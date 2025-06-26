// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './AccessControlCenter.sol';
import '../interfaces/core/IRegistry.sol';
import '../interfaces/IValidator.sol';
import './CoreFeeManager.sol';
import '../errors/Errors.sol';
import '../lib/SignatureLib.sol';
import '../interfaces/CoreDefs.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

contract PaymentGateway is Initializable, ReentrancyGuardUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    using Address for address payable;
    using SafeERC20 for IERC20;

    AccessControlCenter public access;
    IRegistry public registry;
    CoreFeeManager public feeManager;

    mapping(address => uint256) public nonces;
    bytes32 public DOMAIN_SEPARATOR;

    event PaymentProcessed(
        address indexed payer,
        address indexed token,
        uint256 grossAmount,
        uint256 fee,
        uint256 netAmount,
        bytes32 moduleId
    );

    modifier onlyFeatureOwner() {
        if (!access.hasRole(access.FEATURE_OWNER_ROLE(), msg.sender)) revert NotFeatureOwner();
        _;
    }

    modifier onlyAdmin() {
        if (!access.hasRole(access.DEFAULT_ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        _;
    }

    function initialize(address accessControl, address registry_, address feeManager_) public initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        access = AccessControlCenter(accessControl);
        registry = IRegistry(registry_);
        feeManager = CoreFeeManager(feeManager_);
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(uint256 chainId,address verifyingContract)'),
                block.chainid,
                address(this)
            )
        );
    }

    function processPayment(
        bytes32 moduleId,
        address token,
        address payer,
        uint256 amount,
        bytes calldata signature
    ) external onlyFeatureOwner nonReentrant whenNotPaused returns (uint256 netAmount) {
        address val = registry.getModuleService(moduleId, CoreDefs.SERVICE_VALIDATOR);
        if (!IValidator(val).isAllowed(token)) revert NotAllowedToken();
        // Skip signature verification for automation bots and trusted relayers
        if (
            payer != msg.sender &&
            !access.hasRole(access.AUTOMATION_ROLE(), msg.sender) &&
            !access.hasRole(access.RELAYER_ROLE(), msg.sender)
        ) {
            bytes32 digest = SignatureLib.hashProcessPayment(
                DOMAIN_SEPARATOR,
                payer,
                moduleId,
                token,
                amount,
                nonces[payer]++,
                block.chainid
            );
            if (ECDSA.recover(digest, signature) != payer) revert InvalidSignature();
        }

        IERC20(token).safeTransferFrom(payer, address(this), amount);
        IERC20(token).forceApprove(address(feeManager), amount);
        uint256 fee = feeManager.collect(moduleId, token, address(this), amount);
        IERC20(token).forceApprove(address(feeManager), 0);
        netAmount = amount - fee;
        IERC20(token).safeTransfer(msg.sender, netAmount);

        emit PaymentProcessed(payer, token, amount, fee, netAmount, moduleId);
    }

    function setRegistry(address newRegistry) external onlyAdmin {
        if (newRegistry == address(0)) revert InvalidAddress();
        registry = IRegistry(newRegistry);
    }

    function setFeeManager(address newManager) external onlyAdmin {
        if (newManager == address(0)) revert InvalidAddress();
        feeManager = CoreFeeManager(newManager);
    }

    function setAccessControl(address newAccess) external onlyAdmin {
        if (newAccess == address(0)) revert InvalidAddress();
        access = AccessControlCenter(newAccess);
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    /// @dev UUPS upgrade authorization
    function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
        if (newImplementation == address(0)) revert InvalidImplementation();
    }

    uint256[50] private __gap;
}
