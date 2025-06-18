// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccessControlCenter.sol";
import "./TokenRegistry.sol";
import "./CoreFeeManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract PaymentGateway is Initializable, ReentrancyGuardUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    using Address for address payable;
    using SafeERC20 for IERC20;

    AccessControlCenter public access;
    TokenRegistry public tokenRegistry;
    CoreFeeManager public feeManager;

    mapping(address => uint256) public nonces;
    bytes32 public DOMAIN_SEPARATOR;
    bytes32 private constant PROCESS_TYPEHASH = keccak256("ProcessPayment(address payer,bytes32 moduleId,address token,uint256 amount,uint256 nonce,uint256 chainId)");


    event PaymentProcessed(
        address indexed payer,
        address indexed token,
        uint256 grossAmount,
        uint256 fee,
        uint256 netAmount,
        bytes32 moduleId
    );

    modifier onlyFeatureOwner() {
        require(access.hasRole(access.FEATURE_OWNER_ROLE(), msg.sender), "not feature owner");
        _;
    }

    modifier onlyAdmin() {
        require(access.hasRole(access.DEFAULT_ADMIN_ROLE(), msg.sender), "not admin");
        _;
    }

    function initialize(
        address accessControl,
        address validator_,
        address feeManager_
    ) public initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        access = AccessControlCenter(accessControl);
        tokenRegistry = TokenRegistry(validator_);
        feeManager = CoreFeeManager(feeManager_);
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(uint256 chainId,address verifyingContract)"),
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
        require(tokenRegistry.isTokenAllowed(moduleId, token), "token not allowed");
        if (!access.hasRole(access.AUTOMATION_ROLE(), msg.sender)) {
            if (payer != msg.sender) {
                bytes32 digest = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR,
                        keccak256(
                            abi.encode(
                                PROCESS_TYPEHASH,
                                payer,
                                moduleId,
                                token,
                                amount,
                                nonces[payer]++,
                                block.chainid
                            )
                        )
                    )
                );
                require(ECDSA.recover(digest, signature) == payer, "invalid signature");
            }
        }

        IERC20(token).safeTransferFrom(payer, address(this), amount);
        IERC20(token).forceApprove(address(feeManager), amount);
        uint256 fee = feeManager.collect(moduleId, token, address(this), amount);
        IERC20(token).forceApprove(address(feeManager), 0);
        netAmount = amount - fee;
        IERC20(token).safeTransfer(msg.sender, netAmount);


        emit PaymentProcessed(payer, token, amount, fee, netAmount, moduleId);
    }

    function setValidator(address newValidator) external onlyAdmin {
        tokenRegistry = TokenRegistry(newValidator);
    }

    function setFeeManager(address newManager) external onlyAdmin {
        feeManager = CoreFeeManager(newManager);
    }

    function setAccessControl(address newAccess) external onlyAdmin {
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
        require(newImplementation != address(0), "invalid implementation");
    }

    uint256[50] private __gap;
}
