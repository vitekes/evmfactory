// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {PaymentGateway} from "contracts/core/PaymentGateway.sol";
import {CoreFeeManager} from "contracts/core/CoreFeeManager.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";
import {TestHelper} from "./TestHelper.sol";

contract AlwaysValidator {
    function isAllowed(address) external pure returns (bool) { return true; }
}

contract GatewayModuleFeeFuzzTest is Test {
    PaymentGateway gateway;
    CoreFeeManager fee;
    MockRegistry registry;
    AccessControlCenter acc;
    AlwaysValidator validator;
    TestToken token;

    bytes32 constant PROCESS_TYPEHASH = keccak256("ProcessPayment(address payer,bytes32 moduleId,address token,uint256 amount,uint256 nonce,uint256 chainId)");
    uint256 constant SECP256K1N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    function setUp() public {
        acc = new AccessControlCenter();
        acc.initialize(address(this));
        vm.startPrank(address(this));
        registry = new MockRegistry();
        registry.setCoreService(keccak256(bytes("AccessControlCenter")), address(acc));

        fee = new CoreFeeManager();
        fee.initialize(address(acc));

        gateway = new PaymentGateway();
        gateway.initialize(address(acc), address(registry), address(fee));

        validator = new AlwaysValidator();
        address[] memory gov;
        address[] memory fo = new address[](2);
        fo[0] = address(this);
        fo[1] = address(gateway);
        address[] memory mods;
        TestHelper.setupAclAndRoles(acc, gov, fo, mods);
        token = new TestToken("Test", "TST");
        vm.stopPrank();
    }

    function _sign(uint256 pk, address payer, bytes32 moduleId, uint256 amount) internal view returns (bytes memory) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                gateway.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        PROCESS_TYPEHASH,
                        payer,
                        moduleId,
                        address(token),
                        amount,
                        gateway.nonces(payer),
                        block.chainid
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function testFuzzModuleFee(bytes32 moduleId, uint16 feeBps, uint128 amount, uint256 pk) public {
        pk = bound(pk, 1, SECP256K1N - 1);
        feeBps = uint16(bound(feeBps, 0, 10000));
        amount = uint128(bound(amount, 1, 1e18));

        address payer = vm.addr(pk);
        token.transfer(payer, amount);
        vm.prank(payer);
        token.approve(address(gateway), amount);

        registry.setModuleServiceAlias(moduleId, "Validator", address(validator));
        registry.setModuleServiceAlias(moduleId, "PaymentGateway", address(gateway));
        fee.setPercentFee(moduleId, address(token), feeBps);

        bytes memory sig = _sign(pk, payer, moduleId, amount);
        uint256 payerBefore = token.balanceOf(payer);

        acc.grantRole(acc.FEATURE_OWNER_ROLE(), payer);
        vm.prank(payer);
        uint256 net = gateway.processPayment(moduleId, address(token), payer, amount, sig);

        uint256 feeAmt = (amount * feeBps) / 10000;
        assertEq(net, amount - feeAmt, "net mismatch");
        assertEq(token.balanceOf(payer), payerBefore - feeAmt, "payer balance incorrect");
    }
}
