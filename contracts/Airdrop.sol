// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IToken.sol";

contract Airdrop {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IToken public _token;
    mapping(address => bool) public isAddressClaimed;
    uint256 public maxTokenMint;
    uint256 public startTimestamp;
    uint256 public claimedToken;
    uint256 public currentClaimPeriodInAmount;
    uint256 public currentClaimableClaimAmonutPerAddress = 1_000_000e18;

    constructor(IToken token, uint256 _startTimestamp) public {
        assert(_startTimestamp >= block.timestamp);
        _token = token;
        maxTokenMint = _token.maxSupply().mul(405).div(1000);
        startTimestamp = _startTimestamp;
    }

    function claim() public {
        assert(startTimestamp > 0 && block.timestamp >= startTimestamp);
        assert(!isAddressClaimed[msg.sender]);
        assert(
            claimedToken.add(currentClaimableClaimAmonutPerAddress) <=
                maxTokenMint
        );
        isAddressClaimed[msg.sender] = true;
        claimedToken = claimedToken.add(currentClaimableClaimAmonutPerAddress);
        currentClaimPeriodInAmount = currentClaimPeriodInAmount.add(
            currentClaimableClaimAmonutPerAddress
        );
        _token.mint(msg.sender, currentClaimableClaimAmonutPerAddress);
        if (currentClaimPeriodInAmount >= maxTokenMint.mul(3).div(100)) {
            currentClaimableClaimAmonutPerAddress = currentClaimableClaimAmonutPerAddress
                .div(2);
            currentClaimPeriodInAmount = 0;
        }
    }
}
