// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@OpenZeppelin/contracts/utils/Strings.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

contract MockTruflation is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    int256 private rangeInflation;
    address public oracleId;
    string public jobId;
    uint256 public fee;

    constructor(address oracleId_, string memory jobId_, uint256 fee_, address token_) ConfirmedOwner(msg.sender) {
        setChainlinkToken(token_);
        oracleId = oracleId_;
        jobId = jobId_;
        fee = fee_;
    }

    function requestRangeInflation(string memory startDate, string memory endDate) public returns (bytes32 requestId) {
        bytes memory inflationInBytes = abi.encode(1e16); // Inflation fixed to testing
        fulfillRangeInflation(inflationInBytes);
        return bytes32(abi.encodePacked(startDate, endDate));
    }

    function fulfillRangeInflation(bytes memory _inflation) public {
        rangeInflation = toInt256(_inflation);
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

    function getRangeInflation() public view returns (int256) {
        return rangeInflation;
    }

    function toInt256(bytes memory _bytes) internal pure returns (int256 value) {
        assembly {
            value := mload(add(_bytes, 0x20))
        }
    }
}
