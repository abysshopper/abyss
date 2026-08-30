// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { OwnedTwoStep } from "../governance/OwnedTwoStep.sol";

contract FeeVault is OwnedTwoStep {
    error TokenTransferFailed();

    event TreasuryTransfer(address indexed token, address indexed recipient, uint256 amount);

    constructor(address initialOwner) OwnedTwoStep(initialOwner) { }

    function transferToken(address token, address recipient, uint256 amount) external onlyOwner {
        if (recipient == address(0)) revert InvalidOwner();
        (bool success, bytes memory result) = token.call(
            abi.encodeWithSelector(
                bytes4(keccak256("transfer(address,uint256)")), recipient, amount
            )
        );
        if (!success || (result.length != 0 && !abi.decode(result, (bool)))) {
            revert TokenTransferFailed();
        }
        emit TreasuryTransfer(token, recipient, amount);
    }
}
