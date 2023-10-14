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
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract AirEngineTest is Test {
    AirEngine airEngine;
    AirToken airToken;
    DeployAir deployer;
    HelperConfig helperConfig;
    address wethContractAddress;
    address wethUsdPriceFeed;
    address linkAddress;
    uint256 deployerKey;
    MockTruflation mockTruflation;

    address public USER = makeAddr("USER");
    address public ANOTHER_USER = makeAddr("ANOTHER_USER");

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_MINTED_BALANCE = 100 ether;
    uint256 public constant FIRST_TIME_DEPOSIT = 2 ether;
    uint256 public constant FIRST_TIME_DEPOSIT_OTHER = 3 ether;
    uint256 public constant FIRST_TIME_MINT_AMOUNT = 2000e18;

    function setUp() public {
        deployer = new DeployAir();

        (airToken, airEngine, mockTruflation, helperConfig) = deployer.run();

        (wethContractAddress, wethUsdPriceFeed, linkAddress, deployerKey) = helperConfig.activeNetworkConfig();

        ERC20Mock(wethContractAddress).mint(USER, STARTING_MINTED_BALANCE);
    }

    // MODIFIERS SECTION

    modifier depositCollateral() {
        vm.startPrank(USER);
        bool approved = ERC20Mock(wethContractAddress).approve(address(airEngine), AMOUNT_COLLATERAL);
        assert(approved == true);
        airEngine.depositCollateral(FIRST_TIME_DEPOSIT);
        vm.stopPrank();
        _;
    }

    modifier updateAirPegPriceByInfation() {
        // Simulate the Automation Contract calls and modifies the state
        _;
    }

    // Price Feed Tests

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmountInWei = 20000e18;
        // 1 ETH => 2000 USD (setted in mock aggregator v3 interface)
        uint256 actualAmount = airEngine.getCollateralTokenAmountFromUsd(usdAmountInWei);
        uint256 expectedAmount = 10e18;

        assertEq(actualAmount, expectedAmount);
    }

    function testGetAccountCollateralInUsd() public depositCollateral {
        uint256 expectedCollateralInUsd = airEngine.getCollateralUsdValue(FIRST_TIME_DEPOSIT);
        (, uint256 actualCollateralInUsd) = airEngine.getAccountInformation(USER);

        assertEq(expectedCollateralInUsd, actualCollateralInUsd);
    }

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;

        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = airEngine.getCollateralUsdValue(ethAmount);

        assertEq(expectedUsd, actualUsd);
    }

    // Deposit Collateral Tests

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        bool approved = ERC20Mock(wethContractAddress).approve(address(airEngine), AMOUNT_COLLATERAL);
        assert(approved == true);
        vm.expectRevert(AirEngine.AirEngine__MustBeMoreThanZero.selector);
        airEngine.depositCollateral(0);
    }

    function testGetAccountInformationOnlyWithDeposit() public depositCollateral {
        (uint256 actualTotalDscMinted, uint256 actualCollateralValueInUsd) = airEngine.getAccountInformation(USER);

        uint256 amoutOfUserCollateral = FIRST_TIME_DEPOSIT;

        uint256 expectedCollateralValueInUsd = airEngine.getCollateralUsdValue(amoutOfUserCollateral);

        assertEq(expectedCollateralValueInUsd, actualCollateralValueInUsd);

        uint256 expectedTotalDscMinted = 0;

        assertEq(expectedTotalDscMinted, actualTotalDscMinted);
    }

    function testGetHealthFactorOnlyWithDeposit() public depositCollateral {
        vm.prank(USER);
        uint256 healthFactor = airEngine.getHealthFactor();
        uint256 MINIMUM_HEALTH_FACTOR = 1e18; // As DSC amount is 0, the function returns the minimum posible health value.
        assertEq(healthFactor, MINIMUM_HEALTH_FACTOR);
    }
}
