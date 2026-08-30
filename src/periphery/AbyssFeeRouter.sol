// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { Ownable } from "solady/auth/Ownable.sol";
import { UUPSUpgradeable } from "solady/utils/UUPSUpgradeable.sol";
import { Initializable } from "solady/utils/Initializable.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "solady/utils/ReentrancyGuard.sol";
import { IAbyssFeeVault } from "../interfaces/IAbyssFeeVault.sol";

interface IAbyssBurnerConfiguration {
    function abyss() external view returns (address);

    function weth() external view returns (address);
}

/// @notice Upgradeable owner of the immutable FeeVault that converts accrued fee tokens
///         to WETH and distributes WETH or configured ABYSS between the developer and
///         protocol recipient.
/// @dev Generic distribution is WETH-only: non-WETH fee tokens must first be converted
///      with `swapToWeth`, whose route is owner-supplied free-form calldata because
///      conversion venues are deliberately not hardcoded. Converted WETH returns to the
///      vault — the single treasury balance — so `distribute` sees every fee unit once.
///      The split defaults to 20% developer / 80% protocol and applies to both WETH and
///      in-kind configured ABYSS distributions to a compatible local burner.
contract AbyssFeeRouter is Ownable, UUPSUpgradeable, Initializable, ReentrancyGuard {
    using SafeTransferLib for address;

    error InvalidConfiguration();
    error InvalidTarget();
    error CallFailed();
    error BelowMinimumOut();
    error NothingToDistribute();
    error NotWeth();

    error InvalidAbyssReceiver();
    error InvalidAbyssToken();

    event Distributed(
        address indexed caller,
        uint256 amountPulled,
        uint256 devAmount,
        uint256 protocolVaultAmount,
        uint256 protocolForwarded
    );
    event DevShareSet(uint256 oldDevBps, uint256 newDevBps);
    event DevReceiverSet(address indexed oldReceiver, address indexed newReceiver);
    event ProtocolReceiverSet(address indexed oldReceiver, address indexed newReceiver);
    event SwappedToWeth(address indexed tokenIn, uint256 amountIn, uint256 wethReceived);
    event Executed(address indexed target, uint256 value, bytes returnData);
    event AbyssDistributed(
        address indexed caller,
        address indexed token,
        uint256 amountPulled,
        uint256 devAmount,
        uint256 protocolAmount
    );

    uint256 public constant BPS_DENOMINATOR = 10_000;
    /// @dev Developer share until governance changes it: 20%.
    uint256 public constant INITIAL_DEV_BPS = 2000;

    address public feeVault;
    address public weth;
    /// @dev Protocol-fee recipient: a local burner or ancillary-chain bridge treasury.
    address public protocolReceiver;
    /// @dev Developer-fee recipient.
    address public devReceiver;
    /// @dev Developer share of each WETH and in-kind ABYSS distribution, basis points
    ///      of 1e4. The remainder goes to `protocolReceiver`.
    uint256 public devBps;
    uint256[47] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner_,
        address feeVault_,
        address weth_,
        address protocolReceiver_,
        address devReceiver_
    ) external initializer {
        if (
            owner_ == address(0) || feeVault_ == address(0) || weth_ == address(0)
                || protocolReceiver_ == address(0) || devReceiver_ == address(0)
        ) revert InvalidConfiguration();
        _initializeOwner(owner_);
        feeVault = feeVault_;
        weth = weth_;
        protocolReceiver = protocolReceiver_;
        devReceiver = devReceiver_;
        devBps = INITIAL_DEV_BPS;
    }

    // ─────────────────────── Configuration ────────────────────────
    /// @notice Sets the developer share of WETH and in-kind ABYSS distributions. The
    ///         remainder goes to the protocol receiver. Bounded to [0, 10_000] basis points.
    function setDevShare(uint256 newDevBps) external onlyOwner {
        if (newDevBps > 10_000) revert InvalidConfiguration();
        uint256 old = devBps;
        devBps = newDevBps;
        emit DevShareSet(old, newDevBps);
    }

    function setDevReceiver(address newReceiver) external onlyOwner {
        if (newReceiver == address(0)) revert InvalidConfiguration();
        address old = devReceiver;
        devReceiver = newReceiver;
        emit DevReceiverSet(old, newReceiver);
    }

    /// @notice Changes the protocol-share recipient for an explicitly reviewed treasury migration.
    function setProtocolReceiver(address newReceiver) external onlyOwner {
        if (newReceiver == address(0)) revert InvalidConfiguration();
        address old = protocolReceiver;
        protocolReceiver = newReceiver;
        emit ProtocolReceiverSet(old, newReceiver);
    }

    // ─────────────────── Owner-only conversion ────────────────────
    /// @notice Converts `amountIn` of `tokenIn` held by the vault to WETH at an
    ///         owner-chosen venue, then returns the WETH to the vault.
    /// @dev `target.call(data)` runs after approving `target` to pull `amountIn` of
    ///      `tokenIn` from this contract; the route must deliver at least `minWethOut`
    ///      WETH here. The approval is reset to zero after the call regardless of
    ///      outcome. `tokenIn == weth` is rejected: WETH needs no conversion.
    function swapToWeth(
        address tokenIn,
        uint256 amountIn,
        address target,
        bytes calldata data,
        uint256 minWethOut
    ) external onlyOwner nonReentrant {
        if (target == address(this) || target == address(0)) {
            revert InvalidTarget();
        }
        if (tokenIn == weth) revert NotWeth();
        IAbyssFeeVault(feeVault).transferToken(tokenIn, address(this), amountIn);
        SafeTransferLib.safeApprove(tokenIn, target, amountIn);
        uint256 wethBefore = weth.balanceOf(address(this));
        (bool ok,) = target.call(data);
        SafeTransferLib.safeApprove(tokenIn, target, 0);
        if (!ok) revert CallFailed();
        uint256 wethOut = weth.balanceOf(address(this)) - wethBefore;
        if (wethOut < minWethOut) revert BelowMinimumOut();
        // Converted WETH lands back in the vault: the single treasury balance.
        weth.safeTransfer(feeVault, wethOut);
        emit SwappedToWeth(tokenIn, amountIn, wethOut);
    }

    // ─────────────────────── Distribution ─────────────────────────
    /// @notice Pulls the vault's entire WETH balance and splits it: `devBps` to the
    ///         developer receiver, the remainder to the protocol receiver. Owner-only.
    function distribute() external onlyOwner nonReentrant {
        uint256 vaultBalance = weth.balanceOf(feeVault);
        if (vaultBalance == 0) revert NothingToDistribute();

        IAbyssFeeVault(feeVault).transferToken(weth, address(this), vaultBalance);

        uint256 devAmount = (vaultBalance * devBps) / BPS_DENOMINATOR;
        if (devAmount != 0) weth.safeTransfer(devReceiver, devAmount);
        // Forward everything actually held so rounding dust never accumulates.
        uint256 protocolAmount = weth.balanceOf(address(this));
        if (protocolAmount != 0) weth.safeTransfer(protocolReceiver, protocolAmount);

        // Event reports vault flows separately from pre-existing router WETH so
        // indexers can reconcile exactly which amounts came from where.
        emit Distributed(
            msg.sender, vaultBalance, devAmount, vaultBalance - devAmount, protocolAmount
        );
    }

    /// @notice Pulls the vault's entire configured ABYSS balance and splits it between
    ///         the developer and the configured local burner.
    function distributeAbyss(address token) external onlyOwner nonReentrant {
        address receiver = protocolReceiver;
        address configuredAbyss =
            _readBurnerAddress(receiver, IAbyssBurnerConfiguration.abyss.selector);
        address burnerWeth = _readBurnerAddress(receiver, IAbyssBurnerConfiguration.weth.selector);
        if (configuredAbyss == address(0) || burnerWeth != weth) {
            revert InvalidAbyssReceiver();
        }
        if (token == address(0) || token != configuredAbyss) revert InvalidAbyssToken();

        uint256 vaultBalance = token.balanceOf(feeVault);
        if (vaultBalance == 0) revert NothingToDistribute();

        IAbyssFeeVault(feeVault).transferToken(token, address(this), vaultBalance);

        uint256 devAmount = (vaultBalance * devBps) / BPS_DENOMINATOR;
        if (devAmount != 0) token.safeTransfer(devReceiver, devAmount);
        uint256 protocolAmount = vaultBalance - devAmount;
        if (protocolAmount != 0) token.safeTransfer(receiver, protocolAmount);

        emit AbyssDistributed(msg.sender, token, vaultBalance, devAmount, protocolAmount);
    }

    function _readBurnerAddress(address receiver, bytes4 selector)
        private
        view
        returns (address value)
    {
        (bool success, bytes memory data) = receiver.staticcall(abi.encodeWithSelector(selector));
        if (!success || data.length != 32) revert InvalidAbyssReceiver();

        uint256 rawValue;
        assembly ("memory-safe") {
            rawValue := mload(add(data, 0x20))
        }
        if (rawValue >> 160 != 0) revert InvalidAbyssReceiver();
        value = address(uint160(rawValue));
    }

    // ──────────────────── Owner-only execution ────────────────────
    /// @notice Executes arbitrary owner-supplied calldata (residual escape hatch for
    ///         anything `swapToWeth` cannot express). Approvals are granted by
    ///         executing `token.approve(...)` against the token itself and should be
    ///         reset to zero by the route's cleanup call.
    function execute(address target, bytes calldata data)
        external
        payable
        onlyOwner
        nonReentrant
        returns (bytes memory)
    {
        if (target == address(this) || target == address(0)) revert InvalidTarget();
        (bool ok, bytes memory result) = target.call{ value: msg.value }(data);
        if (!ok) revert CallFailed();
        emit Executed(target, msg.value, result);
        return result;
    }

    // ────────────────────────── Upgrade ───────────────────────────
    function _authorizeUpgrade(address) internal override onlyOwner { }
}
