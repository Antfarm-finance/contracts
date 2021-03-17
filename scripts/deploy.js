const { assert } = require("chai");
const { ethers } = require("ethers");
const hre = require("hardhat");

const day = 60 * 30; // FIXME 每天长度
const termsPerRound = 3; // FIXME 每轮捐赠持续天数
const lpPerRound = 2; // FIXME 每加lp赠持续天数
const delayDays = 30; // FIXME 下轮游戏开始前的等待天数
const usdtAddress = "";
const afiAddress = "";
const kswapAddress = "";
const stakeAddress = "";

let go;

async function main() {
  const GenesisOffering = await hre.ethers.getContractFactory(
    "GenesisOffering"
  );
  const round1 = parseInt(Date.now() / 1000);
  const round2 = round1 + (termsPerRound + lpPerRound + delayDays) * day;
  go = await GenesisOffering.deploy(
    usdtAddress,
    afiAddress,
    kswapAddress,
    stakeAddress,
    [
      [round1, ethers.utils.parseEther("30000")],
      [round2, ethers.utils.parseEther("26000")],
    ]
  );
  await go.deployed();

  // const TestToken = await hre.ethers.getContractFactory("TestToken");
  // const afi = await TestToken.attach(afiAddress);
  // await checkTx(afi.addMinter(go.address));

  console.log("USDT address:", usdtAddress);
  console.log("AFI address:", afiAddress);
  console.log("kSwap address:", kswapAddress);
  console.log("Stake address:", stakeAddress);
  console.log("GenesisOffering deployed to:", go.address);
  // const price = await go.getAmountsOut(ethers.utils.parseEther("1"));
  // console.log("price", ethers.utils.formatEther(price));
  // await addLiquidity(round1);
  // await emergency();
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function checkTx(promise) {
  const tx = await promise;
  const reciept = await tx.wait();
  console.log("tx", tx.hash);
  assert.ok(reciept.status);
}

async function addLiquidity(round1) {
  // const GenesisOffering = await hre.ethers.getContractFactory(
  //   "GenesisOffering"
  // );
  // const go = await GenesisOffering.attach(
  //   ""
  // );
  const TestToken = await hre.ethers.getContractFactory("TestToken");
  const usdt = await TestToken.attach(usdtAddress);
  const donateAmount = ethers.utils.parseEther("100");
  console.log("approve");
  await checkTx(usdt.approve(go.address, donateAmount));
  console.log("donate");
  await checkTx(go.donate(donateAmount));
  let usdtBalance;
  for (let i = 0; i < lpPerRound; i++) {
    const usdtBalanceSnapshot = await usdt.balanceOf(go.address);
    console.log("add liquidity", ethers.utils.formatEther(usdtBalanceSnapshot));
    const addLpId = round1 + day * (termsPerRound + i);
    console.log("round0", (await go.Rounds(0, 0)).toString(), addLpId);
    await checkTx(go.addLiquidity(addLpId));
    usdtBalance = await usdt.balanceOf(go.address);
    console.log("add liquidity done", ethers.utils.formatEther(usdtBalance));
  }
  assert.isTrue(usdtBalance.eq(0));
}

async function untilTimestap(timestamp) {
  while (Date.now() < timestamp) {
    await sleep(1000);
  }
}

async function emergency() {
  await checkTx(go.emergencyUnstake());
  // await checkTx(go.emergencyWithdraw());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
