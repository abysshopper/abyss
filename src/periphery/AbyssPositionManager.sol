// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;
// Derived in part from Uniswap V3 Periphery NonfungiblePositionManager.sol; modified by
// the Abyss project on 2026-08-17, 2026-08-18, 2026-08-19, and 2026-08-22 for
// authenticated pools, immutable per-NFT custody accounts, payer settlement, withdrawal
// limits, native-value rejection, guarded multicall launch settlement, and the pinned
// Solady ERC721 base.

import { ERC721 } from "solady/tokens/ERC721.sol";
import { IAbyssFactory } from "../interfaces/IAbyssFactory.sol";
import { IAbyssPool } from "../interfaces/IAbyssPool.sol";
import {
    IAbyssPositionAccount,
    IAbyssPositionManager,
    IAbyssPositionManagerSettlement
} from "../interfaces/IAbyssPositionManager.sol";
import { PoolKey, PoolProfile } from "../types/AbyssTypes.sol";
import { PoolKeyLib } from "../libraries/PoolKeyLib.sol";
import { AbyssPositionAccount } from "./AbyssPositionAccount.sol";

contract AbyssPositionManager is ERC721, IAbyssPositionManager, IAbyssPositionManagerSettlement {
    error InvalidPool();
    error InvalidAmount();
    error SlippageExceeded();
    error DeadlineExpired();
    error Unauthorized();
    error Reentrancy();
    error PositionNotEmpty();
    error TokenTransferFailed();
    error InvalidMintContext();
    error NativeValueNotAccepted();
    error InvalidMulticall();
    error UnexpectedPoolAddress();
    error ExistingPoolPriceOutsideBounds();

    struct ManagedPosition {
        address account;
        address pool;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
    }

    struct MintContext {
        address account;
        address pool;
        address payer;
    }

    IAbyssFactory public immutable override factory;
    uint256 public override nextTokenId = 1;
    mapping(uint256 tokenId => ManagedPosition position) public override positions;

    MintContext private activeMint;
    bool private entered;
    bool private multicallActive;

    modifier nonReentrant() {
        if (entered) revert Reentrancy();
        entered = true;
        _;
        entered = false;
    }

    constructor(IAbyssFactory factory_) {
        factory = factory_;
    }

    function multicall(bytes[] calldata data)
        external
        payable
        override
        returns (bytes[] memory results)
    {
        _rejectNativeValue();
        if (multicallActive || entered) revert InvalidMulticall();
        multicallActive = true;
        results = new bytes[](data.length);
        for (uint256 i; i < data.length; ++i) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(result, 0x20), mload(result))
                }
            }
            results[i] = result;
        }
        multicallActive = false;
    }

    function createAndInitializePoolIfNecessary(
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        uint160 existingPriceMinimumX96,
        uint160 existingPriceMaximumX96
    ) external override returns (address pool, bool created) {
        _rejectNativeValue();
        PoolKeyLib.validate(key);
        bytes32 poolId = PoolKeyLib.id(key);
        pool = factory.getPool(poolId);
        address expected = factory.computePoolAddress(key);
        if (pool == address(0)) {
            address quoteToken = key.profile == PoolProfile.STANDARD
                ? address(0)
                : (key.quoteIsToken0 ? key.token0 : key.token1);
            pool = factory.createAndInitializePool(
                key.token0,
                key.token1,
                key.profile,
                key.fee,
                quoteToken,
                key.oracleConfigId,
                sqrtPriceX96
            );
            if (pool != expected) revert UnexpectedPoolAddress();
            created = true;
        } else {
            if (pool != expected || !factory.isPool(pool)) revert InvalidPool();
            (uint160 currentPrice,,,,,,) = IPoolState(pool).slot0();
            if (
                existingPriceMinimumX96 > existingPriceMaximumX96
                    || currentPrice < existingPriceMinimumX96
                    || currentPrice > existingPriceMaximumX96
            ) revert ExistingPoolPriceOutsideBounds();
        }
    }

    function name() public pure override returns (string memory) {
        return "Abyss Positions";
    }

    function symbol() public pure override returns (string memory) {
        return "ABYSS-POS";
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        ownerOf(id);
        return "";
    }

    function approve(address account, uint256 id) public payable override {
        _rejectNativeValue();
        super.approve(account, id);
    }

    function transferFrom(address from, address to, uint256 id) public payable override {
        _rejectNativeValue();
        super.transferFrom(from, to, id);
    }

    function safeTransferFrom(address from, address to, uint256 id) public payable override {
        _rejectNativeValue();
        super.safeTransferFrom(from, to, id);
    }

    function safeTransferFrom(address from, address to, uint256 id, bytes calldata data)
        public
        payable
        override
    {
        _rejectNativeValue();
        super.safeTransferFrom(from, to, id, data);
    }

    function accountFor(uint256 tokenId, address pool)
        public
        view
        override
        returns (address account)
    {
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(
                type(AbyssPositionAccount).creationCode, abi.encode(address(this), IAbyssPool(pool))
            )
        );
        account = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(this), bytes32(tokenId), bytecodeHash
                        )
                    )
                )
            )
        );
    }

    function mint(
        address pool,
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 amount0Maximum,
        uint256 amount1Maximum,
        uint256 deadline
    ) external override nonReentrant returns (uint256 tokenId, uint256 amount0, uint256 amount1) {
        _rejectNativeValue();
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (!factory.isPool(pool)) revert InvalidPool();
        if (liquidity == 0) revert InvalidAmount();

        tokenId = nextTokenId++;
        address account = address(
            new AbyssPositionAccount{ salt: bytes32(tokenId) }(address(this), IAbyssPool(pool))
        );
        if (account != accountFor(tokenId, pool)) revert InvalidMintContext();
        positions[tokenId] = ManagedPosition({
            account: account,
            pool: pool,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: liquidity
        });

        _activate(account, pool, msg.sender);
        (amount0, amount1) = IAbyssPositionAccount(account)
            .mintPosition(msg.sender, tickLower, tickUpper, liquidity);
        _requireSettled();
        if (amount0 > amount0Maximum || amount1 > amount1Maximum) revert SlippageExceeded();
        _mint(recipient, tokenId);
    }

    function increaseLiquidity(
        uint256 tokenId,
        uint128 amount,
        uint256 amount0Maximum,
        uint256 amount1Maximum
    ) external override nonReentrant returns (uint256 amount0, uint256 amount1) {
        _requireAuthorized(tokenId);
        ManagedPosition storage position = positions[tokenId];
        uint128 poolLiquidity = _syncLiquidity(position);
        if (amount == 0) revert InvalidAmount();
        position.liquidity = poolLiquidity + amount;
        _activate(position.account, position.pool, msg.sender);
        (amount0, amount1) = IAbyssPositionAccount(position.account)
            .mintPosition(msg.sender, position.tickLower, position.tickUpper, amount);
        _requireSettled();
        if (amount0 > amount0Maximum || amount1 > amount1Maximum) revert SlippageExceeded();
    }

    function decreaseLiquidity(
        uint256 tokenId,
        uint128 amount,
        uint256 amount0Minimum,
        uint256 amount1Minimum,
        uint256 deadline
    ) external override nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (block.timestamp > deadline) revert DeadlineExpired();
        _requireAuthorized(tokenId);
        ManagedPosition storage position = positions[tokenId];
        uint128 poolLiquidity = _syncLiquidity(position);
        if (amount == 0 || amount > poolLiquidity) revert InvalidAmount();
        position.liquidity = poolLiquidity - amount;
        (amount0, amount1) = IAbyssPositionAccount(position.account)
            .burnPosition(position.tickLower, position.tickUpper, amount);
        if (amount0 < amount0Minimum || amount1 < amount1Minimum) revert SlippageExceeded();
    }

    function collect(
        uint256 tokenId,
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override nonReentrant returns (uint128 amount0, uint128 amount1) {
        _requireAuthorized(tokenId);
        ManagedPosition storage position = positions[tokenId];
        uint128 poolLiquidity = _syncLiquidity(position);
        IAbyssPositionAccount account = IAbyssPositionAccount(position.account);
        if (poolLiquidity != 0) {
            account.pokePosition(position.tickLower, position.tickUpper);
        }
        (amount0, amount1) = account.collectPosition(
            recipient, position.tickLower, position.tickUpper, amount0Requested, amount1Requested
        );
    }

    function burnPosition(uint256 tokenId) external override nonReentrant {
        _requireAuthorized(tokenId);
        ManagedPosition storage position = positions[tokenId];
        uint128 poolLiquidity = _syncLiquidity(position);
        if (poolLiquidity != 0) {
            IAbyssPositionAccount(position.account)
                .pokePosition(position.tickLower, position.tickUpper);
        }
        bytes32 key =
            keccak256(abi.encodePacked(position.account, position.tickLower, position.tickUpper));
        uint256 tokensOwed0;
        uint256 tokensOwed1;
        (poolLiquidity,,, tokensOwed0, tokensOwed1) = IPoolPositions(position.pool).positions(key);
        if (poolLiquidity != 0 || tokensOwed0 != 0 || tokensOwed1 != 0) {
            revert PositionNotEmpty();
        }
        _burn(tokenId);
    }

    function settleMint(
        address account,
        IAbyssPool pool,
        address payer,
        uint256 amount0Owed,
        uint256 amount1Owed
    ) external override {
        MintContext memory context = activeMint;
        if (
            !entered || msg.sender != context.account || account != context.account
                || address(pool) != context.pool || payer != context.payer || payer == address(0)
        ) revert InvalidMintContext();

        delete activeMint;
        if (amount0Owed != 0) {
            _transferFrom(pool.token0(), payer, address(pool), amount0Owed);
        }
        if (amount1Owed != 0) {
            _transferFrom(pool.token1(), payer, address(pool), amount1Owed);
        }
    }

    function _rejectNativeValue() private view {
        if (msg.value != 0) revert NativeValueNotAccepted();
    }

    function _syncLiquidity(ManagedPosition storage position)
        private
        returns (uint128 poolLiquidity)
    {
        bytes32 key = keccak256(
            abi.encodePacked(position.account, position.tickLower, position.tickUpper)
        );
        (poolLiquidity,,,,) = IPoolPositions(position.pool).positions(key);
        if (position.liquidity != poolLiquidity) position.liquidity = poolLiquidity;
    }

    function _requireAuthorized(uint256 tokenId) private view {
        address owner = ownerOf(tokenId);
        if (
            msg.sender != owner && msg.sender != getApproved(tokenId)
                && !isApprovedForAll(owner, msg.sender)
        ) revert Unauthorized();
    }

    function _activate(address account, address pool, address payer) private {
        if (
            activeMint.account != address(0) || account == address(0) || pool == address(0)
                || payer == address(0)
        ) revert InvalidMintContext();
        activeMint = MintContext({ account: account, pool: pool, payer: payer });
    }

    function _requireSettled() private view {
        if (activeMint.account != address(0)) revert InvalidMintContext();
    }

    function _transferFrom(address token, address sender, address recipient, uint256 amount)
        private
    {
        (bool success, bytes memory result) = token.call(
            abi.encodeWithSelector(
                bytes4(keccak256("transferFrom(address,address,uint256)")),
                sender,
                recipient,
                amount
            )
        );
        if (
            !success || (result.length != 0 && result.length != 32)
                || (result.length == 32 && !abi.decode(result, (bool)))
        ) revert TokenTransferFailed();
    }
}

    interface IPoolState {
        function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
    }

    interface IPoolPositions {
        function positions(bytes32 key)
            external
            view
            returns (uint128, uint256, uint256, uint256, uint256);
    }
