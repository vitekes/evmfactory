// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../interfaces/core/IRegistry.sol';
import '../../core/AccessControlCenter.sol';
import '../../errors/Errors.sol';
import './shared/PrizeInfo.sol';
import './ContestEscrow.sol';
import './interfaces/IContestValidator.sol';
import '../../interfaces/CoreDefs.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/// @title ContestFactory
/// @notice Deploys new contest escrows and handles initial funding.
contract ContestFactory {
    using SafeERC20 for IERC20;

    event ContestCreated(address indexed creator, address contest, uint256 deadline);

    IRegistry public registry;
    address public feeManager;
    AccessControlCenter public access;
    uint256 public defaultContestDuration = 180 days;

    constructor(address _registry, address _feeManager) {
        registry = IRegistry(_registry);
        feeManager = _feeManager;
        access = AccessControlCenter(IRegistry(_registry).getCoreService(keccak256('AccessControlCenter')));
    }

    modifier onlyGovernor() {
        if (!access.hasRole(access.GOVERNOR_ROLE(), msg.sender)) revert NotGovernor();
        _;
    }

    /// @notice Deploy a new contest with specified prizes
    /// @param _prizes List of contest prizes
    /// @return escrow Address of the created escrow contract
    function createContest(
        PrizeInfo[] calldata _prizes,
        bytes calldata /* metadata */
    ) external onlyGovernor returns (address escrow) {
        // validate prizes via plugin if available
        address validator = registry.getModuleServiceByAlias(CoreDefs.CONTEST_MODULE_ID, "Validator");
        if (validator != address(0)) {
            for (uint256 i = 0; i < _prizes.length; i++) {
                IContestValidator(validator).validatePrize(_prizes[i]);
            }
        }

        // basic sanity check for promo slots and zero-amount prizes
        for (uint256 i = 0; i < _prizes.length; i++) {
            PrizeInfo calldata p = _prizes[i];
            if (p.prizeType == PrizeType.PROMO && p.token != address(0)) revert InvalidPrizeData();
            if (p.amount == 0 && p.token != address(0)) revert InvalidPrizeData();
        }

        // deploy escrow
        uint256 deadline = block.timestamp + defaultContestDuration;
        ContestEscrow esc = new ContestEscrow(msg.sender, _prizes, address(registry), 0, feeManager, deadline);
        escrow = address(esc);

        // transfer tokens to escrow, fail-fast on missing amounts
        for (uint256 i = 0; i < _prizes.length; i++) {
            PrizeInfo calldata p = _prizes[i];
            if (p.prizeType == PrizeType.MONETARY && p.amount > 0) {
                uint256 beforeBal = IERC20(p.token).balanceOf(escrow);
                IERC20(p.token).safeTransferFrom(msg.sender, escrow, p.amount);
                uint256 afterBal = IERC20(p.token).balanceOf(escrow);
                if (afterBal - beforeBal != p.amount) revert ContestFundingMissing();
            }
        }

        // verify final balances for each token used
        address[] memory tokens = new address[](_prizes.length);
        uint256[] memory totals = new uint256[](_prizes.length);
        uint256 tcount = 0;
        for (uint256 i = 0; i < _prizes.length; i++) {
            PrizeInfo calldata p = _prizes[i];
            if (p.prizeType == PrizeType.MONETARY && p.amount > 0) {
                bool found = false;
                for (uint256 j = 0; j < tcount; j++) {
                    if (tokens[j] == p.token) {
                        totals[j] += p.amount;
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    tokens[tcount] = p.token;
                    totals[tcount] = p.amount;
                    tcount++;
                }
            }
        }
        for (uint256 i = 0; i < tcount; i++) {
            if (IERC20(tokens[i]).balanceOf(escrow) != totals[i]) revert ContestFundingMissing();
        }

        emit ContestCreated(msg.sender, escrow, deadline);
    }

    /// @notice Set the default contest duration
    /// @param duration Duration in seconds
    function setDefaultContestDuration(uint256 duration) external onlyGovernor {
        defaultContestDuration = duration;
    }

    /// @notice Update registry address
    /// @param newRegistry New registry contract
    function setRegistry(address newRegistry) external onlyGovernor {
        if (newRegistry == address(0)) revert InvalidAddress();
        registry = IRegistry(newRegistry);
        access = AccessControlCenter(IRegistry(newRegistry).getCoreService(keccak256('AccessControlCenter')));
    }

    /// @notice Update fee manager address
    /// @param mgr New fee manager
    function setFeeManager(address mgr) external onlyGovernor {
        if (mgr == address(0)) revert InvalidAddress();
        feeManager = mgr;
    }
}
