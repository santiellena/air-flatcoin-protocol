// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {AirToken} from "../src/AirToken.sol";
import {AirEngine} from "../src/AirEngine.sol";
import {Truflation} from "../src/Truflation.sol";
import {MockTruflation} from "../test/mocks/MockTruflation.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";

contract DeployAir is Script {
    uint256 public constant INITIAL_AIR_PRICE = 1e18;
    uint256 constant INITIAL_LINK_SUPPLY = 1000000000000000000000000;

    address wethUsdPriceFeed;
    address weth;
    address link;

    function run() public returns (AirToken, AirEngine, MockTruflation, HelperConfig, uint256) {
        HelperConfig helperConfig = new HelperConfig();

        (
            address wethContractAddress,
            address priceFeed,
            address linkAddress,
            uint256 deployerKey,
            uint256 automationInterval
        ) = helperConfig.activeNetworkConfig();

        wethUsdPriceFeed = priceFeed;
        weth = wethContractAddress;
        link = linkAddress;

        vm.startBroadcast(deployerKey);

        MockTruflation mockTrufaltion = new MockTruflation(address(0), "", 500000000000000000, address(link));

        AirToken airToken = new AirToken();

        AirEngine airEngine =
        new AirEngine(address(mockTrufaltion), weth, wethUsdPriceFeed, link, address(airToken), INITIAL_AIR_PRICE, automationInterval);

        airToken.transferOwnership(address(airEngine));

        LinkToken(linkAddress).transfer(address(this), INITIAL_LINK_SUPPLY);

        vm.stopBroadcast();
        return (airToken, airEngine, mockTrufaltion, helperConfig, automationInterval);
    }
}
