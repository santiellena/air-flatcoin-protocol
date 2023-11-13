// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {ERC20Mock} from "@OpenZeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethContractAddress;
        address wethUsdPriceFeed;
        address linkAddress;
        uint256 deployerKey;
        uint256 automationInterval;
    }

    int256 public constant ETH_USD_PRICE = 2000e8;
    uint8 public constant DECIMALS = 8;

    address public constant GOERLI_ORACLEID = 0x6888BdA6a975eCbACc3ba69CA2c80d7d7da5A344;
    string public constant GOERLI_JOBID = "d220e5e687884462909a03021385b7ae";
    uint256 public constant GOERLI_FEE = 500000000000000000;
    address public constant GOERLI_LINK_TOKEN = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;
    uint256 public constant GOERLI_CHAINID = 5;
    uint256 public constant AVALANCHE_FUJI_CHAINID = 43113;
    address public constant AVALANCHE_FUJI_LINK_TOKEN = 0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846;
    address public constant DEFAULT_ANVIL_PUBLIC_KEY = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public constant SECONDARY_ANVIL_PUBLIC_KEY = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == GOERLI_CHAINID) {
            activeNetworkConfig = getGoerliEthConfig();
        } else if (block.chainid == AVALANCHE_FUJI_CHAINID) {
            activeNetworkConfig = getAvalancheFujiConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getGoerliEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            // Weenus Token: https://goerli.etherscan.io/address/0xaFF4481D10270F50f203E0763e2597776068CBc5#code
            wethContractAddress: 0xaFF4481D10270F50f203E0763e2597776068CBc5,
            wethUsdPriceFeed: 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e,
            linkAddress: GOERLI_LINK_TOKEN,
            deployerKey: vm.envUint("PRIVATE_KEY"),
            automationInterval: 86400 // One day in seconds
        });
    }

    function getAvalancheFujiConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethContractAddress: 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6, // INVALID CONTRACT ADDRESS.
            wethUsdPriceFeed: 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e,
            linkAddress: AVALANCHE_FUJI_LINK_TOKEN,
            deployerKey: vm.envUint("PRIVATE_KEY"),
            automationInterval: 86400 // One day in seconds
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        uint256 deployer = vm.envUint("DEFAULT_ANVIL_KEY");

        vm.startBroadcast(deployer);
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock();

        console.log("WETH Contract Address: ", address(wethMock));

        wethMock.mint(DEFAULT_ANVIL_PUBLIC_KEY, 2000e18); // AFTER THIS I JUST NEED TO MAKE THE TRANSACTION TO CALL THE AIR ENGINE TO MINT SOME TOKENS

        wethMock.mint(SECONDARY_ANVIL_PUBLIC_KEY, 4000e18);

        LinkToken linkToken = new LinkToken();

        console.log("LINK Contract Address: ", address(linkToken));

        // MockTruflation truflationMock = new MockTruflation(address(0), "", 500000000000000000, address(linkToken));

        vm.stopBroadcast();

        return NetworkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed),
            wethContractAddress: address(wethMock),
            linkAddress: address(linkToken),
            deployerKey: deployer,
            automationInterval: 86400 // One day in seconds
        });
    }
}
