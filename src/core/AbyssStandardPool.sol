// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { AbyssPoolBase } from "./AbyssPoolBase.sol";
import { PoolProfile } from "../types/AbyssTypes.sol";

contract AbyssStandardPool is AbyssPoolBase {
    constructor() AbyssPoolBase(PoolProfile.STANDARD) { }
}
