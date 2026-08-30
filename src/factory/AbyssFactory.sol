// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { AbyssPoolDeployer } from "./AbyssPoolDeployer.sol";
import { OwnedTwoStep } from "../governance/OwnedTwoStep.sol";
import { PoolKeyLib } from "../libraries/PoolKeyLib.sol";
import { FeeVault } from "../periphery/FeeVault.sol";
import { IAbyssPool } from "../interfaces/IAbyssPool.sol";
import { OracleConfig, PoolKey, PoolProfile } from "../types/AbyssTypes.sol";

contract AbyssFactory is OwnedTwoStep {
    error FeeAlreadyEnabled();
    error InvalidFeeAmount();
    error InvalidTickSpacing();
    error InvalidOracleConfig();
    error OracleConfigAlreadyRegistered();
    error PoolAlreadyExists();
    error ProfileCodeNotRegistered();
    error UnknownPool();
    error InvalidProtocolFeeDenominator();

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

    address public immutable feeVault;
    AbyssPoolDeployer public immutable poolDeployer;
    uint8 public defaultProtocolFeeDenominator = 6;

    mapping(uint24 fee => int24 tickSpacing) public feeAmountTickSpacing;
    mapping(bytes32 id => OracleConfig config) public oracleConfigs;
    mapping(bytes32 poolId => address pool) public getPool;
    mapping(address pool => bool registered) public isPool;

    constructor(address initialOwner) OwnedTwoStep(initialOwner) {
        emit OwnerChanged(address(0), initialOwner);
        feeVault = address(new FeeVault(initialOwner));
        poolDeployer = new AbyssPoolDeployer();
        _enableFeeAmount(500, 10);
        _enableFeeAmount(3000, 60);
        _enableFeeAmount(10_000, 200);
    }

    function acceptOwnership() public override {
        address oldOwner = owner;
        super.acceptOwnership();
        emit OwnerChanged(oldOwner, msg.sender);
    }

    function createPool(
        address tokenA,
        address tokenB,
        PoolProfile profile,
        uint24 fee,
        address quoteToken,
        bytes32 oracleConfigId
    ) external returns (address pool) {
        pool = _createPool(tokenA, tokenB, profile, fee, quoteToken, oracleConfigId);
    }

    function createAndInitializePool(
        address tokenA,
        address tokenB,
        PoolProfile profile,
        uint24 fee,
        address quoteToken,
        bytes32 oracleConfigId,
        uint160 sqrtPriceX96
    ) external returns (address pool) {
        pool = _createPool(tokenA, tokenB, profile, fee, quoteToken, oracleConfigId);
        IAbyssPool(pool).initialize(sqrtPriceX96);
    }

    function _createPool(
        address tokenA,
        address tokenB,
        PoolProfile profile,
        uint24 fee,
        address quoteToken,
        bytes32 oracleConfigId
    ) private returns (address pool) {
        PoolKey memory key = PoolKeyLib.canonicalize(
            tokenA, tokenB, profile, fee, quoteToken, oracleConfigId
        );
        (int24 tickSpacing,) = _validatePoolKey(key);
        bytes32 poolId = PoolKeyLib.id(key);
        if (getPool[poolId] != address(0)) revert PoolAlreadyExists();

        pool = poolDeployer.deploy(key, tickSpacing, defaultProtocolFeeDenominator);
        getPool[poolId] = pool;
        isPool[pool] = true;
        emit PoolCreated(key.token0, key.token1, key.fee, tickSpacing, pool);
        emit AbyssPoolCreated(
            key.token0,
            key.token1,
            key.fee,
            key.profile,
            key.quoteIsToken0,
            key.oracleConfigId,
            pool
        );
    }

    function computePoolId(PoolKey calldata key) external view returns (bytes32) {
        _validatePoolKey(key);
        return PoolKeyLib.id(key);
    }

    function computePoolAddress(PoolKey calldata key) external view returns (address predicted) {
        (, bytes32 creationCodeHash) = _validatePoolKey(key);
        bytes32 salt = PoolKeyLib.id(key);
        predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(poolDeployer), salt, creationCodeHash
                        )
                    )
                )
            )
        );
    }

    function registerProfileCode(PoolProfile profile, address chunk0, address chunk1)
        external
        onlyOwner
        returns (bytes32 initCodeHash)
    {
        initCodeHash = poolDeployer.registerProfileCode(profile, chunk0, chunk1);
        emit ProfileEnabled(profile, initCodeHash);
    }

    function enableFeeAmount(uint24 fee, int24 tickSpacing) external onlyOwner {
        _enableFeeAmount(fee, tickSpacing);
    }

    function registerOracleConfig(OracleConfig calldata config)
        external
        onlyOwner
        returns (bytes32 id)
    {
        if (
            config.maxAbsTickMove == 0 || config.maxAbsTickMove > 887_272 || config.cardinality < 2
                || config.cardinality > 4096
        ) revert InvalidOracleConfig();
        id = keccak256(abi.encode(config));
        if (oracleConfigs[id].cardinality != 0) revert OracleConfigAlreadyRegistered();
        oracleConfigs[id] = config;
        emit OracleConfigRegistered(id, config.maxAbsTickMove, config.cardinality);
    }

    function setDefaultProtocolFeeDenominator(uint8 denominator) external onlyOwner {
        _checkProtocolFeeDenominator(denominator);
        uint8 oldDenominator = defaultProtocolFeeDenominator;
        defaultProtocolFeeDenominator = denominator;
        emit DefaultProtocolFeeDenominatorChanged(oldDenominator, denominator);
    }

    function setPoolProtocolFeeDenominator(address pool, uint8 denominator) external onlyOwner {
        _checkProtocolFeeDenominator(denominator);
        if (!isPool[pool]) revert UnknownPool();
        IAbyssPool(pool).setProtocolFeeDenominator(denominator);
    }

    function _validatePoolKey(PoolKey memory key)
        private
        view
        returns (int24 tickSpacing, bytes32 initCodeHash)
    {
        PoolKeyLib.validate(key);
        tickSpacing = feeAmountTickSpacing[key.fee];
        if (tickSpacing == 0) revert InvalidFeeAmount();
        if (key.oracleConfigId != bytes32(0) && oracleConfigs[key.oracleConfigId].cardinality == 0) revert InvalidOracleConfig();
        (,,,, initCodeHash) = poolDeployer.profileCode(key.profile);
        if (initCodeHash == bytes32(0)) revert ProfileCodeNotRegistered();
    }

    function _enableFeeAmount(uint24 fee, int24 tickSpacing) private {
        if (fee == 0 || fee >= 1_000_000) revert InvalidFeeAmount();
        if (tickSpacing <= 0 || tickSpacing >= 16_384) revert InvalidTickSpacing();
        if (feeAmountTickSpacing[fee] != 0) revert FeeAlreadyEnabled();
        feeAmountTickSpacing[fee] = tickSpacing;
        emit FeeAmountEnabled(fee, tickSpacing);
    }

    function _checkProtocolFeeDenominator(uint8 denominator) private pure {
        if (denominator != 0 && (denominator < 4 || denominator > 10)) {
            revert InvalidProtocolFeeDenominator();
        }
    }
}
