// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../interfaces/core/IRegistry.sol';

/**
 * @title MarketplaceProxy
 * @notice Minimal proxy contract used for Marketplace modules.
 *         Stores registry and gateway addresses and delegates all calls
 *         to an implementation contract.
 */
contract MarketplaceProxy {
    /// @notice Registry reference
    IRegistry public registry;
    /// @notice Payment gateway used by the marketplace implementation
    address public gateway;
    /// @dev Implementation address that receives delegated calls
    address public immutable implementation;

    constructor(address _registry, address _gateway, address _implementation) {
        registry = IRegistry(_registry);
        gateway = _gateway;
        implementation = _implementation;
    }

    receive() external payable {}

    fallback() external payable {
        address impl = implementation;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
