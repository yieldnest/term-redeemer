// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IERC20MetadataMinimal is IERC20Minimal {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
}

interface IMaxVault is IERC20MetadataMinimal {
    function asset() external view returns (address);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function withdrawAsset(uint256 assets, address receiver) external returns (uint256 sharesBurned);
}

contract ERC20Base is IERC20MetadataMinimal {
    string public override name;
    string public override symbol;
    uint8 public immutable override decimals;

    uint256 public override totalSupply;

    mapping(address account => uint256) public override balanceOf;
    mapping(address owner => mapping(address spender => uint256)) public override allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= value, "ERC20: insufficient allowance");
            allowance[from][msg.sender] = allowed - value;
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }

        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(to != address(0), "ERC20: transfer to zero");

        uint256 fromBalance = balanceOf[from];
        require(fromBalance >= value, "ERC20: insufficient balance");

        unchecked {
            balanceOf[from] = fromBalance - value;
            balanceOf[to] += value;
        }

        emit Transfer(from, to, value);
    }

    function _mint(address to, uint256 value) internal {
        require(to != address(0), "ERC20: mint to zero");

        totalSupply += value;
        balanceOf[to] += value;

        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        uint256 fromBalance = balanceOf[from];
        require(fromBalance >= value, "ERC20: insufficient balance");

        unchecked {
            balanceOf[from] = fromBalance - value;
            totalSupply -= value;
        }

        emit Transfer(from, address(0), value);
    }
}

    contract Ownable {
        address public owner;

        event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

        modifier onlyOwner() {
            require(msg.sender == owner, "Ownable: unauthorized");
            _;
        }

        constructor(address initialOwner) {
            require(initialOwner != address(0), "Ownable: zero owner");
            owner = initialOwner;
            emit OwnershipTransferred(address(0), initialOwner);
        }

        function transferOwnership(address newOwner) external onlyOwner {
            require(newOwner != address(0), "Ownable: zero owner");
            emit OwnershipTransferred(owner, newOwner);
            owner = newOwner;
        }
    }

    contract TermReceiptToken is ERC20Base {
        address public immutable minter;

        modifier onlyMinter() {
            require(msg.sender == minter, "Receipt: unauthorized");
            _;
        }

        constructor(string memory name_, string memory symbol_, uint8 decimals_, address minter_)
            ERC20Base(name_, symbol_, decimals_)
        {
            minter = minter_;
        }

        function mint(address to, uint256 value) external onlyMinter {
            _mint(to, value);
        }

        function burn(address from, uint256 value) external onlyMinter {
            _burn(from, value);
        }
    }

    contract TermRedeemer is Ownable {
        struct Schedule {
            uint64 lockStart;
            uint64 lockEnd;
            uint64 redeemStart;
        }

        IMaxVault public immutable vault;
        IERC20Minimal public immutable asset;
        TermReceiptToken public immutable receiptToken;
        address public immutable residualSharesSpender;
        uint256 public immutable shareScale;
        Schedule public schedule;

        uint256 public lockedAssetPerShare;
        bool public rateLocked;
        bool public redemptionPrepared;

        event Locked(address indexed account, address indexed receiver, uint256 shareAmount);
        event RedemptionRateLocked(uint256 assetPerShare);
        event RedemptionPrepared(uint256 assetsWithdrawn, uint256 residualSharesApproved);
        event Redeemed(address indexed account, address indexed receiver, uint256 receiptAmount, uint256 assetAmount);

        constructor(
            address owner_,
            address vault_,
            address residualSharesSpender_,
            uint64 lockStart_,
            uint64 lockEnd_,
            uint64 redeemStart_
        ) Ownable(owner_) {
            require(vault_ != address(0), "TermRedeemer: zero vault");
            require(residualSharesSpender_ != address(0), "TermRedeemer: zero spender");
            require(lockStart_ < lockEnd_, "TermRedeemer: invalid lock window");
            require(lockEnd_ <= redeemStart_, "TermRedeemer: invalid redeem time");

            vault = IMaxVault(vault_);
            asset = IERC20Minimal(IMaxVault(vault_).asset());
            residualSharesSpender = residualSharesSpender_;
            schedule = Schedule({lockStart: lockStart_, lockEnd: lockEnd_, redeemStart: redeemStart_});

            uint8 shareDecimals = IERC20MetadataMinimal(vault_).decimals();
            shareScale = 10 ** uint256(shareDecimals);

            receiptToken = new TermReceiptToken(
                string.concat("Withdrawable ", IERC20MetadataMinimal(vault_).name()),
                string.concat("w", IERC20MetadataMinimal(vault_).symbol()),
                shareDecimals,
                address(this)
            );
        }

        function lock(uint256 shareAmount, address receiver) external returns (uint256 receiptAmount) {
            require(block.timestamp >= schedule.lockStart, "TermRedeemer: lock not started");
            require(block.timestamp < schedule.lockEnd, "TermRedeemer: lock closed");
            require(receiver != address(0), "TermRedeemer: zero receiver");
            require(shareAmount > 0, "TermRedeemer: zero amount");

            receiptAmount = shareAmount;
            require(vault.transferFrom(msg.sender, address(this), shareAmount), "TermRedeemer: share transfer failed");
            receiptToken.mint(receiver, receiptAmount);

            emit Locked(msg.sender, receiver, shareAmount);
        }

        function lockRedemptionRate() public returns (uint256 assetPerShare) {
            require(block.timestamp >= schedule.lockEnd, "TermRedeemer: lock window active");
            require(!rateLocked, "TermRedeemer: rate locked");

            assetPerShare = vault.convertToAssets(shareScale);
            require(assetPerShare > 0, "TermRedeemer: zero rate");

            lockedAssetPerShare = assetPerShare;
            rateLocked = true;

            emit RedemptionRateLocked(assetPerShare);
        }

        function prepareRedemption() external onlyOwner returns (uint256 assetsNeeded, uint256 residualShares) {
            require(block.timestamp >= schedule.redeemStart, "TermRedeemer: redeem not started");
            require(!redemptionPrepared, "TermRedeemer: redemption prepared");

            if (!rateLocked) {
                lockRedemptionRate();
            }

            assetsNeeded = previewAssetsOwed(receiptToken.totalSupply());
            if (assetsNeeded > 0) {
                vault.withdrawAsset(assetsNeeded, address(this));
            }

            residualShares = vault.balanceOf(address(this));
            require(vault.approve(residualSharesSpender, residualShares), "TermRedeemer: approve failed");

            redemptionPrepared = true;

            emit RedemptionPrepared(assetsNeeded, residualShares);
        }

        function redeem(uint256 receiptAmount, address receiver) external returns (uint256 assetAmount) {
            require(block.timestamp >= schedule.redeemStart, "TermRedeemer: redeem not started");
            require(rateLocked, "TermRedeemer: rate not locked");
            require(receiver != address(0), "TermRedeemer: zero receiver");
            require(receiptAmount > 0, "TermRedeemer: zero amount");

            assetAmount = previewAssetsOwed(receiptAmount);
            receiptToken.burn(msg.sender, receiptAmount);
            require(asset.transfer(receiver, assetAmount), "TermRedeemer: asset transfer failed");

            emit Redeemed(msg.sender, receiver, receiptAmount, assetAmount);
        }

        function previewAssetsOwed(uint256 receiptAmount) public view returns (uint256) {
            return receiptAmount * lockedAssetPerShare / shareScale;
        }
    }
