// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

/// @notice Minimal interface for the treasury operations Abyss needs from the FeeVault.
interface IAbyssFeeVault {
    /// @notice Owner-only treasury transfer of an arbitrary ERC-20 balance.
    function transferToken(address token, address recipient, uint256 amount) external;
}
