// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {AirEngine} from "../../src/AirEngine.sol";
import {AirToken} from "../../src/AirToken.sol";
import {ERC20Mock} from "@OpenZeppelin/contracts/mocks/ERC20Mock.sol";
import {MockTruflation} from "../mocks/MockTruflation.sol";
import {LinkToken} from "../mocks/LinkToken.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployAir} from "../../script/DeployAir.s.sol";

contract AirEngineTest is Test {}
