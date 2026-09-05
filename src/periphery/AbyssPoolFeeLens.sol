// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

interface IAbyssFeeLensFactory {
    function isPool(address pool) external view returns (bool);
}

interface IAbyssFeeLensPool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function protocolFees() external view returns (uint128 amount0, uint128 amount1);
    function claimProtocolFees() external returns (uint128 amount0, uint128 amount1);
}

/// @notice Bounded, failure-isolating protocol-fee inspection and claim adapter.
/// @dev Pricing and profitability remain off-chain. Pools transfer claims directly to their
///      immutable FeeVault; this contract never receives or approves treasury tokens.
contract AbyssPoolFeeLens {
    error InvalidConfiguration();
    error InvalidBatch();
    error SelfOnly();

    uint256 public constant MAX_POOLS = 64;

    struct PoolFees {
        bool canonical;
        bool success;
        address token0;
        address token1;
        uint128 amount0;
        uint128 amount1;
        bytes4 errorSelector;
    }

    struct ClaimResult {
        bool canonical;
        bool success;
        uint128 amount0;
        uint128 amount1;
        bytes4 errorSelector;
    }

    event ProtocolFeesClaimed(
        address indexed pool,
        bool indexed canonical,
        bool success,
        uint128 amount0,
        uint128 amount1,
        bytes4 errorSelector
    );

    IAbyssFeeLensFactory public immutable factory;

    constructor(IAbyssFeeLensFactory factory_) {
        if (address(factory_) == address(0) || address(factory_).code.length == 0) {
            revert InvalidConfiguration();
        }
        factory = factory_;
    }

    function inspect(address[] calldata pools) external view returns (PoolFees[] memory results) {
        uint256 length = _checkBatch(pools.length);
        results = new PoolFees[](length);
        for (uint256 i; i < length; ++i) {
            address pool = pools[i];
            bool canonical = factory.isPool(pool);
            results[i].canonical = canonical;
            if (!canonical) continue;
            try this.inspectOne(pool) returns (
                address token0, address token1, uint128 amount0, uint128 amount1
            ) {
                results[i].success = true;
                results[i].token0 = token0;
                results[i].token1 = token1;
                results[i].amount0 = amount0;
                results[i].amount1 = amount1;
            } catch (bytes memory reason) {
                results[i].errorSelector = _selector(reason);
            }
        }
    }

    function inspectOne(address pool)
        external
        view
        returns (address token0, address token1, uint128 amount0, uint128 amount1)
    {
        if (msg.sender != address(this)) revert SelfOnly();
        IAbyssFeeLensPool target = IAbyssFeeLensPool(pool);
        token0 = target.token0();
        token1 = target.token1();
        (amount0, amount1) = target.protocolFees();
    }

    function claim(address[] calldata pools) external returns (ClaimResult[] memory results) {
        uint256 length = _checkBatch(pools.length);
        results = new ClaimResult[](length);
        for (uint256 i; i < length; ++i) {
            address pool = pools[i];
            bool canonical = factory.isPool(pool);
            results[i].canonical = canonical;
            if (canonical) {
                try IAbyssFeeLensPool(pool).claimProtocolFees() returns (
                    uint128 amount0, uint128 amount1
                ) {
                    results[i].success = true;
                    results[i].amount0 = amount0;
                    results[i].amount1 = amount1;
                } catch (bytes memory reason) {
                    results[i].errorSelector = _selector(reason);
                }
            }
            emit ProtocolFeesClaimed(
                pool,
                canonical,
                results[i].success,
                results[i].amount0,
                results[i].amount1,
                results[i].errorSelector
            );
        }
    }

    function _checkBatch(uint256 length) private pure returns (uint256) {
        if (length == 0 || length > MAX_POOLS) revert InvalidBatch();
        return length;
    }

    function _selector(bytes memory reason) private pure returns (bytes4 selector) {
        if (reason.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(reason, 0x20))
        }
    }
}
