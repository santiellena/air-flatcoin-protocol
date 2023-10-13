// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@OpenZeppelin/contracts/utils/Strings.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

contract Truflation is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    int256 private dateInflation;
    address public oracleId;
    string public jobId;
    uint256 public fee;

    // Please refer to
    // https://github.com/truflation/quickstart/blob/main/network.md
    // for oracle address. job id, and fee for a given network

    constructor(address oracleId_, string memory jobId_, uint256 fee_, address token_) ConfirmedOwner(msg.sender) {
        setChainlinkToken(token_);
        oracleId = oracleId_;
        jobId = jobId_;
        fee = fee_;
    }

    function requestDateInflation() public returns (bytes32 requestId) {
        Chainlink.Request memory req =
            buildChainlinkRequest(bytes32(bytes(jobId)), address(this), this.fulfillDateInflation.selector);
        req.add("service", "truflation/at-date");
        req.add("keypath", "");
        req.add("data", '{"date":"2023-10-05","location":"us"}'); // DATE HARDCODED JUST FOR DEVELOPMENT
        req.add("abi", "int256");
        req.add("multiplier", "1000000000000000000");
        req.add("refundTo", Strings.toHexString(uint160(msg.sender), 20));
        return sendChainlinkRequestTo(oracleId, req, fee);
    }

    function fulfillDateInflation(bytes32 _requestId, bytes memory _inflation)
        public
        recordChainlinkFulfillment(_requestId)
    {
        dateInflation = toInt256(_inflation);
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
