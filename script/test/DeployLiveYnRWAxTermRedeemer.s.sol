// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RedeemableToken} from "../../contracts/RedeemableToken.sol";
import {YnRwaRateProvider} from "../../contracts/YnRwaRateProvider.sol";
import {FeeHooks} from "yieldnest-vault/src/hooks/FeeHooks.sol";
import {BaseTestScript} from "./BaseTestScript.s.sol";
import {Contracts} from "./Contracts.sol";
import {Constants} from "./Constants.sol";
import {TestRedeemableTokenFactory} from "./utils/TestRedeemableTokenFactory.sol";
import {TestTermRedeemerController} from "./utils/TestTermRedeemerController.sol";

error ProcessorRuleSetupFailed();

/// @notice Example:
/// SENDER=0xYourAddress ACCOUNT=your-keystore-name forge script script/test/DeployLiveYnRWAxTermRedeemer.s.sol:DeployLiveYnRWAxTermRedeemer --rpc-url $ETH_MAINNET_RPC_URL --account $ACCOUNT --sender $SENDER --broadcast --slow --verify --etherscan-api-key $ETHERSCAN_API_KEY
contract DeployLiveYnRWAxTermRedeemer is BaseTestScript {
    struct ParamRule {
        uint8 paramType;
        bool isArray;
        address[] allowList;
    }

    struct FunctionRule {
        bool isActive;
        ParamRule[] paramRules;
        address validator;
    }

    function run() external {
        address admin = _broadcaster();
        address liveYnRWAx = Contracts.YNRWAX;

        vm.startBroadcast();

        YnRwaRateProvider provider = new YnRwaRateProvider(Contracts.WRAPPED_USDC, Contracts.USDC, liveYnRWAx);

        RedeemableToken implementation = new RedeemableToken();
        TestRedeemableTokenFactory factory = new TestRedeemableTokenFactory(address(implementation));
        (RedeemableToken vault, FeeHooks hooks, TestTermRedeemerController controller) = factory.deploy(
            TestRedeemableTokenFactory.DeployParams({
                admin: admin,
                provider: address(provider),
                wrappedAsset: Contracts.WRAPPED_USDC,
                redemptionAsset: Contracts.USDC,
                depositToken: liveYnRWAx,
                feeRecipient: admin,
                name: Constants.LIVE_TERM_VAULT_NAME,
                symbol: Constants.LIVE_TERM_VAULT_SYMBOL,
                decimals: Constants.VAULT_DECIMALS,
                countNativeAsset: false,
                alwaysComputeTotalAssets: false,
                defaultAssetIndex: Constants.DEFAULT_ASSET_INDEX
            })
        );

        _allowProcessorWithdrawAsset(vault, liveYnRWAx, Contracts.USDC);

        vm.stopBroadcast();

        string[] memory keys = new string[](7);
        address[] memory values = new address[](7);
        keys[0] = Constants.TERM_PROVIDER_KEY;
        values[0] = address(provider);
        keys[1] = Constants.TERM_IMPLEMENTATION_KEY;
        values[1] = address(implementation);
        keys[2] = Constants.TERM_FACTORY_KEY;
        values[2] = address(factory);
        keys[3] = Constants.TERM_VAULT_KEY;
        values[3] = address(vault);
        keys[4] = Constants.TERM_HOOKS_KEY;
        values[4] = address(hooks);
        keys[5] = Constants.TERM_CONTROLLER_KEY;
        values[5] = address(controller);
        keys[6] = "depositToken";
        values[6] = liveYnRWAx;
        _writeAddresses(Constants.LIVE_TERM_NAMESPACE, keys, values);

        _logAddress(Constants.TERM_VAULT_LABEL, address(vault));
        _logAddress(Constants.TERM_HOOKS_LABEL, address(hooks));
        _logAddress(Constants.TERM_CONTROLLER_LABEL, address(controller));
    }

    function _allowProcessorWithdrawAsset(RedeemableToken vault, address target, address redemptionAsset) internal {
        address[] memory vaultAllowList = new address[](1);
        vaultAllowList[0] = address(vault);
        address[] memory assetAllowList = new address[](1);
        assetAllowList[0] = redemptionAsset;
        ParamRule[] memory paramRules = new ParamRule[](4);
        paramRules[0] = ParamRule({paramType: 1, isArray: false, allowList: assetAllowList});
        paramRules[2] = ParamRule({paramType: 1, isArray: false, allowList: vaultAllowList});
        paramRules[3] = ParamRule({paramType: 1, isArray: false, allowList: vaultAllowList});
        FunctionRule memory rule = FunctionRule({isActive: true, paramRules: paramRules, validator: address(0)});

        (bool ok,) = address(vault).call(
            abi.encodeWithSignature(
                "setProcessorRule(address,bytes4,(bool,(uint8,bool,address[])[],address))",
                target,
                bytes4(keccak256("withdrawAsset(address,uint256,address,address)")),
                rule
            )
        );
        if (!ok) {
            revert ProcessorRuleSetupFailed();
        }
    }
}
