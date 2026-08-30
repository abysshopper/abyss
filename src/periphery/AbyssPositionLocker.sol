// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { IAbyssPositionManager } from "../interfaces/IAbyssPositionManager.sol";

interface IAbyssPositionNft {
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId) external payable;
}

/// @notice Optional custody for time-locked or permanently locked Abyss position NFTs.
/// @dev Timestamp manipulation is negligible relative to user-selected lock durations.
contract AbyssPositionLocker {
    error InvalidInput();
    error InvalidPositionManager();
    error InvalidTransfer();
    error PositionNotLocked();
    error PositionAlreadyLocked();
    error Unauthorized();
    error PermanentlyLocked();
    error LockActive();
    error LockCannotBeShortened();
    error Reentrancy();

    struct Lock {
        address owner;
        address claimAuthority;
        address feeRecipient;
        uint64 unlockTime;
        bool permissionlessClaim;
    }

    IAbyssPositionManager public immutable positionManager;
    mapping(uint256 tokenId => Lock lock) public locks;

    bool private entered;

    event PositionLocked(
        uint256 indexed tokenId,
        address indexed owner,
        address indexed feeRecipient,
        address claimAuthority,
        uint64 unlockTime,
        bool permissionlessClaim
    );
    event FeesClaimed(
        uint256 indexed tokenId, address indexed recipient, uint128 amount0, uint128 amount1
    );
    event ClaimConfigurationUpdated(
        uint256 indexed tokenId,
        address indexed claimAuthority,
        address indexed feeRecipient,
        bool permissionlessClaim
    );
    event LockExtended(uint256 indexed tokenId, uint64 previousUnlockTime, uint64 newUnlockTime);
    event LockOwnershipTransferred(
        uint256 indexed tokenId, address indexed previousOwner, address indexed newOwner
    );
    event PositionWithdrawn(
        uint256 indexed tokenId, address indexed owner, address indexed recipient
    );

    modifier nonReentrant() {
        if (entered) revert Reentrancy();
        entered = true;
        _;
        entered = false;
    }

    constructor(IAbyssPositionManager positionManager_) {
        if (address(positionManager_) == address(0) || address(positionManager_).code.length == 0) {
            revert InvalidPositionManager();
        }
        positionManager = positionManager_;
    }

    /// @notice Receives a position and atomically records its custody terms.
    /// @dev `data` must encode `Lock`. An unlock time of zero is permanent.
    function onERC721Received(address, address from, uint256 tokenId, bytes calldata data)
        external
        nonReentrant
        returns (bytes4)
    {
        if (msg.sender != address(positionManager)) revert InvalidPositionManager();
        if (from == address(0) || locks[tokenId].owner != address(0)) {
            revert PositionAlreadyLocked();
        }
        if (IAbyssPositionNft(address(positionManager)).ownerOf(tokenId) != address(this)) {
            revert InvalidTransfer();
        }

        Lock memory lock = abi.decode(data, (Lock));
        if (
            lock.owner == address(0) || lock.feeRecipient == address(0)
                || (!lock.permissionlessClaim && lock.claimAuthority == address(0))
                // Validator timestamp latitude is negligible relative to user-selected lock durations.
                || (lock.unlockTime != 0 && lock.unlockTime <= block.timestamp)
        ) revert InvalidInput();

        locks[tokenId] = lock;
        emit PositionLocked(
            tokenId,
            lock.owner,
            lock.feeRecipient,
            lock.claimAuthority,
            lock.unlockTime,
            lock.permissionlessClaim
        );
        return this.onERC721Received.selector;
    }

    function claim(uint256 tokenId)
        external
        nonReentrant
        returns (uint128 amount0, uint128 amount1)
    {
        Lock memory lock = _lock(tokenId);
        if (
            !lock.permissionlessClaim && msg.sender != lock.claimAuthority
                && msg.sender != lock.owner
        ) revert Unauthorized();
        (amount0, amount1) = positionManager.collect(
            tokenId, lock.feeRecipient, type(uint128).max, type(uint128).max
        );
        emit FeesClaimed(tokenId, lock.feeRecipient, amount0, amount1);
    }

    function setClaimConfiguration(
        uint256 tokenId,
        address claimAuthority,
        address feeRecipient,
        bool permissionlessClaim
    ) external {
        Lock storage lock = _ownedLock(tokenId);
        if (feeRecipient == address(0) || (!permissionlessClaim && claimAuthority == address(0))) {
            revert InvalidInput();
        }
        lock.claimAuthority = claimAuthority;
        lock.feeRecipient = feeRecipient;
        lock.permissionlessClaim = permissionlessClaim;
        emit ClaimConfigurationUpdated(tokenId, claimAuthority, feeRecipient, permissionlessClaim);
    }

    /// @notice Extends a finite lock or converts it to a permanent lock.
    function extendLock(uint256 tokenId, uint64 newUnlockTime) external {
        Lock storage lock = _ownedLock(tokenId);
        uint64 previousUnlockTime = lock.unlockTime;
        if (previousUnlockTime == 0) revert PermanentlyLocked();
        if (newUnlockTime != 0 && newUnlockTime <= previousUnlockTime) {
            revert LockCannotBeShortened();
        }
        lock.unlockTime = newUnlockTime;
        emit LockExtended(tokenId, previousUnlockTime, newUnlockTime);
    }

    function transferLockOwnership(uint256 tokenId, address newOwner) external {
        if (newOwner == address(0)) revert InvalidInput();
        Lock storage lock = _ownedLock(tokenId);
        address previousOwner = lock.owner;
        lock.owner = newOwner;
        emit LockOwnershipTransferred(tokenId, previousOwner, newOwner);
    }

    function withdraw(uint256 tokenId, address recipient) external nonReentrant {
        Lock memory lock = _lock(tokenId);
        if (msg.sender != lock.owner) revert Unauthorized();
        if (recipient == address(0)) revert InvalidInput();
        if (lock.unlockTime == 0) revert PermanentlyLocked();
        // Validator timestamp latitude is negligible relative to user-selected lock durations.
        if (block.timestamp < lock.unlockTime) revert LockActive();

        delete locks[tokenId];
        IAbyssPositionNft(address(positionManager))
            .safeTransferFrom(address(this), recipient, tokenId);
        emit PositionWithdrawn(tokenId, lock.owner, recipient);
    }

    function _lock(uint256 tokenId) private view returns (Lock memory lock) {
        lock = locks[tokenId];
        if (lock.owner == address(0)) revert PositionNotLocked();
    }

    function _ownedLock(uint256 tokenId) private view returns (Lock storage lock) {
        lock = locks[tokenId];
        if (lock.owner == address(0)) revert PositionNotLocked();
        if (msg.sender != lock.owner) revert Unauthorized();
    }
}
