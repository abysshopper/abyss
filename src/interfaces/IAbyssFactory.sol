// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { OracleConfig, PoolKey, PoolProfile } from "../types/AbyssTypes.sol";

interface IAbyssFactory {
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        uint24 indexed fee,
        int24 tickSpacing,
        address pool
    );
    event AbyssPoolCreated(
        address indexed token0,
        address indexed token1,
        uint24 indexed fee,
        PoolProfile profile,
        bool quoteIsToken0,
        bytes32 oracleConfigId,
        address pool
    );
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event FeeAmountEnabled(uint24 indexed fee, int24 indexed tickSpacing);
    event OracleConfigRegistered(
        bytes32 indexed oracleConfigId, uint24 maxAbsTickMove, uint16 cardinality
    );
    event DefaultProtocolFeeDenominatorChanged(uint8 oldDenominator, uint8 newDenominator);
    event ProfileEnabled(PoolProfile indexed profile, bytes32 indexed initCodeHash);

    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function feeVault() external view returns (address);
    function defaultProtocolFeeDenominator() external view returns (uint8);
    function feeAmountTickSpacing(uint24 fee) external view returns (int24);
    function oracleConfigs(bytes32 id)
        external
        view
        returns (uint24 maxAbsTickMove, uint16 cardinality);
    function getPool(bytes32 poolId) external view returns (address);
    function isPool(address pool) external view returns (bool);

    function createPool(
        address tokenA,
        address tokenB,
        PoolProfile profile,
        uint24 fee,
        address quoteToken,
        bytes32 oracleConfigId
    ) external returns (address pool);

    function createAndInitializePool(
        address tokenA,
        address tokenB,
        PoolProfile profile,
        uint24 fee,
        address quoteToken,
        bytes32 oracleConfigId,
        uint160 sqrtPriceX96
    ) external returns (address pool);

    function computePoolId(PoolKey calldata key) external view returns (bytes32);
    function computePoolAddress(PoolKey calldata key) external view returns (address predicted);
    function registerProfileCode(PoolProfile profile, address chunk0, address chunk1)
        external
        returns (bytes32 initCodeHash);
    function enableFeeAmount(uint24 fee, int24 tickSpacing) external;
    function registerOracleConfig(OracleConfig calldata config) external returns (bytes32 id);
    function setDefaultProtocolFeeDenominator(uint8 denominator) external;
    function setPoolProtocolFeeDenominator(address pool, uint8 denominator) external;
    function transferOwnership(address newOwner) external;
    function acceptOwnership() external;
}
