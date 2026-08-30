// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

/// @notice Data-only contract used to hold one immutable creation-code chunk.
contract BytecodeChunk {
    error InvalidChunkLength();

    constructor(bytes memory data) {
        if (data.length == 0 || data.length > 24_000) revert InvalidChunkLength();
        assembly ("memory-safe") {
            return(add(data, 0x20), mload(data))
        }
    }
}
