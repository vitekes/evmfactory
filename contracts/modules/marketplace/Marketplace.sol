// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../core/Registry.sol";
import "../../core/PaymentGateway.sol";

/// @title Marketplace
/// @notice Minimal marketplace example demonstrating registration of sales and
/// payment processing via the PaymentGateway core service.
contract Marketplace {
    Registry public immutable registry;
    bytes32 public constant MODULE_ID = keccak256("Marketplace");

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

    constructor(address _registry) {
        registry = Registry(_registry);
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

        PaymentGateway(
            registry.getModuleService(MODULE_ID, keccak256(bytes("PaymentGateway")))
        ).processPayment(MODULE_ID, l.token, msg.sender, l.price);

        l.active = false;
        emit Sold(id, msg.sender);
    }
}
