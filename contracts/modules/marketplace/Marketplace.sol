// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../core/Registry.sol";
import "../../interfaces/IGateway.sol";
import "../../core/AccessControlCenter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../lib/SignatureLib.sol";

/// @title Marketplace
/// @notice Minimal marketplace example demonstrating registration of sales and
/// payment processing via the PaymentGateway core service.
contract Marketplace {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    Registry public immutable registry;
    bytes32 public immutable MODULE_ID;

    struct OnchainListing {
        address seller;
        address token;
        uint256 price;
        bool active;
    }


    uint256 public nextId;
    mapping(uint256 => OnchainListing) public listings;

    mapping(bytes32 => mapping(address => bool)) public consumed;

    bytes32 public DOMAIN_SEPARATOR;

    event Listed(uint256 indexed id, address indexed seller, address token, uint256 price);
    event Sold(uint256 indexed id, address indexed buyer);
    event ListingPurchased(address indexed buyer, bytes32 listingHash, uint256 chainId);

    constructor(address _registry, address paymentGateway, bytes32 moduleId) {
        registry = Registry(_registry);
        MODULE_ID = moduleId;
        registry.setModuleServiceAlias(MODULE_ID, "PaymentGateway", paymentGateway);

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(uint256 chainId,address verifyingContract)"),
                block.chainid,
                address(this)
            )
        );

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
        listings[id] = OnchainListing(msg.sender, token, price, true);
        emit Listed(id, msg.sender, token, price);
    }

    /// @notice Purchase a listed item, paying through PaymentGateway
    function buy(uint256 id) external {
        OnchainListing storage l = listings[id];
        require(l.active, "not listed");

        uint256 netAmount = IGateway(
            registry.getModuleService(MODULE_ID, keccak256(bytes("PaymentGateway")))
        ).processPayment(MODULE_ID, l.token, msg.sender, l.price, "");

        IERC20(l.token).safeTransfer(l.seller, netAmount);

        l.active = false;
        emit Sold(id, msg.sender);
    }

    /// @notice Purchase a lazily listed item using EIP-712 signature
    function buy(SignatureLib.Listing calldata listing, bytes calldata sigSeller) external {
        bytes32 listingHash = hashListing(listing);
        require(
            listingHash.recover(sigSeller) == listing.seller,
            "invalid signature"
        );
        require(!consumed[listingHash][msg.sender], "already purchased");
        require(
            listing.expiry == 0 || listing.expiry >= block.timestamp,
            "expired"
        );
        bool chainAllowed = false;
        for (uint256 i = 0; i < listing.chainIds.length; i++) {
            if (listing.chainIds[i] == block.chainid) {
                chainAllowed = true;
                break;
            }
        }
        require(chainAllowed, "invalid chain");

        uint256 netAmount = IGateway(
            registry.getModuleService(MODULE_ID, keccak256(bytes("PaymentGateway")))
        ).processPayment(MODULE_ID, listing.token, msg.sender, listing.price, "");

        IERC20(listing.token).safeTransfer(listing.seller, netAmount);

        consumed[listingHash][msg.sender] = true;
        emit ListingPurchased(msg.sender, listingHash, block.chainid);
    }

    function hashListing(SignatureLib.Listing calldata listing) public view returns (bytes32) {
        bytes32 structHash = SignatureLib.hashListing(listing);
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }
}
