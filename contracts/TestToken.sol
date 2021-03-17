//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "./ERC20Mintable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20, ERC20Mintable {
    constructor() public ERC20("Test", "TT") {
        return;
    }

    function mint(address account, uint256 amount) public override {}

    function addMinter(address minter) public override {}

    function getPriorVotes(address account, uint256 blockNumber)
        public
        view
        override
        returns (uint256)
    {
        return 0;
    }
}
