const { expect } = require("chai");
const { ethers } = require("hardhat");
const { expectRevert, time } = require("@openzeppelin/test-helpers");

describe("GenesisOffering", async function () {
  const day = 60 * 60 * 24;
  let ofi, usdt, swap, genesisOffering, owner, user1, startedAt;
  it("部署 USDT", async function () {
    [owner, user1] = await ethers.getSigners();
    const TestToken = await ethers.getContractFactory("TestToken");
    usdt = await TestToken.deploy("test USDT", "USDT");
    await usdt.deployed();
    expect(await usdt.symbol()).to.equal("USDT");
  });
  it("部署 AFI", async function () {
    const TestToken = await ethers.getContractFactory("TestToken");
    ofi = await TestToken.deploy("test AFI", "AFI");
    await ofi.deployed();
    expect(await ofi.symbol()).to.equal("AFI");
  });
  it("部署 Uniswap", async function () {
    const TestUniswap = await ethers.getContractFactory("TestUniswap");
    swap = await TestUniswap.deploy(usdt.address, ofi.address);
    await swap.deployed();
    expect(await swap.token0()).to.equal(usdt.address);
  });
  it("部署 GenesisOffering", async function () {
    const GenesisOffering = await ethers.getContractFactory("GenesisOffering");
    startedAt = (await ethers.getDefaultProvider().getBlock()).timestamp + 1000;

    genesisOffering = await GenesisOffering.deploy(
      usdt.address,
      ofi.address,
      swap.address,
      [
        [startedAt, ethers.utils.parseUnits("1", 21)],
        [startedAt + 60 * 60 * 24 * 17, ethers.utils.parseUnits("8", 20)],
      ]
    );
  });
  it("day0 未开始不能投", async function () {
    await usdt.mint(owner.address, ethers.utils.parseUnits("1", 20));
    await expectRevert(
      genesisOffering.purchase(ethers.utils.parseUnits("1", 20)),
      "invalid opcode"
    );
    await usdt.approve(
      genesisOffering.address,
      ethers.utils.parseUnits("1", 20)
    );
    await expectRevert(
      genesisOffering.purchase(ethers.utils.parseUnits("1", 20)),
      "invalid opcode"
    );
    expect(await genesisOffering.isBUIDLing()).false;
  });
  it("day1 参与创世发行", async function () {
    await time.increaseTo(startedAt);
    await genesisOffering.purchase(ethers.utils.parseUnits("1", 20));
    expect(await genesisOffering.isBUIDLing()).false;
    const round = await genesisOffering.getRound(0);
    expect(round[0]).eq(startedAt);
  });
  it("day2 领取创世奖励", async function () {
    await expectRevert(genesisOffering.claim(), "invalid opcode");
    expect(await ofi.balanceOf(owner.address)).to.equal(0);
    await time.increaseTo(startedAt + day);
    await genesisOffering.claim();
    // 重复领取
    await expectRevert(genesisOffering.claim(), "invalid opcode");
    expect(await ofi.balanceOf(owner.address)).to.equal(
      ethers.utils.parseUnits("1", 21)
    );
  });
  it("day2投 day4领", async function () {
    await usdt.mint(owner.address, ethers.utils.parseUnits("1", 20));
    await usdt.approve(
      genesisOffering.address,
      ethers.utils.parseUnits("1", 20)
    );
    await genesisOffering.purchase(ethers.utils.parseUnits("5", 19));
    await genesisOffering.purchase(ethers.utils.parseUnits("5", 19));
    await time.increaseTo(startedAt + 3 * day);
    await genesisOffering.claim();
    expect(await ofi.balanceOf(owner.address)).to.equal(
      ethers.utils.parseUnits("2", 21)
    );
  });
  it("day4 user1投1次100,owner投2次50", async function () {
    await usdt.mint(user1.address, ethers.utils.parseUnits("1", 20));
    await usdt
      .connect(user1)
      .approve(genesisOffering.address, ethers.utils.parseUnits("1", 20));
    await genesisOffering
      .connect(user1)
      .purchase(ethers.utils.parseUnits("1", 20));

    await usdt.mint(owner.address, ethers.utils.parseUnits("1", 20));
    await usdt.approve(
      genesisOffering.address,
      ethers.utils.parseUnits("1", 20)
    );
    await genesisOffering.purchase(ethers.utils.parseUnits("5", 19));
    await genesisOffering.purchase(ethers.utils.parseUnits("5", 19));
  });
  it("day5 领取", async function () {
    await time.increaseTo(startedAt + 4 * day);
    await genesisOffering.claim();
    expect(await ofi.balanceOf(owner.address)).to.equal(
      ethers.utils.parseUnits("2.5", 21)
    );
    await genesisOffering.connect(user1).claim();
    expect(await ofi.balanceOf(user1.address)).to.equal(
      ethers.utils.parseUnits("0.5", 21)
    );
  });
  it("day8 不能投资", async function () {
    await time.increaseTo(startedAt + 7 * day);
    await usdt.mint(owner.address, ethers.utils.parseUnits("1", 20));
    await usdt.approve(
      genesisOffering.address,
      ethers.utils.parseUnits("1", 20)
    );
    await expectRevert(
      genesisOffering.purchase(ethers.utils.parseUnits("1", 20)),
      "invalid opcode"
    );
  });
  it("day8 设置 USDTAFI 的 LP，BUIDL", async function () {
    const usdtAmt = ethers.utils.parseUnits("10000000000", 18);
    const ofiAmt = ethers.utils.parseUnits("100000000000", 18);
    await usdt.mint(owner.address, usdtAmt);
    await usdt.approve(swap.address, usdtAmt);
    await ofi.mint(owner.address, ofiAmt);
    await ofi.approve(swap.address, ofiAmt);
    await swap.addLiquidity(
      usdt.address,
      ofi.address,
      usdtAmt,
      ofiAmt,
      0,
      0,
      usdt.address,
      0
    );
    await genesisOffering.setUSDT_AFI_LP(swap.address);
    expect(await genesisOffering.isBUIDLing()).true;
    await genesisOffering.BUIDL();
    expect(await genesisOffering.LastBUIDLPrevDay()).to.gt(0);
  });
  it("day8 再次 BUIDL", async function () {
    await expectRevert(genesisOffering.BUIDL(), "invalid opcode");
    expect(await genesisOffering.isOffering()).false;
  });
  it("day9-17 BUIDL", async function () {
    for (let i = 0; i < 9; i++) {
      await time.increaseTo(startedAt + (8 + i) * day);
      await genesisOffering.BUIDL();
    }
  });
  it("day18 BUIDL失败，开启新一轮", async function () {
    await time.increaseTo(startedAt + 17 * day);
    await expectRevert(genesisOffering.BUIDL(), "invalid opcode");
    const round = await genesisOffering.getRound(0);
    expect(round[0]).eq(startedAt + 17 * day);
  });
  it("投资一次新一轮游戏", async function () {
    await usdt.mint(owner.address, ethers.utils.parseUnits("1", 20));
    await usdt.approve(
      genesisOffering.address,
      ethers.utils.parseUnits("1", 20)
    );
    await genesisOffering.purchase(ethers.utils.parseUnits("1", 20));
    expect(await genesisOffering.isBUIDLing()).false;
  });
  it("第2期结束不能投资", async function () {
    await time.increaseTo(startedAt + 24 * day);
    await usdt.mint(owner.address, ethers.utils.parseUnits("1", 20));
    await usdt.approve(
      genesisOffering.address,
      ethers.utils.parseUnits("1", 20)
    );
    await expectRevert(
      genesisOffering.purchase(ethers.utils.parseUnits("1", 20)),
      "invalid opcode"
    );
    await genesisOffering.BUIDL();
  });
  it("第2期 BUIDL 结束不能 BUIDL", async function () {
    await time.increaseTo(startedAt + 34 * day);
    await expectRevert(genesisOffering.BUIDL(), "invalid opcode");
  });
});
