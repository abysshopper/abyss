// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { AbyssQuoter } from "./AbyssQuoter.sol";
import { ExactInputHop } from "../types/AbyssPeripheryTypes.sol";

/// @notice Bounded failure-isolating adapter for exact-input quotes against one canonical quoter.
/// @dev Intended for eth_call. It stores no quote state, accepts no value, and has no arbitrary-call surface.
contract AbyssBatchQuoter {
    error InvalidConfiguration();
    error InvalidBatch();
    error SelfOnly();

    uint256 public constant MAX_QUOTES = 64;
    uint256 public constant MAX_TOTAL_HOPS = 256;

    struct ExactInputQuoteRequest {
        ExactInputHop[] path;
        uint256 amountIn;
    }

    struct ExactInputQuoteResult {
        bool success;
        uint256 amountOut;
        bytes4 errorSelector;
    }

    AbyssQuoter public immutable quoter;

    constructor(AbyssQuoter quoter_) {
        if (address(quoter_) == address(0) || address(quoter_).code.length == 0) {
            revert InvalidConfiguration();
        }
        quoter = quoter_;
    }

    function quoteExactInputs(ExactInputQuoteRequest[] calldata requests)
        external
        returns (ExactInputQuoteResult[] memory results)
    {
        uint256 length = requests.length;
        if (length == 0 || length > MAX_QUOTES) revert InvalidBatch();
        uint256 totalHops;
        for (uint256 i; i < length; ++i) {
            uint256 hops = requests[i].path.length;
            if (hops == 0 || hops > quoter.MAX_HOPS()) revert InvalidBatch();
            totalHops += hops;
        }
        if (totalHops > MAX_TOTAL_HOPS) revert InvalidBatch();

        results = new ExactInputQuoteResult[](length);
        for (uint256 i; i < length; ++i) {
            try this.quoteOne(requests[i]) returns (uint256 amountOut) {
                results[i] = ExactInputQuoteResult({
                    success: true, amountOut: amountOut, errorSelector: bytes4(0)
                });
            } catch (bytes memory reason) {
                results[i].errorSelector = _selector(reason);
            }
        }
    }

    function quoteOne(ExactInputQuoteRequest calldata request)
        external
        returns (uint256 amountOut)
    {
        if (msg.sender != address(this)) revert SelfOnly();
        return quoter.quoteExactInput(request.path, request.amountIn);
    }

    function _selector(bytes memory reason) private pure returns (bytes4 selector) {
        if (reason.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(reason, 0x20))
        }
    }
}
