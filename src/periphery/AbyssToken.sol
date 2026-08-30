// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { ERC20 } from "solady/tokens/ERC20.sol";

/// @notice Abyss protocol token: fixed identity, fixed initial supply, permissionless burn.
/// @dev Built on the pinned Solady ERC20 library base (MIT). No owner, mint, or pause.
///      Inherits Solady's EIP-2612 `permit` and its default Permit2 infinite allowance
///      (`allowance(x, PERMIT2) == type(uint256).max` unless overridden). `burn` is the
///      only sink and permanently reduces `totalSupply`.
contract AbyssToken is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 100_000_000_000 * 1e18;

    constructor() {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function name() public pure override returns (string memory) {
        return "Abyss";
    }

    function symbol() public pure override returns (string memory) {
        return "ABYSS";
    }

    /// @notice Permanently removes `amount` tokens from the caller's balance and the supply.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
