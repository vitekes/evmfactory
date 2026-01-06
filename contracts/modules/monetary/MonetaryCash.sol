// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../core/CoreSystem.sol';
import '../../core/CoreDefs.sol';
import '../../errors/Errors.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts/utils/cryptography/EIP712.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/// @title MonetaryCash
/// @notice Escrow for promo cash claims authorized by backend signatures
contract MonetaryCash is EIP712, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum CashStatus {
        None,
        Active,
        Activated,
        Cancelled
    }

    struct Cash {
        address token;
        uint128 amount;
        uint64 expiresAt;
        uint64 createdAt;
        CashStatus status;
        address creator;
    }

    bytes32 public constant ACTIVATE_TYPEHASH =
        keccak256('ActivateCash(uint256 cashId,address recipient,uint256 deadline)');

    string private constant SIGNING_DOMAIN = 'MonetaryCash';
    string private constant SIGNATURE_VERSION = '1';

    CoreSystem public immutable core;
    bytes32 public immutable MODULE_ID;
    address public backendSigner;

    uint256 private cashCounter;
    mapping(uint256 => Cash) private cashes;

    event MonetaryCashCreated(
        address indexed creator,
        uint256 indexed cashId,
        address token,
        uint256 amount,
        uint64 expiresAt
    );
    event MonetaryCashActivated(address indexed recipient, uint256 indexed cashId);
    event MonetaryCashCancelled(address indexed operator, uint256 indexed cashId);
    event BackendSignerUpdated(address indexed previousSigner, address indexed newSigner);

    constructor(address coreAddress, bytes32 moduleId, address signer) EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) {
        if (coreAddress == address(0)) revert ZeroAddress();
        if (signer == address(0)) revert InvalidAddress();

        core = CoreSystem(coreAddress);
        MODULE_ID = moduleId;
        backendSigner = signer;
    }

    modifier onlyAdminOrFeatureOwner() {
        if (
            !core.hasRole(CoreDefs.FEATURE_OWNER_ROLE, msg.sender) &&
            !core.hasRole(0x00, msg.sender)
        ) {
            revert NotFeatureOwner();
        }
        _;
    }

    function createCash(address token, uint256 amount, uint64 expiresAt) external payable onlyAdminOrFeatureOwner nonReentrant returns (uint256 cashId) {
        if (amount == 0) revert InvalidAmount();
        if (amount > type(uint128).max) revert InvalidParameters();
        if (expiresAt != 0 && expiresAt <= block.timestamp) revert InvalidParameters();

        uint256 received = amount;
        if (token == address(0)) {
            if (msg.value != amount) revert InvalidAmount();
        } else {
            if (msg.value != 0) revert InvalidAmount();
            uint256 balanceBefore = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            received = IERC20(token).balanceOf(address(this)) - balanceBefore;
            if (received == 0) revert InvalidAmount();
            if (received > type(uint128).max) revert InvalidParameters();
        }

        cashId = ++cashCounter;
        Cash storage entry = cashes[cashId];
        entry.token = token;
        entry.amount = uint128(received);
        entry.expiresAt = expiresAt;
        entry.createdAt = uint64(block.timestamp);
        entry.status = CashStatus.Active;
        entry.creator = msg.sender;

        emit MonetaryCashCreated(msg.sender, cashId, token, received, expiresAt);
    }

    function activateCashWithSig(
        uint256 cashId,
        address recipient,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();
        if (deadline != 0 && block.timestamp > deadline) revert Expired();

        Cash storage entry = cashes[cashId];
        if (entry.status == CashStatus.None) revert NotFound();
        if (entry.status != CashStatus.Active) revert InvalidState();
        if (entry.expiresAt != 0 && block.timestamp > entry.expiresAt) revert Expired();

        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(ACTIVATE_TYPEHASH, cashId, recipient, deadline))
        );
        address signer = ECDSA.recover(digest, signature);
        if (signer != backendSigner) revert InvalidSignature();

        entry.status = CashStatus.Activated;

        if (entry.token == address(0)) {
            (bool success, ) = payable(recipient).call{value: entry.amount}('');
            if (!success) revert TransferFailed();
        } else {
            IERC20(entry.token).safeTransfer(recipient, entry.amount);
        }

        emit MonetaryCashActivated(recipient, cashId);
    }

    function cancelCash(uint256 cashId) external onlyAdminOrFeatureOwner nonReentrant {
        Cash storage entry = cashes[cashId];
        if (entry.status == CashStatus.None) revert NotFound();
        if (entry.status != CashStatus.Active) revert InvalidState();

        entry.status = CashStatus.Cancelled;
        _refund(entry.creator, entry.token, entry.amount);

        emit MonetaryCashCancelled(msg.sender, cashId);
    }

    function withdrawExpired(uint256 cashId) external onlyAdminOrFeatureOwner nonReentrant {
        Cash storage entry = cashes[cashId];
        if (entry.status == CashStatus.None) revert NotFound();
        if (entry.status != CashStatus.Active) revert InvalidState();
        if (entry.expiresAt == 0 || block.timestamp <= entry.expiresAt) revert InvalidState();

        entry.status = CashStatus.Cancelled;
        _refund(entry.creator, entry.token, entry.amount);

        emit MonetaryCashCancelled(msg.sender, cashId);
    }

    function setBackendSigner(address newSigner) external onlyAdminOrFeatureOwner {
        if (newSigner == address(0)) revert InvalidAddress();
        address previous = backendSigner;
        backendSigner = newSigner;
        emit BackendSignerUpdated(previous, newSigner);
    }

    function getCash(uint256 cashId) external view returns (Cash memory) {
        Cash memory entry = cashes[cashId];
        if (entry.status == CashStatus.None) revert NotFound();
        return entry;
    }

    function getCashStatus(uint256 cashId) external view returns (CashStatus) {
        return cashes[cashId].status;
    }

    function hashActivation(uint256 cashId, address recipient, uint256 deadline) external view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(ACTIVATE_TYPEHASH, cashId, recipient, deadline)));
    }

    function _refund(address to, address token, uint256 amount) internal {
        if (amount == 0) return;
        if (token == address(0)) {
            (bool success, ) = payable(to).call{value: amount}('');
            if (!success) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }
}
