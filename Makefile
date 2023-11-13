-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

SECONDARY_ACCOUNT_PUBLIC_KEY := 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
SECONDARY_ANVIL_KEY := 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d

APPROVED_WETH_AMOUNT := 1000000000000000000000

DEPOSIT_COLLATERAL_AMOUNT := 1000000000000000000

MINTED_AIR_AMOUNT := 1000000000000000000000

MINTED_AIR_AMOUNT_LIMIT := 2000000000000000000000

BURN_AIR_AMOUNT := 500000000000000000000

DEBT_TO_COVER := 500000000000000000000


## ¡¡¡ An explanation of what these commands do can be found on the README.md file !!!


install :
	forge install transmissions11/solmate --no-commit && forge install RollaProject/solidity-datetime --no-commit && forge install cyfrin/foundry-devops@0.0.11 --no-commit && forge install smartcontractkit/chainlink --no-commit && forge install foundry-rs/forge-std@v1.5.3 --no-commit && forge install openzeppelin/openzeppelin-contracts@v4.8.3 --no-commit

anvil:; anvil

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

ifeq ($(findstring --network goerli,$(ARGS)),--network goerli)
	NETWORK_ARGS := --rpc-url $(GOERLI_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

ifeq ($(findstring --network avalanchefuji,$(ARGS)),--network avalanchefuji)
	NETWORK_ARGS := --rpc-url $(AVALANCHE_FUJI_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

deploy:
	@forge script script/DeployAir.s.sol:DeployAir $(NETWORK_ARGS)

## These commands must be configured before being executed
depositAndMint:
	@cast send <WETH Token Contract Address> "approve(address,uint256)" <AirEngine Contract Address> $(APPROVED_WETH_AMOUNT) --private-key $(DEFAULT_ANVIL_KEY)
	@cast send <AirEngine Contract Address> "depositCollateralAndMintAir(uint256,uint256)" $(DEPOSIT_COLLATERAL_AMOUNT) $(MINTED_AIR_AMOUNT) --private-key $(DEFAULT_ANVIL_KEY)

deposit:
	@cast send <WETH Token Contract Address> "approve(address,uint256)" <AirEngine Contract Address> $(APPROVED_WETH_AMOUNT) --private-key $(DEFAULT_ANVIL_KEY)
	@cast send <AirEngine Contract Address> "depositCollateral(uint256)" $(DEPOSIT_COLLATERAL_AMOUNT) --private-key $(DEFAULT_ANVIL_KEY)

mint:
	@cast send <AirEngine Contract Address> "mintAir(uint256)" $(MINTED_AIR_AMOUNT) --private-key $(DEFAULT_ANVIL_KEY)

burn:
	@cast send <WETH Token Contract Address> "approve(address,uint256)" <AirEngine Contract Address> $(APPROVED_WETH_AMOUNT) --private-key $(DEFAULT_ANVIL_KEY)
	@cast send <AirEngine Contract Address> "burnAir(uint256)" $(BURN_AIR_AMOUNT) --private-key $(DEFAULT_ANVIL_KEY)

increaseAirPrice:
	@cast send <AirEngine Contract Address> "performUpkeep(bytes)" "0x0" --private-key $(DEFAULT_ANVIL_KEY)

# This command will revert if increaseAirPrice wasn't executed at least one time
liquidate:
	@cast send <AirEngine Contract Address> "liquidate(address,uint256)" $(SECONDARY_ACCOUNT_PUBLIC_KEY) $(DEBT_TO_COVER) --private-key $(DEFAULT_ANVIL_KEY)

healthFactor:
	@cast call <AirEngine Contract Address> "getHealthFactor()" --private-key $(DEFAULT_ANVIL_KEY)

depositAndMintSecondAccount:
	@cast send <WETH Token Contract Address> "approve(address,uint256)" <AirEngine Contract Address> $(APPROVED_WETH_AMOUNT) --private-key $(SECONDARY_ANVIL_KEY)
	@cast send <AirEngine Contract Address> "depositCollateralAndMintAir(uint256,uint256)" $(DEPOSIT_COLLATERAL_AMOUNT) $(MINTED_AIR_AMOUNT_LIMIT) --private-key $(SECONDARY_ANVIL_KEY)
