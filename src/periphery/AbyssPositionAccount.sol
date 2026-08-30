// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { IAbyssPool } from "../interfaces/IAbyssPool.sol";
import { IAbyssMintCallback } from "../interfaces/IAbyssCallbacks.sol";
import {
    IAbyssPositionAccount,
    IAbyssPositionManagerSettlement
} from "../interfaces/IAbyssPositionManager.sol";

/// @notice Immutable custody account for exactly one position-manager NFT.
/// @dev The account, rather than the manager, is the owner in the pool position key.
contract AbyssPositionAccount is IAbyssPositionAccount, IAbyssMintCallback {
    error Unauthorized();
    error InvalidCallback();

    address public immutable override manager;
    IAbyssPool public immutable override pool;

    address private activePayer;
    bool private mintActive;

    modifier onlyManager() {
        if (msg.sender != manager) revert Unauthorized();
        _;
    }

    constructor(address manager_, IAbyssPool pool_) {
        manager = manager_;
        pool = pool_;
    }

    function mintPosition(address payer, int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        override
        onlyManager
        returns (uint256 amount0, uint256 amount1)
    {
        if (payer == address(0) || mintActive) revert InvalidCallback();
        activePayer = payer;
        mintActive = true;
        (amount0, amount1) = pool.mint(address(this), tickLower, tickUpper, liquidity, "");
        if (mintActive || activePayer != address(0)) revert InvalidCallback();
    }

    function burnPosition(int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        override
        onlyManager
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = pool.burn(tickLower, tickUpper, liquidity);
    }

    function pokePosition(int24 tickLower, int24 tickUpper) external override onlyManager {
        pool.burn(tickLower, tickUpper, 0);
    }

    function collectPosition(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override onlyManager returns (uint128 amount0, uint128 amount1) {
        (amount0, amount1) =
            pool.collect(recipient, tickLower, tickUpper, amount0Requested, amount1Requested);
    }

    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata)
        external
        override
    {
        address payer = activePayer;
        if (msg.sender != address(pool) || !mintActive || payer == address(0)) {
            revert InvalidCallback();
        }
        mintActive = false;
        delete activePayer;
        IAbyssPositionManagerSettlement(manager)
            .settleMint(address(this), pool, payer, amount0Owed, amount1Owed);
    }
}
