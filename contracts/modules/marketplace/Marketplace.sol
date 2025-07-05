// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../interfaces/IRegistry.sol';
import '../../interfaces/IGateway.sol';
import '../../interfaces/IPriceOracle.sol';
import '../../interfaces/IAccessControlCenter.sol';
import '../../shared/AccessManaged.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '../../lib/SignatureLib.sol';
import '../../interfaces/CoreDefs.sol';
import '../../errors/Errors.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

// Event payload helper
interface IEventPayload {
    struct MarketplaceEvent {
        bytes32 sku;
        address seller;
        address buyer;
        uint256 price;
        address paymentToken;
        uint256 paymentAmount;
        uint256 timestamp;
        bytes32 listingHash;
        uint16 version;
    }
}

/// @title Marketplace
/// @notice Marketplace working only with off-chain listings via signatures
contract Marketplace is AccessManaged, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // Core contracts
    IRegistry public immutable registry;
    bytes32 public immutable MODULE_ID;
    IGateway public immutable paymentGateway;

    // EIP-712 domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;

    // Listing signature tracking
    mapping(bytes32 => mapping(address => bool)) public consumed;
    mapping(bytes32 => uint256) public minSaltBySku;
    mapping(bytes32 => bool) public revokedListings;

    // Marketplace events
    event MarketplaceSale(
        bytes32 indexed sku,
        address indexed seller,
        address indexed buyer,
        uint256 price,
        address paymentToken,
        uint256 paymentAmount,
        uint256 timestamp,
        bytes32 listingHash,
        bytes32 moduleId
    );

    event ListingRevoked(
        bytes32 indexed sku,
        address indexed seller,
        address buyer,
        uint256 price,
        address paymentToken,
        uint256 paymentAmount,
        uint256 timestamp,
        bytes32 listingHash,
        bytes32 moduleId
    );

    constructor(
        address _registry,
        address _paymentGateway,
        bytes32 moduleId
    ) AccessManaged(IRegistry(_registry).getCoreService(CoreDefs.SERVICE_ACCESS_CONTROL)) {
        registry = IRegistry(_registry);
        MODULE_ID = moduleId;
        paymentGateway = IGateway(_paymentGateway);

        // Create EIP-712 domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(uint256 chainId,address verifyingContract)'),
                block.chainid,
                address(this)
            )
        );
    }

    /// @notice Purchase an item based on an off-chain listing
    /// @param listing Listing structure
    /// @param sellerSignature Seller signature
    /// @param paymentToken Preferred payment token (0 to use listing currency)
    /// @param maxPaymentAmount Maximum allowed payment amount
    function buy(
        SignatureLib.Listing calldata listing,
        bytes calldata sellerSignature,
        address paymentToken,
        uint256 maxPaymentAmount
    ) external nonReentrant {
        // Cheap checks before expensive operations
        if (listing.price == 0) revert InvalidArgument();
        if (listing.seller == address(0)) revert ZeroAddress();

        // Compute listing hash once
        bytes32 buyListingHash = hashListing(listing);

        // Validate listing (signature checked last)
        _validateListing(listing, sellerSignature, buyListingHash);

        // Mark listing as consumed for this buyer
        consumed[buyListingHash][msg.sender] = true;

        // Determine token and amount for payment
        address actualPaymentToken = paymentToken == address(0) ? listing.token : paymentToken;
        uint256 paymentAmount = listing.price;

        // Convert amount if payment token differs from listing token
        if (actualPaymentToken != listing.token) {
            // Check token pair support
            if (!paymentGateway.isPairSupported(MODULE_ID, listing.token, actualPaymentToken)) {
                revert UnsupportedPair();
            }

            // Calculate amount in selected currency
            paymentAmount = paymentGateway.convertAmount(MODULE_ID, listing.token, actualPaymentToken, listing.price);
            if (paymentAmount == 0) revert InvalidPrice();

            // Verify payment amount doesn't exceed maximum limit
            if (maxPaymentAmount > 0 && paymentAmount > maxPaymentAmount) {
                revert PriceExceedsMaximum();
            }
        }

        // Cache addresses to reduce storage reads
        address buyer = msg.sender;
        address seller = listing.seller;

        // Cache if token is native to avoid multiple calls
        bool isNativeToken = actualPaymentToken == address(0) ||
            actualPaymentToken == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

        uint256 netAmount;
        if (isNativeToken) {
            // Process payment with native currency
            netAmount = paymentGateway.processPayment{value: paymentAmount}(
                MODULE_ID,
                address(0), // Use zero address for native currency
                buyer,
                paymentAmount,
                '' // Empty signature for direct payments
            );

            // Transfer native currency to seller
            (bool success, ) = payable(seller).call{value: netAmount}('');
            if (!success) revert RefundDisabled();
        } else {
            // Process payment with ERC20 token
            netAmount = paymentGateway.processPayment(
                MODULE_ID,
                actualPaymentToken,
                buyer,
                paymentAmount,
                '' // Empty signature for direct payments
            );

            // Transfer funds to seller using cached addresses
            IERC20(actualPaymentToken).safeTransfer(seller, netAmount);
        }

        // Emit event directly
        emit MarketplaceSale(
            listing.sku,
            listing.seller,
            msg.sender,
            listing.price,
            actualPaymentToken,
            paymentAmount,
            block.timestamp,
            buyListingHash,
            MODULE_ID
        );
    }

    /// @notice Get item price in a preferred currency
    /// @param listing Listing data
    /// @param preferredCurrency Preferred payment token
    /// @return price Price in the requested currency
    function getPriceInPreferredCurrency(
        SignatureLib.Listing calldata listing,
        address preferredCurrency
    ) external view returns (uint256 price) {
        // Shortcut if currency matches listing token
        if (listing.token == preferredCurrency) {
            return listing.price;
        }

        // Otherwise convert using PaymentGateway
        return paymentGateway.convertAmount(MODULE_ID, listing.token, preferredCurrency, listing.price);
    }

    /// @notice Validate listing parameters
    /// @param listing Listing data
    /// @param skuOnly Skip full validation if true
    /// @return valid Listing validity
    function isListingValid(SignatureLib.Listing calldata listing, bool skuOnly) external view returns (bool valid) {
        // Check expiry
        if (listing.expiry > 0 && listing.expiry < block.timestamp) {
            return false;
        }

        // Check salt for SKU
        if (listing.salt < minSaltBySku[listing.sku]) {
            return false;
        }

        if (skuOnly) {
            return true;
        }

        // Check specific listing revocation
        bytes32 listingHash = hashListing(listing);
        if (revokedListings[listingHash]) {
            return false;
        }

        // Check current chain support
        bool chainSupported = false;
        for (uint256 i = 0; i < listing.chainIds.length; i++) {
            if (listing.chainIds[i] == block.chainid) {
                chainSupported = true;
                break;
            }
        }

        return chainSupported;
    }

    /// @notice Revoke all listings with a given SKU up to the provided salt
    /// @param sku Item SKU
    /// @param minSalt Minimum salt (listings with lower salt are revoked)
    function revokeBySku(bytes32 sku, uint256 minSalt) external {
        minSaltBySku[sku] = minSalt;

        // Emit event directly
        emit ListingRevoked(sku, msg.sender, address(0), 0, address(0), 0, block.timestamp, bytes32(0), MODULE_ID);
    }

    /// @notice Revoke a specific listing
    /// @param listing Listing data
    /// @param sellerSignature Seller signature
    function revokeListing(SignatureLib.Listing calldata listing, bytes calldata sellerSignature) external {
        // Basic checks first
        if (listing.seller == address(0)) revert ZeroAddress();

        // Skip signature if caller is the seller
        if (msg.sender == listing.seller) {
            // Seller can revoke without signature check
            bytes32 currentListingHash = hashListing(listing);
            revokedListings[currentListingHash] = true;

            // Emit event directly
            emit ListingRevoked(
                listing.sku,
                listing.seller,
                address(0),
                0,
                address(0),
                listing.salt,
                block.timestamp,
                currentListingHash,
                MODULE_ID
            );
        }

        // If caller is not the seller verify signature
        bytes32 listingHash = hashListing(listing);

        // Verify signature
        if (sellerSignature.length == 0) revert InvalidSignature();
        address signer = ECDSA.recover(listingHash, sellerSignature);
        if (signer != listing.seller) {
            revert InvalidSignature();
        }

        // Revoke listing
        revokedListings[listingHash] = true;

        emit ListingRevoked(
            listing.sku,
            listing.seller,
            address(0),
            0,
            address(0),
            listing.salt,
            block.timestamp,
            listingHash,
            MODULE_ID
        );
    }

    /// @notice Hash listing according to EIP-712
    /// @param listing Listing data
    /// @return Listing hash with domain separator
    function hashListing(SignatureLib.Listing calldata listing) public view returns (bytes32) {
        bytes32 listingTypeHash = keccak256(
            'Listing(bytes32 sku,address seller,uint256 price,address token,uint256 salt,uint256 expiry,uint256[] chainIds)'
        );

        // Hash chainIds array separately
        bytes32 chainIdsHash = keccak256(abi.encodePacked(listing.chainIds));

        // Build EIP-712 struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                listingTypeHash,
                listing.sku,
                listing.seller,
                listing.price,
                listing.token,
                listing.salt,
                listing.expiry,
                chainIdsHash
            )
        );

        // Final digest for signature
        return keccak256(abi.encodePacked('\x19\x01', DOMAIN_SEPARATOR, structHash));
    }

    /// @dev Validate listing parameters
    function _validateListing(
        SignatureLib.Listing calldata listing,
        bytes calldata sellerSignature,
        bytes32 listingHash
    ) internal view {
        // Optimized validation sequence - start with cheap checks

        // 1. Ensure listing not consumed by this buyer
        if (consumed[listingHash][msg.sender]) {
            revert AlreadyPurchased();
        }

        // 2. Check expiry
        if (listing.expiry > 0 && listing.expiry < block.timestamp) {
            revert Expired();
        }

        // 3. Check global SKU revocation
        if (listing.salt < minSaltBySku[listing.sku]) {
            revert Expired();
        }

        // 4. Check specific listing revocation status
        if (revokedListings[listingHash]) {
            revert Expired();
        }

        // 5. Ensure current chain is supported
        uint256 chainsLen = listing.chainIds.length;
        bool chainSupported = false;
        for (uint256 i = 0; i < chainsLen; i++) {
            if (listing.chainIds[i] == block.chainid) {
                chainSupported = true;
                break;
            }
        }
        if (!chainSupported) {
            revert InvalidChain();
        }

        // 6. Verify signature last (most expensive)
        if (ECDSA.recover(listingHash, sellerSignature) != listing.seller) {
            revert InvalidSignature();
        }
    }

    /// @notice Allows the contract to receive ETH (required for native currency payments)
    receive() external payable {}

    /// @notice Fallback function to reject unintended calls with ETH
    fallback() external payable {
        revert('Use buy() for purchases');
    }
}
