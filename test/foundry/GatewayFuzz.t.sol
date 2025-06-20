// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {PaymentGateway} from "contracts/core/PaymentGateway.sol";
import {CoreFeeManager} from "contracts/core/CoreFeeManager.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";
import {TestHelper} from "./TestHelper.sol";

contract MockValidator {
    function isAllowed(address) external pure returns (bool) { return true; }
}

contract GatewayFuzzTest is Test {
    PaymentGateway gateway;
    CoreFeeManager fee;
    MockRegistry registry;
    AccessControlCenter acc;
    MockValidator validator;
    TestToken token;

    bytes32 constant MODULE_ID = keccak256("Core");
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

        acc.grantRole(acc.FEATURE_OWNER_ROLE(), address(gateway));
        acc.grantRole(acc.GOVERNOR_ROLE(), address(validator));

        validator = new MockValidator();
        registry.setModuleServiceAlias(MODULE_ID, "Validator", address(validator));
        registry.setModuleServiceAlias(MODULE_ID, "PaymentGateway", address(gateway));

        address[] memory gov;
        address[] memory fo = new address[](1);
        fo[0] = address(this);
        address[] memory mods;
        TestHelper.setupAclAndRoles(acc, gov, fo, mods);
        vm.stopPrank();

        token = new TestToken("Test", "TST");
    }

    function _sign(uint256 pk, address payer, uint256 amount) internal view returns (bytes memory) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                gateway.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        PROCESS_TYPEHASH,
                        payer,
                        MODULE_ID,
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

    function testFuzzValidRelayedPayment(uint256 pkPayer, uint256 pkSender, uint128 amount) public {
        pkPayer = bound(pkPayer, 1, SECP256K1N - 1);
        pkSender = bound(pkSender, 1, SECP256K1N - 1);
        vm.assume(pkSender != pkPayer);
        amount = uint128(bound(amount, 1, 1e18));

        address payer = vm.addr(pkPayer);
        address relayer = vm.addr(pkSender);

        token.transfer(payer, amount);
        vm.prank(payer);
        token.approve(address(gateway), amount);

        bytes memory sig = _sign(pkPayer, payer, amount);

        acc.grantRole(acc.FEATURE_OWNER_ROLE(), relayer);
        vm.prank(relayer);
        gateway.processPayment(MODULE_ID, address(token), payer, amount, sig);
    }

    function testFuzzInvalidRelayedPayment(uint256 pkPayer, uint256 pkSender, uint128 amount) public {
        pkPayer = bound(pkPayer, 1, SECP256K1N - 1);
        pkSender = bound(pkSender, 1, SECP256K1N - 1);
        vm.assume(pkSender != pkPayer);
        amount = uint128(bound(amount, 1, 1e18));

        address payer = vm.addr(pkPayer);
        address relayer = vm.addr(pkSender);

        token.transfer(payer, amount);
        vm.prank(payer);
        token.approve(address(gateway), amount);

        bytes memory sig = _sign(pkSender, payer, amount);

        acc.grantRole(acc.FEATURE_OWNER_ROLE(), relayer);
        vm.prank(relayer);
        vm.expectRevert("InvalidSignature()");
        gateway.processPayment(MODULE_ID, address(token), payer, amount, sig);
    }
}

