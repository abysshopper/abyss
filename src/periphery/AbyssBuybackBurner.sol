// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { Ownable } from "solady/auth/Ownable.sol";
import { UUPSUpgradeable } from "solady/utils/UUPSUpgradeable.sol";
import { Initializable } from "solady/utils/Initializable.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "solady/utils/ReentrancyGuard.sol";

interface IAbyssToken {
    function burn(uint256 amount) external;
}

interface IWeth {
    function withdraw(uint256 amount) external;
}

/// @notice Upgradeable treasury sink that buys ABYSS with WETH via owner-chosen
///         venues, burns it, and pays the operator a native-ETH gas refund.
/// @dev Every function is owner-only and scoped; there are no permissionless entry
///      points. The buyback is balance-aware: whatever ABYSS the contract holds after
///      the route completes is burned in full, so stray transfers and route dust are
///      swept by the next buyback automatically. Gas refunds unwrap WETH and send
///      native ETH to the operator-supplied recipient, capped by `maxGasRefund`.
contract AbyssBuybackBurner is Ownable, UUPSUpgradeable, Initializable, ReentrancyGuard {
    using SafeTransferLib for address;

    error InvalidConfiguration();
    error InvalidTarget();
    error CallFailed();
    error BelowMinimumOut();
    error NothingToRefund();
    error InvalidRecipient();

    /// @dev Required to receive native ETH unwrapped by `refundGas`: WETH9's
    ///      `withdraw` pays the caller, so the burner must accept plain ETH sends.
    receive() external payable { }

    event BuybackAndBurned(address indexed target, uint256 wethAmount, uint256 abyssBought);
    event MaxGasRefundSet(uint256 oldMax, uint256 newMax);
    event RefundPaid(address indexed recipient, uint256 wethAmount);

    address public weth;
    address public abyss;
    uint256 public maxGasRefund;
    uint256[47] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner_, address weth_, address abyss_) external initializer {
        if (owner_ == address(0) || weth_ == address(0) || abyss_ == address(0)) {
            revert InvalidConfiguration();
        }
        _initializeOwner(owner_);
        weth = weth_;
        abyss = abyss_;
    }

    // ────────────────────────── Config ────────────────────────────
    function setMaxGasRefund(uint256 newMax) external onlyOwner {
        uint256 old = maxGasRefund;
        maxGasRefund = newMax;
        emit MaxGasRefundSet(old, newMax);
    }

    // ──────────────────── Owner-only buyback ──────────────────────
    /// @notice Buys ABYSS with `wethAmount` WETH via owner-chosen calldata, then
    ///         burns the contract's entire ABYSS balance.
    /// @dev `target` is approved for exactly `wethAmount` before the call and reset
    ///      to zero after, regardless of outcome. The ABYSS balance-delta across the
    ///      call must be at least `minAbyssOut`; the full resulting balance (delta
    ///      plus any stray holdings) is then burned.
    function buybackAndBurn(
        address target,
        bytes calldata data,
        uint256 wethAmount,
        uint256 minAbyssOut
    ) external onlyOwner nonReentrant {
        if (target == address(this) || target == address(0)) {
            revert InvalidTarget();
        }
        SafeTransferLib.safeApprove(weth, target, wethAmount);
        uint256 abyssBefore = abyss.balanceOf(address(this));
        (bool ok,) = target.call(data);
        SafeTransferLib.safeApprove(weth, target, 0);
        if (!ok) revert CallFailed();
        uint256 abyssOut = abyss.balanceOf(address(this)) - abyssBefore;
        if (abyssOut < minAbyssOut) revert BelowMinimumOut();
        // Balance-aware burn: sweep everything held, not just this route's delta.
        uint256 toBurn = abyss.balanceOf(address(this));
        if (toBurn != 0) IAbyssToken(abyss).burn(toBurn);
        emit BuybackAndBurned(target, wethAmount, toBurn);
    }

    /// @notice Pays `recipient` up to `wethAmount` (bounded by `maxGasRefund` and the
    ///         WETH balance) by unwrapping WETH and sending native ETH. Owner-only.
    /// @dev The keeper's gas token is native ETH: the refund path wraps no assumptions
    ///      about the recipient being able to handle ERC-20.
    function refundGas(address recipient, uint256 wethAmount) external onlyOwner nonReentrant {
        if (recipient == address(0)) revert InvalidRecipient();
        uint256 paid = wethAmount;
        uint256 cap = maxGasRefund;
        if (paid > cap) paid = cap;
        uint256 available = weth.balanceOf(address(this));
        if (paid > available) paid = available;
        if (paid == 0) revert NothingToRefund();
        IWeth(weth).withdraw(paid);
        SafeTransferLib.safeTransferETH(recipient, paid);
        emit RefundPaid(recipient, paid);
    }

    // ────────────────────────── Upgrade ───────────────────────────
    function _authorizeUpgrade(address) internal override onlyOwner { }
}
