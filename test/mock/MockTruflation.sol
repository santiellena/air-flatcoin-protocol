// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@OpenZeppelin/contracts/utils/Strings.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

contract MockTruflation is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    int256 private dateInflation;
    address public oracleId;
    string public jobId;
    uint256 public fee;

    constructor(address oracleId_, string memory jobId_, uint256 fee_, address token_) ConfirmedOwner(msg.sender) {
        setChainlinkToken(token_);
        oracleId = oracleId_;
        jobId = jobId_;
        fee = fee_;
    }

    function requestDateInflation() public returns (bytes32 requestId) {
        int256 inflation = 5e17;
        fulfillDateInflation(inflation);
        return bytes32("JUST TO KEEP THE RETURNS");
    }

    function fulfillDateInflation(int256 _inflation) public {
        dateInflation = _inflation;
    }

    function changeOracle(address _oracle) public onlyOwner {
        oracleId = _oracle;
    }

    function changeJobId(string memory _jobId) public onlyOwner {
        jobId = _jobId;
    }

    function changeFee(uint256 _fee) public onlyOwner {
        fee = _fee;
    }

    function getChainlinkToken() public view returns (address) {
        return chainlinkTokenAddress();
    }

    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(link.transfer(msg.sender, link.balanceOf(address(this))), "Unable to transfer");
    }

    function getDateInflation() public view returns (int256) {
        return dateInflation;
    }

    function toInt256(bytes memory _bytes) internal pure returns (int256 value) {
        assembly {
            value := mload(add(_bytes, 0x20))
        }
    }
}
