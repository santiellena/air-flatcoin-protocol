// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface TruflationInterface {
    function requestRangeInflation(string memory, string memory) external returns (bytes32 requestId);

    function fulfillRangeInflation(bytes32 _requestId, bytes memory _inflation) external;

    function changeOracle(address _oracle) external;

    function changeJobId(string memory _jobId) external;

    function changeFee(uint256 _fee) external;

    function getChainlinkToken() external view returns (address);

    function withdrawLink() external;

    function getRangeInflation() external view returns (int256);

    function toInt256(bytes memory _bytes) external pure returns (int256 value);
}
