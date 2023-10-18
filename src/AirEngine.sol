// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AirToken} from "./AirToken.sol";
import {ReentrancyGuard} from "@OpenZeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@OpenZeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {TruflationInterface} from "../interfaces/TruflationInterface.sol";
import {DateTime} from "@solidity-datetime/contracts/DateTime.sol";
import {Strings} from "@OpenZeppelin/contracts/utils/Strings.sol";
import {AutomationCompatible} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

contract AirEngine is ReentrancyGuard, AutomationCompatible {
    // Errors Section
    error AirEngine__MustBeMoreThanZero();
    error AirEngine__TokenNotAllowed();
    error AirEngine__TransferFailed();
    error AirEngine__MintTransactionFailed();
    error AirEngine__BurnedAmountCannotBeGreaterThanAmountMinted();
    error AirEngine__HealthFactorIsBroken();
    error AirEngine__HealthFactorMustBeBrokenToLiquidate();
    error AirEngine__NotEnoughTimeHasPassed();
    error AirEngine__ZeroCollateralInAccount();
    error AirEngine__ZeroMintedAirInAccount();

    // State Variables Section
    AirToken private immutable i_AIR;
    address private immutable i_collateralTokenAddress;
    address private immutable i_collateralUsdPriceFeedAddress;
    address private immutable i_truflationClient;
    address private immutable i_linkTokenAddress;
    uint256 private immutable i_interval;
    // Price feed returns a number with 8 decimals and the whole system works with 18
    int256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; //10% bonus
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MINIMUM_LINK_TRANSFERENCE = 1e18;
    uint256 private s_lastTimestamp;

    mapping(address user => uint256 amount) private s_userToAmountOfCollateralDeposited;
    mapping(address user => uint256 amount) private s_userToAmountMinted;

    // AIR PRICE
    uint256 private s_airPegPriceInUsd;

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
        address truflationClient,
        address collateralTokenAddress,
        address collateralUsdPriceFeedAddress,
        address linkTokenAddress,
        address airAddress,
        uint256 initialAirPrice,
        // interval refers to the minimum time in seconds that has
        // to pass to be able to update by infaltion the price
        uint256 interval
    ) {
        i_truflationClient = truflationClient;
        i_collateralTokenAddress = collateralTokenAddress;
        i_collateralUsdPriceFeedAddress = collateralUsdPriceFeedAddress;
        i_AIR = AirToken(airAddress);
        i_linkTokenAddress = linkTokenAddress;
        s_airPegPriceInUsd = initialAirPrice;
        i_interval = interval;
        s_lastTimestamp = block.timestamp;
    }

    // External Functions Section

    /**
     *
     * @notice checkData as parameter is needed to let chainlink automation identify the function
     * @return upkeepNeeded boolean, true if enough time has passed to execute performUpkeep
     * @return performData needs to be returned anyways because is needed to let chainlink automation identify the function
     */
    function checkUpkeep(bytes memory /* checkData */ )
        public
        view
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        upkeepNeeded = ((block.timestamp - s_lastTimestamp) >= i_interval);
        return (upkeepNeeded, "0x0");
    }

    /**
     *
     * @notice PerformData as parameter is needed to let chainlink automation identify the function
     */
    function performUpkeep(bytes calldata /* PerformData */ ) external {
        (bool upkeepNeeded,) = checkUpkeep("0x0");

        if (!upkeepNeeded) {
            revert AirEngine__NotEnoughTimeHasPassed();
        }

        _updateAirPegPriceByInflation();
    }

    /**
     * @param user Address of the user who is breaking the helath factor
     * @param debtToCover Amount of AIR you want to burn to improve the user's health factor
     * @notice You can partially liquidate a user
     * @notice You will receive a bonus for liquidating a user's debt
     */
    function liquidate(address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);

        if (startingUserHealthFactor >= MINIMUM_HEALTH_FACTOR) {
            revert AirEngine__HealthFactorMustBeBrokenToLiquidate();
        }

        uint256 debtToCoverInUsd = (debtToCover * s_airPegPriceInUsd) / PRECISION;
        uint256 tokenAmountFromDebtCovered = getCollateralTokenAmountFromUsd(debtToCoverInUsd);
        // tokenAmountFromDebtCovered is the amount to give to the user without taking into account the bonus

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(totalCollateralToRedeem, user, msg.sender);

        _burnAir(debtToCover, user, msg.sender);

        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor <= startingUserHealthFactor) {
            revert AirEngine__HealthFactorMustBeBrokenToLiquidate();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param amountCollateral amount of collateral to be deposited to back the Air minted
     * @param amountAirToMint amount of Air token to be minted
     * @dev doesnt check if params are more than zero because the functions that calls immediately check that
     */
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
     *
     * @param amountCollateral The amount of collateral to deposit
     * @notice CEI pattern [Checks - Effects - Interactions]
     */
    function depositCollateral(uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant {
        s_userToAmountOfCollateralDeposited[msg.sender] += amountCollateral;
        emit CollateradDeposited(msg.sender, i_collateralTokenAddress, amountCollateral);

        bool success = IERC20(i_collateralTokenAddress).transferFrom(msg.sender, address(this), amountCollateral);

        if (!success) {
            revert AirEngine__TransferFailed();
        }
    }

    /**
     *
     * @param amountToBurn amount to burn in the sender account
     */
    function burnAir(uint256 amountToBurn) public moreThanZero(amountToBurn) {
        _burnAir(amountToBurn, msg.sender, msg.sender);
    }

    /**
     *
     * @param amount amount of collateral that will be redeemed
     */
    function redeemCollateral(uint256 amount) public moreThanZero(amount) nonReentrant {
        _redeemCollateral(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param usdAmountInWei dollar amount times 10^18
     * @notice returns the amount of collateral that a given amount of usd is equal to
     */
    function getCollateralTokenAmountFromUsd(uint256 usdAmountInWei)
        public
        view
        moreThanZero(usdAmountInWei)
        returns (uint256)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(i_collateralUsdPriceFeedAddress);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return (usdAmountInWei * PRECISION) / uint256(price * ADDITIONAL_FEED_PRECISION);
    }

    // Internal & Private View Functions Section

    /**
     *
     * @param amount amount of AIR that will be used to pay debtor debt
     * @param debtor address of the account that its health factor is broken and its debt will be covered by liquidator
     * @param liquidator address of the account thas has Air balance and is willing to pay debtor debt
     */
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
        totalAirMintedInUsd = (totalAirMinted * s_airPegPriceInUsd) / PRECISION;
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

    /**
     *
     * @param amountCollateral amount of collateral to be redeemed
     * @param from account that will loose their collateral
     * @param to account that will receive the collateral
     * @notice this function might seem weird, but is mainly used in the liquidation process to transfer funds from one account to other
     */
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

    /**
     * @notice sends Link tokens to the Truflation contract so it can work
     * @notice updated the value of inflation in the Trueflation contract
     */
    function _updateRangeInflation() internal {
        /**
         * What if instead of updating by date, the contract updates by range of time?
         * So if the chainlink subscription runs out of LINK, you can fund it again
         * and dont loose the peg.
         * @notice this comment suggestion was already implemented but I want to keep it because is really clear
         */
        string memory startDate = _getDateFormated(s_lastTimestamp);
        string memory endDate = _getDateFormated(block.timestamp);

        IERC20(i_linkTokenAddress).transfer(i_truflationClient, MINIMUM_LINK_TRANSFERENCE);
        TruflationInterface(i_truflationClient).requestRangeInflation(startDate, endDate);
    }

    /**
     * @return rangeInflation amount of american inflation generated between the dates given in _updateRangeInflation()
     * @notice this function updates the state of Trufaltion contract and then reads it
     */
    function _getRangeInflation() internal returns (int256 rangeInflation) {
        _updateRangeInflation();
        rangeInflation = TruflationInterface(i_truflationClient).getRangeInflation();
    }

    /**
     * @notice calls _getRangeInflation() to get the inflation that was previously calculated
     * @dev maybe the require is useless because that condition will never be met
     */
    function _updateAirPegPriceByInflation() internal {
        int256 dateInflation = _getRangeInflation();

        int256 actualPrice = int256(s_airPegPriceInUsd);

        require(actualPrice > 0);
        // new price = old price * (1 + 0.inflation)
        // 65 = 100 * (1 - 0.35) --> -0.35: negative inflation
        // 650000 = 10000 * (100 - 35) --> adjusts with 0s and result is the same without precision
        s_airPegPriceInUsd = uint256((actualPrice * (1e18 + dateInflation)) / int256(PRECISION));
    }

    /**
     *
     * @param customTimestamp Any timestamp
     * @notice Formats a timestamp (in second) to a yyyy-mm-dd format
     * @dev uses the DateTime library
     */
    function _getDateFormated(uint256 customTimestamp) internal pure returns (string memory) {
        (uint256 year, uint256 month, uint256 day) = DateTime.timestampToDate(customTimestamp);

        // ISSUE: month or day are less than 10 so a zero (0) before the number must be added
        return
            string(abi.encodePacked(Strings.toString(year), "-", Strings.toString(month), "-", Strings.toString(day)));
    }

    /**
     *
     * @param account account of the user that its liquidation price is needed
     * @return liquidationPrice uint256 value with 18 decimals
     * @dev Liquidation price is calculated from the health factor function as an equation
     *
     * Initial Health Factor Ecuation =
     * ((((collateralDeposited * collateralPrice) * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION) * PRECISION) / totalMintedAirInUsd;
     *
     * Final Liquidation Price Ecuation (collateralPrice isolated, Health Factor value = 1e18 -> the minimum) =
     * (((healthFactor * totalMintedAirInUsd) * LIQUIDATION_PRECISION) / LIQUIDATION_THRESHOLD) / collateralDeposited;
     */
    function _getLiquidationAccountPrice(address account) internal view returns (uint256) {
        uint256 collateralDeposited = s_userToAmountOfCollateralDeposited[account];

        if (collateralDeposited <= 0) {
            revert AirEngine__ZeroCollateralInAccount();
        }

        (uint256 totalAirMintedInUsd,) = _getAccountInformation(account);

        if (totalAirMintedInUsd <= 0) {
            revert AirEngine__ZeroMintedAirInAccount();
        }

        uint256 liquidationHealthFactor = 1e18;

        // From the Health Factor equation I developed a new one for liquidation price
        // BETTER EXPLAINED IN NAT-SPECs
        // / PRECISION -> (this division is making the ecuation loose their decimals)
        uint256 liquidationPrice = (
            (((liquidationHealthFactor * totalAirMintedInUsd)) * LIQUIDATION_PRECISION) / LIQUIDATION_THRESHOLD
        ) / collateralDeposited;

        return liquidationPrice;
    }

    // Public & External View Functions Section

    /**
     *
     * @param account an address whose information is needed
     * @return totalAirMintedInUsd by the account
     * @return collateralValueInUsd deposited and available on the account (not the all time deposited amount) in dollars
     */
    function getAccountInformation(address account) public view returns (uint256, uint256) {
        return _getAccountInformation(account);
    }

    /**
     *
     * @param amount a given amount of the collateral token
     * @return value the value in dollars of the amount of token collateral given as parameter
     */
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

    /**
     * @return healthFactor a value that represents the state of the account of the sender of collateral vs debt
     * @notice refer to the _healthFactor() function to see how it is calculated
     */
    function getHealthFactor() external view returns (uint256) {
        uint256 healthFactor = _healthFactor(msg.sender);
        return healthFactor;
    }

    function getAirPriceInUsd() public view returns (uint256) {
        return s_airPegPriceInUsd;
    }

    function getCollateralTokenAddress() public view returns (address) {
        return i_collateralTokenAddress;
    }

    function getAmountAirMinted() public view returns (uint256) {
        return s_userToAmountMinted[msg.sender];
    }

    function getAmountOfCollateralDeposited() public view returns (uint256) {
        return s_userToAmountOfCollateralDeposited[msg.sender];
    }

    /**
     * @notice returns the collateral limit price that breaks the health factor of the sender account
     * @return liquidationPrice uint256 value with 18 decimals
     */
    function getLiquidationAccountPrice() public view returns (uint256) {
        return _getLiquidationAccountPrice(msg.sender);
    }
}
