// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../core/CoreSystem.sol';
import '../../pay/interfaces/IPaymentGateway.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '../../lib/SignatureLib.sol';
import '../../core/CoreDefs.sol';
import '../../errors/Errors.sol';

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

// Интерфейс менеджера скидок
interface IDiscountManager {
    struct Discount {
        uint16 discountPercent;
        uint64 startTime;
        uint64 endTime;
        bool active;
    }

    function getDiscount(bytes32 sku) external view returns (Discount memory discount);

    function isDiscountActive(bytes32 sku) external view returns (bool isActive, uint16 percent);

    function getDiscountedPrice(bytes32 sku, uint256 originalPrice) external view returns (uint256 discountedPrice);
}

/// @title Marketplace
/// @notice Marketplace working only with off-chain listings via signatures
contract Marketplace is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // Core system reference
    CoreSystem public immutable core;

    bytes32 public immutable MODULE_ID;
    IPaymentGateway public immutable paymentGateway;

    // EIP-712 domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;

    // Listing signature tracking
    mapping(bytes32 => mapping(address => bool)) public consumed;
    mapping(bytes32 => mapping(address => uint256)) public minSaltBySku;
    mapping(bytes32 => bool) public listingConsumed;
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
    constructor(address _core, address _paymentGateway, bytes32 moduleId) {
        if (_core == address(0)) revert ZeroAddress();
        if (_paymentGateway == address(0)) revert ZeroAddress();

        core = CoreSystem(_core);
        MODULE_ID = moduleId;
        paymentGateway = IPaymentGateway(_paymentGateway);

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
    ) external payable nonReentrant {
        // Cheap checks before expensive operations
        if (listing.price == 0) revert InvalidArgument();
        if (listing.seller == address(0)) revert ZeroAddress();

        // Compute listing hash once
        bytes32 buyListingHash = hashListing(listing);

        // Validate listing (signature checked last)
        _validateListing(listing, sellerSignature, buyListingHash);

        // Mark listing as consumed
        consumed[buyListingHash][msg.sender] = true;
        listingConsumed[buyListingHash] = true;
        revokedListings[buyListingHash] = true;

        // Determine token and amount for payment
        address actualPaymentToken = paymentToken == address(0) ? listing.token : paymentToken;

        uint256 paymentAmount = listing.price;

        if (maxPaymentAmount > 0 && actualPaymentToken == listing.token && listing.price > maxPaymentAmount) {
            revert PriceExceedsMaximum();
        }

        // Convert amount if payment token differs from listing token
        if (actualPaymentToken != listing.token) {
            if (!paymentGateway.isPairSupported(MODULE_ID, listing.token, actualPaymentToken)) {
                revert UnsupportedPair();
            }

            paymentAmount = paymentGateway.convertAmount(MODULE_ID, listing.token, actualPaymentToken, listing.price);
            if (paymentAmount == 0) revert InvalidPrice();

            if (maxPaymentAmount > 0 && paymentAmount > maxPaymentAmount) {
                revert PriceExceedsMaximum();
            }
        }

        address buyer = msg.sender;
        address seller = listing.seller;

        bool isNativeToken = actualPaymentToken == address(0) ||
            actualPaymentToken == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

        uint256 netAmount;
        if (isNativeToken) {
            if (msg.value < paymentAmount) revert InsufficientBalance();

            netAmount = paymentGateway.processPayment{value: paymentAmount}(
                MODULE_ID,
                address(0),
                buyer,
                paymentAmount,
                ''
            );

            (bool success, ) = payable(seller).call{value: netAmount}('');
            if (!success) revert RefundDisabled();

            uint256 excess = msg.value - paymentAmount;
            if (excess > 0) {
                (bool refundSuccess, ) = payable(buyer).call{value: excess}('');
                if (!refundSuccess) revert RefundDisabled();
            }
        } else {
            netAmount = paymentGateway.processPayment(MODULE_ID, actualPaymentToken, buyer, paymentAmount, '');

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
        if (listing.salt < minSaltBySku[listing.sku][listing.seller]) {
            return false;
        }

        if (skuOnly) {
            return true;
        }

        bytes32 listingHash = hashListing(listing);
        if (listingConsumed[listingHash] || revokedListings[listingHash]) {
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
        minSaltBySku[sku][msg.sender] = minSalt;

        emit ListingRevoked(sku, msg.sender, address(0), 0, address(0), 0, block.timestamp, bytes32(0), MODULE_ID);
    }

    /// @notice Revoke a specific listing
    /// @param listing Listing data
    /// @param sellerSignature Seller signature
    function revokeListing(SignatureLib.Listing calldata listing, bytes calldata sellerSignature) external {
        if (listing.seller == address(0)) revert ZeroAddress();
        if (msg.sender != listing.seller) revert NotSeller();

        bytes32 listingHash = hashListing(listing);
        if (sellerSignature.length > 0) {
            if (ECDSA.recover(listingHash, sellerSignature) != listing.seller) {
                revert InvalidSignature();
            }
        }
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
        // Используем реализацию из SignatureLib для согласованности
        return SignatureLib.hashListing(listing, DOMAIN_SEPARATOR);
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

        // 2. Check expiry (0 = бессрочный листинг)
        if (listing.expiry > 0 && listing.expiry < block.timestamp) {
            revert Expired();
        }

        // 3. Check global SKU revocation
        if (listing.salt < minSaltBySku[listing.sku][listing.seller]) {
            revert Expired();
        }

        if (listingConsumed[listingHash] || revokedListings[listingHash]) {
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
