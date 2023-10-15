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
    uint256 automationInterval;

    address public USER = makeAddr("USER");
    address public ANOTHER_USER = makeAddr("ANOTHER_USER");

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_MINTED_BALANCE = 100 ether;
    uint256 public constant FIRST_TIME_DEPOSIT = 2 ether;
    uint256 public constant FIRST_TIME_DEPOSIT_OTHER = 3 ether;
    uint256 public constant FIRST_TIME_MINT_AMOUNT = 2000e18;
    uint256 private constant MINIMUM_LINK_TRANSFERENCE = 1e18;

    function setUp() public {
        deployer = new DeployAir();

        (airToken, airEngine, mockTruflation, helperConfig, automationInterval) = deployer.run();

        (wethContractAddress, wethUsdPriceFeed, linkAddress, deployerKey, automationInterval) =
            helperConfig.activeNetworkConfig();

        ERC20Mock(wethContractAddress).mint(USER, STARTING_MINTED_BALANCE);
    }

    // MODIFIERS SECTION

    modifier depositCollateral(address account) {
        vm.startPrank(account);
        bool approved = ERC20Mock(wethContractAddress).approve(address(airEngine), AMOUNT_COLLATERAL);
        assert(approved == true);
        airEngine.depositCollateral(FIRST_TIME_DEPOSIT);
        vm.stopPrank();
        _;
    }

    modifier updateAirPegPriceByInflation() {
        airEngine.performUpkeep("0x0");
        _;
    }

    modifier timePass() {
        vm.warp(block.timestamp + automationInterval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier fundWithLinkAndApprove(address account) {
        vm.prank(address(deployer));
        LinkToken(linkAddress).transfer(account, MINIMUM_LINK_TRANSFERENCE);
        bool approved = LinkToken(linkAddress).approve(address(airEngine), MINIMUM_LINK_TRANSFERENCE);
        assert(approved == true);
        _;
    }

    modifier mintAir(address account) {
        (, uint256 actualCollateralValueInUsd) = airEngine.getAccountInformation(account);
        uint256 expectedMintedAirLimit = actualCollateralValueInUsd / 2;
        vm.prank(account);
        airEngine.mintAir(expectedMintedAirLimit);
        _;
    }

    modifier depositAndMint(address account) {
        vm.startPrank(account);
        bool approved = ERC20Mock(wethContractAddress).approve(address(airEngine), AMOUNT_COLLATERAL);
        assert(approved == true);
        airEngine.depositCollateralAndMintAir(FIRST_TIME_DEPOSIT, FIRST_TIME_MINT_AMOUNT);
        vm.stopPrank();
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

    function testGetAccountCollateralInUsd() public depositCollateral(USER) {
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

    function testGetAccountInformationOnlyWithDeposit() public depositCollateral(USER) {
        (uint256 actualTotalDscMinted, uint256 actualCollateralValueInUsd) = airEngine.getAccountInformation(USER);

        uint256 amoutOfUserCollateral = FIRST_TIME_DEPOSIT;

        uint256 expectedCollateralValueInUsd = airEngine.getCollateralUsdValue(amoutOfUserCollateral);

        assertEq(expectedCollateralValueInUsd, actualCollateralValueInUsd);

        uint256 expectedTotalDscMinted = 0;

        assertEq(expectedTotalDscMinted, actualTotalDscMinted);
    }

    function testGetHealthFactorOnlyWithDeposit() public depositCollateral(USER) {
        vm.prank(USER);
        uint256 healthFactor = airEngine.getHealthFactor();
        uint256 MINIMUM_HEALTH_FACTOR = 1e18; // As DSC amount is 0, the function returns the minimum posible health value.
        assertEq(healthFactor, MINIMUM_HEALTH_FACTOR);
    }

    // Upkeep Tests

    function testCheckUpkeepReturnsFalseIfNotEnoughTimeHasPassed() public {
        vm.prank(USER);
        (bool upkeepNeeded,) = airEngine.checkUpkeep("0x0");

        assertEq(upkeepNeeded, false);
    }

    function testCheckUpkeepReturnsTrueIfEnoughTimeHasPassed() public timePass {
        vm.prank(USER);
        (bool upkeepNeeded,) = airEngine.checkUpkeep("0x0");

        assertEq(upkeepNeeded, true);
    }

    function testPerformUpkeepRevertsIfNotEnoughTimeHasPassed() public {
        vm.prank(USER);
        vm.expectRevert(AirEngine.AirEngine__NotEnoughTimeHasPassed.selector);
        airEngine.performUpkeep("0x0");
    }

    function testPerformUpkeepUpdatesAirPegPrice() public timePass fundWithLinkAndApprove(address(airEngine)) {
        vm.prank(USER);
        airEngine.performUpkeep("0x0");

        uint256 expectedAirPegPrice = 101e16;
        uint256 actualAirPegPrice = airEngine.getAirPriceInUsd();

        assertEq(expectedAirPegPrice, actualAirPegPrice);
    }

    // Mint Tests

    function testMintRevertsIfAmountIsZero() public depositCollateral(USER) {
        vm.prank(USER);
        vm.expectRevert(AirEngine.AirEngine__MustBeMoreThanZero.selector);
        airEngine.mintAir(0);
    }

    function testMintRevertsIfHealthFactorBreaks() public depositCollateral(USER) {
        // collateral in eth is == FIRST_TIME_COLLATERAL

        (, uint256 actualCollateralValueInUsd) = airEngine.getAccountInformation(USER);

        // actualCollateralValueInUsd can back half of its amount in DSC because of the threshold
        uint256 expectedMintedAirLimit = actualCollateralValueInUsd / 2;

        vm.prank(USER);
        vm.expectRevert(AirEngine.AirEngine__HealthFactorIsBroken.selector);
        airEngine.mintAir(expectedMintedAirLimit + 1);
        // If you want to do so, you can try adding more or substracting to check that the limit is well calculated
    }

    function testHelthFactorIs1e18WhenTheCollateralIsDoubleTheAirMintedInUsd()
        public
        depositCollateral(USER)
        mintAir(USER)
    {
        uint256 expectedHealthFactor = 1e18;

        vm.prank(USER);
        uint256 actualHealthFactor = airEngine.getHealthFactor();

        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    // Deposit & Mint Tests

    function testDepositAndMintAirRevertsIfCollateralAmountIsNotEnough() public {
        uint256 collateralAmountInEth = 1 ether; // 1e18
        uint256 amountAirToMint = 1500e18;

        vm.startPrank(USER);
        bool approved = ERC20Mock(wethContractAddress).approve(address(airEngine), AMOUNT_COLLATERAL);
        assert(approved == true);
        vm.expectRevert(AirEngine.AirEngine__HealthFactorIsBroken.selector);
        airEngine.depositCollateralAndMintAir(collateralAmountInEth, amountAirToMint);
        vm.stopPrank();
    }
}
