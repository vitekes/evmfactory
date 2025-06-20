// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../core/Registry.sol';
import '../../interfaces/IGateway.sol';
import '../../core/AccessControlCenter.sol';
import '../../shared/AccessManaged.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '../../lib/SignatureLib.sol';
import '../../interfaces/CoreDefs.sol';
import '../../errors/Errors.sol';

/// @title Marketplace
/// @notice Minimal marketplace example demonstrating registration of sales and
/// payment processing via the PaymentGateway core service.
contract Marketplace is AccessManaged {
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

    event MarketplaceListingCreated(uint256 indexed id, address indexed seller, address token, uint256 price);
    event MarketplaceListingSold(uint256 indexed id, address indexed buyer);
    event MarketplaceListingPurchased(address indexed buyer, bytes32 listingHash, uint256 chainId);
    /// @notice Emitted when a listing price is updated
    /// @param hash Listing identifier hash
    /// @param oldPrice Previous price
    /// @param newPrice New price value
    event ListingUpdated(bytes32 indexed hash, uint256 oldPrice, uint256 newPrice);

    constructor(
        address _registry,
        address paymentGateway,
        bytes32 moduleId
    ) AccessManaged(Registry(_registry).getCoreService(keccak256('AccessControlCenter'))) {
        registry = Registry(_registry);
        MODULE_ID = moduleId;
        registry.setModuleServiceAlias(MODULE_ID, 'PaymentGateway', paymentGateway);

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(uint256 chainId,address verifyingContract)'),
                block.chainid,
                address(this)
            )
        );

        AccessControlCenter acl = AccessControlCenter(_ACC);
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = acl.MODULE_ROLE();
        roles[1] = acl.FEATURE_OWNER_ROLE();
        _grantSelfRoles(roles);
    }

    /// @notice Put an item for sale
    function list(address token, uint256 price) external returns (uint256 id) {
        id = nextId++;
        listings[id] = OnchainListing(msg.sender, token, price, true);
        emit MarketplaceListingCreated(id, msg.sender, token, price);
    }

    /// @notice Update price for an existing listing
    /// @param id Listing identifier
    /// @param newPrice New price value
    function updateListingPrice(uint256 id, uint256 newPrice) external {
        OnchainListing storage l = listings[id];
        if (l.seller != msg.sender) revert NotSeller();
        uint256 oldPrice = l.price;
        l.price = newPrice;
        bytes32 hash = keccak256(abi.encodePacked(id, l.seller, l.token));
        emit ListingUpdated(hash, oldPrice, newPrice);
    }

    /// @notice Purchase a listed item, paying through PaymentGateway
    function buy(uint256 id) external {
        OnchainListing storage l = listings[id];
        if (!l.active) revert NotListed();

        uint256 netAmount = IGateway(registry.getModuleService(MODULE_ID, CoreDefs.SERVICE_PAYMENT_GATEWAY))
            .processPayment(MODULE_ID, l.token, msg.sender, l.price, '');

        IERC20(l.token).safeTransfer(l.seller, netAmount);

        l.active = false;
        emit MarketplaceListingSold(id, msg.sender);
    }
    /// @notice Purchase a lazily listed item using EIP-712 signature
    function buy(SignatureLib.Listing calldata listing, bytes calldata sigSeller) external {
        bytes32 listingHash = hashListing(listing);
        if (listingHash.recover(sigSeller) != listing.seller) revert InvalidSignature();
        if (consumed[listingHash][msg.sender]) revert AlreadyPurchased();
        if (!(listing.expiry == 0 || listing.expiry >= block.timestamp)) revert Expired();
        bool chainAllowed = false;
        for (uint256 i = 0; i < listing.chainIds.length; i++) {
            if (listing.chainIds[i] == block.chainid) {
                chainAllowed = true;
                break;
            }
        }
        if (!chainAllowed) revert InvalidChain();

        uint256 netAmount = IGateway(registry.getModuleService(MODULE_ID, CoreDefs.SERVICE_PAYMENT_GATEWAY))
            .processPayment(MODULE_ID, listing.token, msg.sender, listing.price, '');

        IERC20(listing.token).safeTransfer(listing.seller, netAmount);

        consumed[listingHash][msg.sender] = true;
        emit MarketplaceListingPurchased(msg.sender, listingHash, block.chainid);
    }

    function hashListing(SignatureLib.Listing calldata listing) public view returns (bytes32) {
        return SignatureLib.hashListing(listing, DOMAIN_SEPARATOR);
    }
}
