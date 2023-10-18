// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {AirEngine} from "../../src/AirEngine.sol";
import {AirToken} from "../../src/AirEngine.sol";
import {ERC20Mock} from "@OpenZeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    AirEngine airEngine;
    AirToken airToken;
    ERC20Mock wethContractAddress;
    MockV3Aggregator wethPriceFeed;

    uint128 MAX_COLLATERAL_AMOUNT = type(uint96).max;
    address[] public usersThatDepositedCollateral;

    constructor(AirEngine _airEngine, AirToken _airToken) {
        airEngine = _airEngine;
        airToken = _airToken;

        address tokenCollateralAddress = airEngine.getCollateralTokenAddress();
        wethContractAddress = ERC20Mock(tokenCollateralAddress);

        wethPriceFeed = MockV3Aggregator(address(airEngine.getCollateralPriceFeedAddress()));
    }

    function depositCollateral(uint256 amount) public {
        uint256 validAmount = bound(amount, 1, MAX_COLLATERAL_AMOUNT);

        vm.startPrank(msg.sender);

        wethContractAddress.mint(msg.sender, validAmount);

        bool approved = wethContractAddress.approve(address(airEngine), validAmount);
        assert(approved == true);

        airEngine.depositCollateral(validAmount);

        vm.stopPrank();

        usersThatDepositedCollateral.push(msg.sender);
    }

    function redeemCollateral(uint256 amount) public {
        uint256 maxValidAmount = airEngine.getAmountOfCollateralDeposited();

        if (maxValidAmount == 0) return;

        uint256 validAmount = bound(amount, 1, maxValidAmount);

        airToken.approve(address(airEngine), validAmount);
        airEngine.redeemCollateral(validAmount);
    }

    function updateCollateralPrice(uint96 randomPrice) public {
        int256 newRandomPrice = int256(uint256(randomPrice));

        wethPriceFeed.updateAnswer(newRandomPrice);
    }

    function mintDsc(uint256 amount) public {
        if (usersThatDepositedCollateral.length == 0) {
            return;
        }

        uint256 randomUserIndex = bound(amount, 0, usersThatDepositedCollateral.length - 1);

        address USER = usersThatDepositedCollateral[randomUserIndex];

        (uint256 totalAirMintedInUsd, uint256 collateralValueInUsd) = airEngine.getAccountInformation(USER);

        int256 maxAirToMint = (int256(collateralValueInUsd) / 2) - int256(totalAirMintedInUsd);

        if (maxAirToMint < 0) {
            return;
        }

        amount = bound(amount, 0, uint256(maxAirToMint));

        if (amount == 0) {
            return;
        }

        vm.prank(USER);
        airEngine.mintAir(amount);
    }
}
