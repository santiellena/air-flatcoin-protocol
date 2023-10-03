// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AirToken} from "./AirToken.sol";
import {ReentrancyGuard} from "@OpenZeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@OpenZeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract AirEngine is ReentrancyGuard {
    // Errors Section
    error AirEngine__MustBeMoreThanZero();
    error AirEngine__TokenNotAllowed();
    error AirEngine__TransferFailed();
    error AirEngine__MintTransactionFailed();
    error AirEngine__BurnedAmountCannotBeGreaterThanAmountMinted();
    error AirEngine__HealthFactorIsBroken();

    // State Variables Section
    AirToken private immutable i_AIR;
    address private immutable i_collateralTokenAddress;
    address private immutable i_collateralUsdPriceFeedAddress;
    // Price feed returns a number with 8 decimals and the whole system works with 18
    int256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; //10% bonus
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;

    mapping(address user => uint256 amount) private s_userToAmountOfCollateralDeposited;
    mapping(address user => uint256 amount) private s_userToAmountMinted;

    // AIR PRICE
    uint256 public airPrice;

    // Events Section
    event CollateradDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    // Modifiers Section
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert AirEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isCollateralTokenAddressAllowed(address collateralTokenAddress) {
        if (collateralTokenAddress == i_collateralTokenAddress) {
            revert AirEngine__TokenNotAllowed();
        }
        _;
    }

    // Constructor Section
    constructor(
        address collateralTokenAddress,
        address collateralUsdPriceFeedAddress,
        address AirAddress,
        uint256 initialAirPrice
    ) {
        i_collateralTokenAddress = collateralTokenAddress;
        i_collateralUsdPriceFeedAddress = collateralUsdPriceFeedAddress;
        i_AIR = AirToken(AirAddress);
        airPrice = initialAirPrice;
    }

    // External Functions Section

    function depositCollateralAndMintAir(uint256 amountCollateral, uint256 amountAirToMint) external {
        depositCollateral(amountCollateral);
        mintAir(amountAirToMint);
    }

    /**
     * @param amountCollateral Amount of collateral to redeem
     * @param amountAirToBurn Amount of AIR to burn
     * @notice If the health factor breaks because of this tx, it will revert
     */
    function redeemCollateralForAir(uint256 amountCollateral, uint256 amountAirToBurn)
        external
        moreThanZero(amountCollateral)
        moreThanZero(amountAirToBurn)
    {
        burnAir(amountAirToBurn);
        redeemCollateral(amountCollateral);
    }

    // Public Functions Section

    function mintAir(uint256 amountAirToMint) public moreThanZero(amountAirToMint) {
        s_userToAmountMinted[msg.sender] += amountAirToMint;

        // Checks if the amount of collateral deposited by the user
        // is enough to mint (threshold is not broken)
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_AIR.mint(msg.sender, amountAirToMint);
        if (!minted) {
            revert AirEngine__MintTransactionFailed();
        }
    }

    /**
     * @param amountCollateral The amount of collateral to deposit
     * @notice CEI pattern
     */
    function depositCollateral(uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant {
        s_userToAmountOfCollateralDeposited[msg.sender] += amountCollateral;
        emit CollateradDeposited(msg.sender, i_collateralTokenAddress, amountCollateral);

        bool success = IERC20(i_collateralTokenAddress).transferFrom(msg.sender, address(this), amountCollateral);

        if (!success) {
            revert AirEngine__TransferFailed();
        }
    }

    function burnAir(uint256 amountToBurn) public moreThanZero(amountToBurn) {
        _burnAir(amountToBurn, msg.sender, msg.sender);
    }

    function redeemCollateral(uint256 amount) public moreThanZero(amount) nonReentrant {
        _redeemCollateral(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // Internal & Private View Functions Section

    function _burnAir(uint256 amount, address debtor, address liquidator) private moreThanZero(amount) {
        if (s_userToAmountMinted[debtor] < amount) {
            revert AirEngine__BurnedAmountCannotBeGreaterThanAmountMinted();
        }
        s_userToAmountMinted[debtor] -= amount;

        bool success = i_AIR.transferFrom(liquidator, address(this), amount);

        if (!success) {
            revert AirEngine__TransferFailed();
        }

        i_AIR.burn(amount);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalAirMintedInUsd, uint256 collateralValueInUsd)
    {
        uint256 totalAirMinted = s_userToAmountMinted[user];
        uint256 collateralDeposited = s_userToAmountOfCollateralDeposited[user];
        collateralValueInUsd = getCollateralUsdValue(collateralDeposited);
        totalAirMintedInUsd = totalAirMinted * airPrice;

        return (totalAirMinted, collateralValueInUsd);
    }

    /**
     *
     * @param user Address to check health factor
     * @notice Returns how close to liquidation an address is
     * @notice (health factor value) < 1 --> Liquidated
     * @notice https://docs.aave.com/risk/asset-risk/risk-parameters#health-factor
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalAirMintedInUsd, uint256 collateralValueInUsd) = _getAccountInformation(user);

        if (totalAirMintedInUsd == 0) {
            return MINIMUM_HEALTH_FACTOR;
        }
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalAirMintedInUsd;
    }

    function _revertIfHealthFactorIsBroken(address user) private view {
        uint256 userHealthFactor = _healthFactor(user);

        if (userHealthFactor < MINIMUM_HEALTH_FACTOR) {
            revert AirEngine__HealthFactorIsBroken();
        }
    }

    function _redeemCollateral(uint256 amountCollateral, address from, address to)
        private
        moreThanZero(amountCollateral)
    {
        s_userToAmountOfCollateralDeposited[from] -= amountCollateral;
        emit CollateralRedeemed(from, to, i_collateralTokenAddress, amountCollateral);

        bool success = IERC20(i_collateralTokenAddress).transfer(to, amountCollateral);

        if (!success) {
            revert AirEngine__TransferFailed();
        }
    }

    // Public & External View Functions Section

    function getAccountInformation(address account) public view returns (uint256, uint256) {
        return _getAccountInformation(account);
    }

    function getCollateralUsdValue(uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(i_collateralUsdPriceFeedAddress);

        /**
         * latestRoundData returns:
         *
         *   - uint80 roundId,
         *   - int256 answer,
         *   - uint256 startedAt,
         *   - uint256 updatedAt,
         *   - uint80 answeredInRound
         */
        (, int256 price,,,) = priceFeed.latestRoundData();
        // price == actualTokenPrice * 1e8;

        return uint256(uint256(price * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
