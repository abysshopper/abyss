// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { AbyssQuotePoolBase } from "./AbyssQuotePoolBase.sol";
import { PoolProfile } from "../types/AbyssTypes.sol";

contract AbyssQuotePool is AbyssQuotePoolBase {
    constructor() AbyssQuotePoolBase(PoolProfile.QUOTE) { }
}
