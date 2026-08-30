// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { PoolKey, PoolProfile } from "../types/AbyssTypes.sol";

interface IAbyssPoolDeployer {
    function parameters()
        external
        view
        returns (address factory, address token0, address token1, uint24 fee, int24 tickSpacing);

    function abyssParameters()
        external
        view
        returns (
            PoolProfile profile,
            bool quoteIsToken0,
            bytes32 oracleConfigId,
            address feeVault,
            uint8 protocolFeeDenominator
        );
    function expectedInitCodeHash(PoolProfile profile) external pure returns (bytes32);

    function deploy(PoolKey calldata key, int24 tickSpacing, uint8 protocolFeeDenominator)
        external
        returns (address pool);

    function registerProfileCode(PoolProfile profile, address chunk0, address chunk1)
        external
        returns (bytes32 initCodeHash);
}
