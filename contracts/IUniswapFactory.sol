//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

interface IUniswapFactory {
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);
}
