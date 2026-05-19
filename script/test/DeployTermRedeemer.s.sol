// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RedeemableToken} from "../../contracts/RedeemableToken.sol";
import {RedeemableTokenFactory} from "../../contracts/RedeemableTokenFactory.sol";
import {TermRedeemerController} from "../../contracts/TermRedeemerController.sol";
import {FeeHooks} from "yieldnest-vault/src/hooks/FeeHooks.sol";
import {MockRateProvider} from "../../test/mocks/MockRateProvider.sol";
import {BaseTestScript} from "./BaseTestScript.s.sol";
import {Contracts} from "./Contracts.sol";

error ProcessorRuleSetupFailed();

contract DeployTermRedeemer is BaseTestScript {
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
        address mockYnRWAx = _loadAddress(Contracts.MOCK_YNRWAX_KEY);

        vm.startBroadcast();

        MockRateProvider provider = new MockRateProvider();
        provider.setRate(Contracts.USDC, Contracts.ONE);
        provider.setRate(mockYnRWAx, Contracts.ONE);

        RedeemableToken implementation = new RedeemableToken();
        RedeemableTokenFactory factory = new RedeemableTokenFactory(address(implementation));
        (RedeemableToken vault, FeeHooks hooks, TermRedeemerController controller) = factory.deploy(
            RedeemableTokenFactory.DeployParams({
                admin: admin,
                provider: address(provider),
                wrappedAsset: address(0),
                redemptionAsset: Contracts.USDC,
                depositToken: mockYnRWAx,
                feeRecipient: admin,
                name: Contracts.TERM_VAULT_NAME,
                symbol: Contracts.TERM_VAULT_SYMBOL,
                decimals: Contracts.VAULT_DECIMALS,
                countNativeAsset: false,
                alwaysComputeTotalAssets: false,
                unrestrictedController: true,
                defaultAssetIndex: Contracts.DEFAULT_ASSET_INDEX,
                lockEnd: uint64(Contracts.TEST_STAGE_TIME),
                redeemStart: uint64(Contracts.TEST_STAGE_TIME)
            })
        );

        _allowProcessorWithdrawAsset(vault, mockYnRWAx, Contracts.USDC);

        vm.stopBroadcast();

        _recordAddress(Contracts.TERM_PROVIDER_KEY, address(provider));
        _recordAddress(Contracts.TERM_IMPLEMENTATION_KEY, address(implementation));
        _recordAddress(Contracts.TERM_FACTORY_KEY, address(factory));
        _recordAddress(Contracts.TERM_VAULT_KEY, address(vault));
        _recordAddress(Contracts.TERM_HOOKS_KEY, address(hooks));
        _recordAddress(Contracts.TERM_CONTROLLER_KEY, address(controller));

        _logAddress(Contracts.TERM_VAULT_LABEL, address(vault));
        _logAddress(Contracts.TERM_HOOKS_LABEL, address(hooks));
        _logAddress(Contracts.TERM_CONTROLLER_LABEL, address(controller));
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
