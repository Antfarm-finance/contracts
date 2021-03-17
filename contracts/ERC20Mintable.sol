//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

interface ERC20Mintable {
    function mint(address account, uint256 amount) external;

    function addMinter(address minter) external;

    function getPriorVotes(address account, uint256 blockNumber)
        external
        view
        returns (uint256);
}
