// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

/// @notice Solvency-preserving quote-fee arithmetic using pips.
library QuoteFeeMath {
    uint256 internal constant FEE_DENOMINATOR = 1_000_000;

    error InvalidFee();
    error AmountOverflow();

    function feeFromGross(uint256 grossAmount, uint24 feePips)
        internal
        pure
        returns (uint256 feeAmount)
    {
        _checkFee(feePips);
        uint256 quotient = grossAmount / FEE_DENOMINATOR;
        uint256 remainder = grossAmount % FEE_DENOMINATOR;
        feeAmount = quotient * feePips + _ceilDiv(remainder * feePips, FEE_DENOMINATOR);
    }

    function netFromGross(uint256 grossAmount, uint24 feePips)
        internal
        pure
        returns (uint256 netAmount, uint256 feeAmount)
    {
        feeAmount = feeFromGross(grossAmount, feePips);
        netAmount = grossAmount - feeAmount;
    }

    function grossFromNet(uint256 netAmount, uint24 feePips)
        internal
        pure
        returns (uint256 grossAmount, uint256 feeAmount)
    {
        _checkFee(feePips);
        uint256 netDenominator = FEE_DENOMINATOR - feePips;
        uint256 quotient = netAmount / netDenominator;
        uint256 remainder = netAmount % netDenominator;
        feeAmount = quotient * feePips + _ceilDiv(remainder * feePips, netDenominator);
        if (feeAmount > type(uint256).max - netAmount) revert AmountOverflow();
        grossAmount = netAmount + feeAmount;
    }

    function splitProtocolFee(uint256 stepFee, uint8 denominator)
        internal
        pure
        returns (uint256 lpFee, uint256 protocolFee)
    {
        if (denominator != 0 && (denominator < 4 || denominator > 10)) revert InvalidFee();
        protocolFee = denominator == 0 ? 0 : stepFee / denominator;
        lpFee = stepFee - protocolFee;
    }

    function _checkFee(uint24 feePips) private pure {
        if (feePips >= FEE_DENOMINATOR) revert InvalidFee();
    }

    function _ceilDiv(uint256 x, uint256 y) private pure returns (uint256) {
        return x == 0 ? 0 : (x - 1) / y + 1;
    }
}
