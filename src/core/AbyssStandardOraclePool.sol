// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { AbyssOraclePoolBase } from "./AbyssOraclePoolBase.sol";
import { PoolProfile } from "../types/AbyssTypes.sol";

contract AbyssStandardOraclePool is AbyssOraclePoolBase {
    constructor() AbyssOraclePoolBase(PoolProfile.STANDARD_ORACLE) { }
}
