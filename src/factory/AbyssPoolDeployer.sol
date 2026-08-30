// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { IAbyssPoolDeployer } from "../interfaces/IAbyssPoolDeployer.sol";
import { PoolKey, PoolProfile } from "../types/AbyssTypes.sol";

/// @notice Holds pool constructor parameters transiently and deploys registered creation bytecode.
contract AbyssPoolDeployer is IAbyssPoolDeployer {
    error OnlyFactory();
    error ProfileCodeAlreadyRegistered();
    error InvalidProfileCode();
    error ProfileCodeHashMismatch(bytes32 expected, bytes32 actual);
    error DeploymentFailed();

    struct ProfileCode {
        address chunk0;
        address chunk1;
        uint24 length0;
        uint24 length1;
        bytes32 initCodeHash;
    }

    event ProfileCodeRegistered(PoolProfile indexed profile, bytes32 indexed initCodeHash);
    /// @dev EXACT-HASH UPDATE POINT: regenerate bytecode-report.json with the pinned compiler,
    /// review the profile artifacts, then update all four commitments together.
    bytes32 public constant STANDARD_INIT_CODE_HASH =
        0x00cd31b0b2f648e25ae487a60e33963112dc4728d7809c36ff32dcf5ebd5f5f2;
    bytes32 public constant STANDARD_ORACLE_INIT_CODE_HASH =
        0x8b0ceb9fe7ad9ce169c9c313985087d1d515fab8eafd4e30274b87ad029050c1;
    bytes32 public constant QUOTE_INIT_CODE_HASH =
        0x2fb7e4553b9aad5faa789a70bd7f1aa87d874b065f2b73a8a49799508645c069;
    bytes32 public constant QUOTE_ORACLE_INIT_CODE_HASH =
        0xb63607c147df8f1798c5c39439bbcbb4c230e9262641dbd679ce4eb61b38924f;

    address public immutable factory;
    mapping(PoolProfile profile => ProfileCode code) public profileCode;

    address private _token0;
    address private _token1;
    uint24 private _fee;
    int24 private _tickSpacing;
    PoolProfile private _profile;
    bool private _quoteIsToken0;
    bytes32 private _oracleConfigId;
    address private _feeVault;
    uint8 private _protocolFeeDenominator;

    constructor() {
        factory = msg.sender;
    }

    function expectedInitCodeHash(PoolProfile profile) public pure returns (bytes32) {
        if (profile == PoolProfile.STANDARD) return STANDARD_INIT_CODE_HASH;
        if (profile == PoolProfile.STANDARD_ORACLE) return STANDARD_ORACLE_INIT_CODE_HASH;
        if (profile == PoolProfile.QUOTE) return QUOTE_INIT_CODE_HASH;
        return QUOTE_ORACLE_INIT_CODE_HASH;
    }

    function registerProfileCode(PoolProfile profile, address chunk0, address chunk1)
        external
        returns (bytes32 initCodeHash)
    {
        if (msg.sender != factory) revert OnlyFactory();
        if (profileCode[profile].initCodeHash != bytes32(0)) {
            revert ProfileCodeAlreadyRegistered();
        }
        uint256 length0 = chunk0.code.length;
        uint256 length1 = chunk1.code.length;
        if (
            length0 == 0 || length0 > 24_000 || length1 > 24_000
                || (length1 == 0 && chunk1 != address(0))
        ) {
            revert InvalidProfileCode();
        }
        bytes memory creationCode = _loadCode(chunk0, chunk1, length0, length1);
        initCodeHash = keccak256(creationCode);
        bytes32 expectedHash = expectedInitCodeHash(profile);
        if (initCodeHash != expectedHash) {
            revert ProfileCodeHashMismatch(expectedHash, initCodeHash);
        }
        profileCode[profile] = ProfileCode({
            chunk0: chunk0,
            chunk1: chunk1,
            length0: uint24(length0),
            length1: uint24(length1),
            initCodeHash: initCodeHash
        });
        emit ProfileCodeRegistered(profile, initCodeHash);
    }

    function parameters()
        external
        view
        returns (
            address factoryAddress,
            address token0,
            address token1,
            uint24 fee,
            int24 tickSpacing
        )
    {
        return (factory, _token0, _token1, _fee, _tickSpacing);
    }

    function abyssParameters()
        external
        view
        returns (
            PoolProfile profile,
            bool quoteIsToken0,
            bytes32 oracleConfigId,
            address feeVault,
            uint8 protocolFeeDenominator
        )
    {
        return (_profile, _quoteIsToken0, _oracleConfigId, _feeVault, _protocolFeeDenominator);
    }

    function deploy(PoolKey calldata key, int24 tickSpacing, uint8 protocolFeeDenominator)
        external
        returns (address pool)
    {
        if (msg.sender != factory) revert OnlyFactory();
        ProfileCode memory code = profileCode[key.profile];
        if (code.initCodeHash == bytes32(0)) revert InvalidProfileCode();
        _token0 = key.token0;
        _token1 = key.token1;
        _fee = key.fee;
        _tickSpacing = tickSpacing;
        _profile = key.profile;
        _quoteIsToken0 = key.quoteIsToken0;
        _oracleConfigId = key.oracleConfigId;
        _feeVault = IAbyssDeployerFactory(factory).feeVault();
        _protocolFeeDenominator = protocolFeeDenominator;

        bytes memory creationCode = _loadCode(code.chunk0, code.chunk1, code.length0, code.length1);
        bytes32 actualHash = keccak256(creationCode);
        if (actualHash != code.initCodeHash) {
            revert ProfileCodeHashMismatch(code.initCodeHash, actualHash);
        }
        bytes32 salt = keccak256(abi.encode(key));
        assembly ("memory-safe") {
            pool := create2(0, add(creationCode, 0x20), mload(creationCode), salt)
        }
        if (pool == address(0) || pool.code.length == 0) revert DeploymentFailed();

        delete _token0;
        delete _token1;
        delete _fee;
        delete _tickSpacing;
        delete _profile;
        delete _quoteIsToken0;
        delete _oracleConfigId;
        delete _feeVault;
        delete _protocolFeeDenominator;
    }

    function _loadCode(address chunk0, address chunk1, uint256 length0, uint256 length1)
        private
        view
        returns (bytes memory creationCode)
    {
        creationCode = new bytes(length0 + length1);
        assembly ("memory-safe") {
            extcodecopy(chunk0, add(creationCode, 0x20), 0, length0)
            extcodecopy(chunk1, add(add(creationCode, 0x20), length0), 0, length1)
        }
    }
}

interface IAbyssDeployerFactory {
    function feeVault() external view returns (address);
}
