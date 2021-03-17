// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ERC20Votable.sol";

contract Token is ERC20Votable, Ownable {
    using SafeMath for uint256;
    uint256 public constant _maxSupply = 6_000_000 * 1e18;

    mapping(address => bool) _minters;
    address[] _mintersList;

    modifier noOverflow(uint256 _amt) {
        require(_maxSupply >= totalSupply().add(_amt), "totalSupply overflow");
        _;
    }

    modifier onlyMinter() {
        require(_minters[msg.sender] || owner() == msg.sender);
        _;
    }

    constructor() public ERC20("AntFarm Finance", "AFI") {
        return;
    }

    function addMinter(address minter) public onlyOwner {
        require(!_minters[minter], "minter already exists");
        _minters[minter] = true;
        _mintersList.push(minter);
    }

    function removeMinter(address minter) public onlyOwner {
        bool flag;
        for (uint256 i = 0; i < _mintersList.length; i++) {
            if (_mintersList[i] == minter) {
                _mintersList[i] = _mintersList[_mintersList.length - 1];
                _mintersList.pop();
                delete _minters[minter];
                flag = true;
            }
        }
        if (!flag) revert("minter not found");
    }

    function mint(address _address, uint256 _amount) public noOverflow(_amount) onlyMinter {
        _mint(_address, _amount);
    }
}
