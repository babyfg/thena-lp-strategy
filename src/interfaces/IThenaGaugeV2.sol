// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IThenaGaugeV2 {
    function rewardToken() external view returns (address);

    function earned(address account) external view returns (uint256);

    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function withdrawAll() external;

    function getReward() external;
}
