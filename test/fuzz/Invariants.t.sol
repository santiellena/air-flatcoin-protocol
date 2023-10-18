// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test, console} from "forge-std/Test.sol";
import {Handler} from "./Handler.t.sol";

import {DeployAir} from "../../script/DeployAir.s.sol";
import {AirEngine} from "../../src/AirEngine.sol";
import {AirToken} from "../../src/AirToken.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

import {IERC20} from "@OpenZeppelin/contracts/token/ERC20/IERC20.sol";

contract Invariants is StdInvariant, Test {
    uint256 constant PRECISION = 1e18;

    AirEngine airEngine;
    AirToken airToken;
    DeployAir deployer;
    HelperConfig helperConfig;
    address wethContractAddress;
    address wethUsdPriceFeed;
    uint256 deployerKey;
    Handler handler;

    function setUp() external {
        console.log(address(this));
        deployer = new DeployAir();
        (airToken, airEngine,, helperConfig,) = deployer.run();

        (
            wethUsdPriceFeed,
            wethContractAddress,
            /**
             * linkAddress
             */
            ,
            deployerKey,
            /**
             * automationInterval
             */
        ) = helperConfig.activeNetworkConfig();

        handler = new Handler(airEngine, airToken);
        targetContract(address(handler));
    }

    function invariantProtocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 wethBalance = IERC20(wethContractAddress).balanceOf(address(airEngine));

        uint256 wethInUsdBalance = airEngine.getCollateralUsdValue(wethBalance);

        uint256 totalSupply = airToken.totalSupply();

        uint256 airPrice = airEngine.getAirPriceInUsd();

        uint256 totalSupplyInUsd = (totalSupply * airPrice) / PRECISION;

        if (wethInUsdBalance == 0) {
            assert(wethInUsdBalance == totalSupplyInUsd);
        } else {
            assert(wethInUsdBalance > totalSupplyInUsd);
        }
    }

    function invariantGettersDontRevert() public view {
        //airEngine.getAccountCollateralInUsd();
        //airEngine.getAccountInformation();
        airEngine.getAmountAirMinted();
        //airEngine.getAmountOfCollateralDeposited();
        airEngine.getHealthFactor();
        //airEngine.getTokenAmountFromUsd();
        airEngine.getCollateralTokenAddress();
        //airEngine.getUsdValue();
    }
}
