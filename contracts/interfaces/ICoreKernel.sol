// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './IAccessControlCenter.sol';
import './IRegistry.sol';

/// @title ICoreKernel
/// @notice Combined interface of access control and registry
interface ICoreKernel is IAccessControlCenter, IRegistry {}
