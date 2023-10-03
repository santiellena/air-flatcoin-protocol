// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20, ERC20Burnable} from "@OpenZeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@OpenZeppelin/contracts/access/Ownable.sol";

contract AirToken is ERC20Burnable, Ownable {
    error AirToken__AmountMustBeMoreThanZero();
    error AirToken__CantBurnMoreThanBalance();
    error AirToken__NotZeroAddress();

    constructor() ERC20("AirToken", "AIR") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (_amount <= 0) {
            // Cant burn zero or a negative amount
            revert AirToken__AmountMustBeMoreThanZero();
        }

        if (balance < _amount) {
            // Cant burn amount not owned
            revert AirToken__CantBurnMoreThanBalance();
        }

        // super keyword let us use ERC20Burnable functions
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            // Don't want coins to be minted and burned at the same time
            revert AirToken__NotZeroAddress();
        }

        if (_amount <= 0) {
            revert AirToken__AmountMustBeMoreThanZero();
        }

        _mint(_to, _amount);
        return true;
    }
}
