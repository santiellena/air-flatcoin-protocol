// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@OpenZeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethContractAddress;
        address wethUsdPriceFeed;
        address linkAddress;
        uint256 deployerKey;
    }

    int256 public constant ETH_USD_PRICE = 2000e8;
    uint8 public constant DECIMALS = 8;

    address public constant GOERLI_ORACLEID = 0x6888BdA6a975eCbACc3ba69CA2c80d7d7da5A344;
    string public constant GOERLI_JOBID = "d220e5e687884462909a03021385b7ae";
    uint256 public constant GOERLI_FEE = 500000000000000000;
    address public constant GOERLI_TOKEN = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;
    uint256 public constant GOERLI_CHAINID = 5;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == GOERLI_CHAINID) {
            activeNetworkConfig = getGoerliEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getGoerliEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethContractAddress: 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6, // NOT REALLY KNOWN YET
            wethUsdPriceFeed: 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e,
            linkAddress: GOERLI_TOKEN,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock();

        LinkToken linkToken = new LinkToken();

        // MockTruflation truflationMock = new MockTruflation(address(0), "", 500000000000000000, address(linkToken));

        vm.stopBroadcast();

        return NetworkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed),
            wethContractAddress: address(wethMock),
            linkAddress: address(linkToken),
            deployerKey: vm.envUint("DEFAULT_ANVIL_KEY")
        });
    }
}
