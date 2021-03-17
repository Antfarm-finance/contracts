//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

interface IStake {
    function getLPPoolIndex() external returns (uint256);

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function claim(uint256 _pid) external;

    function emergencyWithdraw(uint256 _pid) external;

    function pendingReward(uint256 _pid, address _user)
        external
        returns (uint256);
}
