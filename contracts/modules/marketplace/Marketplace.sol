// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../core/Registry.sol";
import "../../core/PaymentGateway.sol";
import "../../core/AccessControlCenter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Marketplace
/// @notice Minimal marketplace example demonstrating registration of sales and
/// payment processing via the PaymentGateway core service.
contract Marketplace {
    using SafeERC20 for IERC20;
    Registry public immutable registry;
    bytes32 public immutable MODULE_ID;

    struct Listing {
        address seller;
        address token;
        uint256 price;
        bool active;
    }

    uint256 public nextId;
    mapping(uint256 => Listing) public listings;

    event Listed(uint256 indexed id, address indexed seller, address token, uint256 price);
    event Sold(uint256 indexed id, address indexed buyer);

    constructor(address _registry, address paymentGateway, bytes32 moduleId) {
        registry = Registry(_registry);
        MODULE_ID = moduleId;
        registry.setModuleServiceAlias(MODULE_ID, "PaymentGateway", paymentGateway);

        AccessControlCenter acl = AccessControlCenter(
            registry.getCoreService(keccak256("AccessControlCenter"))
        );
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = acl.MODULE_ROLE();
        roles[1] = acl.FEATURE_OWNER_ROLE();
        acl.grantMultipleRoles(address(this), roles);
    }

    /// @notice Put an item for sale
    function list(address token, uint256 price) external returns (uint256 id) {
        id = nextId++;
        listings[id] = Listing(msg.sender, token, price, true);
        emit Listed(id, msg.sender, token, price);
    }

    /// @notice Purchase a listed item, paying through PaymentGateway
    function buy(uint256 id) external {
        Listing storage l = listings[id];
        require(l.active, "not listed");

        uint256 netAmount = PaymentGateway(
            registry.getModuleService(MODULE_ID, keccak256(bytes("PaymentGateway")))
        ).processPayment(MODULE_ID, l.token, msg.sender, l.price, "");

        IERC20(l.token).safeTransfer(l.seller, netAmount);

        l.active = false;
        emit Sold(id, msg.sender);
    }
}
