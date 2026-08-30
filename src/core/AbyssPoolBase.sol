// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;
// Derived in part from Uniswap V3 Core UniswapV3Pool.sol; modified by the Abyss project
// on 2026-08-17 and 2026-08-18: split pool/profile configuration, factory authorization,
// protocol-fee controls, and quote-token orientation into an Abyss base contract.

import { UniswapV3Pool } from "./v3/UniswapV3Pool.sol";
import { TransferHelper } from "./v3/libraries/TransferHelper.sol";
import { IAbyssPoolDeployer } from "../interfaces/IAbyssPoolDeployer.sol";
import { PoolProfile } from "../types/AbyssTypes.sol";

abstract contract AbyssPoolBase is UniswapV3Pool {
    error OnlyFactory();
    error InvalidConfiguration();

    event ProtocolFeeDenominatorChanged(uint8 oldDenominator, uint8 newDenominator);

    PoolProfile internal immutable _profile;
    bool public immutable quoteIsToken0;
    bytes32 internal immutable _oracleConfigId;
    address internal immutable feeVault;

    constructor(PoolProfile expectedProfile) {
        uint8 denominator;
        (_profile, quoteIsToken0, _oracleConfigId, feeVault, denominator) =
            IAbyssPoolDeployer(msg.sender).abyssParameters();
        if (_profile != expectedProfile || feeVault == address(0)) revert InvalidConfiguration();
        _checkProtocolFeeDenominator(denominator);
        slot0.feeProtocol = denominator | (denominator << 4);
    }

    function setProtocolFeeDenominator(uint8 denominator) external lock {
        if (msg.sender != factory) revert OnlyFactory();
        _checkProtocolFeeDenominator(denominator);
        uint8 oldDenominator = slot0.feeProtocol & 0x0f;
        slot0.feeProtocol = denominator | (denominator << 4);
        emit ProtocolFeeDenominatorChanged(oldDenominator, denominator);
        emit SetFeeProtocol(oldDenominator, oldDenominator, denominator, denominator);
    }

    function claimProtocolFees() external lock returns (uint128 amount0, uint128 amount1) {
        amount0 = protocolFees.token0;
        amount1 = protocolFees.token1;
        if (amount0 != 0) {
            protocolFees.token0 = 0;
            TransferHelper.safeTransfer(token0, feeVault, amount0);
        }
        if (amount1 != 0) {
            protocolFees.token1 = 0;
            TransferHelper.safeTransfer(token1, feeVault, amount1);
        }
        emit CollectProtocol(msg.sender, feeVault, amount0, amount1);
    }

    function _beforeSwap(uint32, int24, uint128) internal virtual override { }

    function _afterInitialize(uint32, int24) internal virtual override { }

    function _afterIncreaseObservationCardinalityNext(uint16) internal virtual override { }

    function _beforeLiquidityChange(uint32, int24, uint128, int24, int24, int128)
        internal
        virtual
        override
    { }

    function _checkProtocolFeeDenominator(uint8 denominator) private pure {
        if (denominator != 0 && (denominator < 4 || denominator > 10)) {
            revert InvalidConfiguration();
        }
    }
}
