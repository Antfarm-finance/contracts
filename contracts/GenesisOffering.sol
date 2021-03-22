//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ERC20Mintable.sol";
import "./IUniswapRouter.sol";
import "./IUniswapFactory.sol";
import "./IStake.sol";

contract GenesisOffering is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    uint256 public constant DurationPerTerm = 30 minutes; //FIXME 1 days
    uint256 public constant DaysPurchasePerRound = 3;
    uint256 public constant DaysAddLiquidityPerRound = 2;
    uint256 private constant SlippageTolerance = 990;

    IUniswapRouter public UniswapV2Router;
    IUniswapFactory public UniswapV2Factory;
    IStake public Stake;
    IERC20 public USDT;
    IERC20 public AFI;

    uint256 public GlobalPurchased;
    uint256 public GlobalHarvested;
    uint256 public GlobalHarvestClaimed;
    uint256 public EmergencyWithdrawTokenSnapshot;
    uint256 public EmergencyWithdrawUSDTSnapshot;
    uint256 public EmergencyWithdrawTotalSupplySnapshot;
    uint256 public EmergencyWithdrawBlockSnapshot;
    uint256[] public Terms;
    uint256[2][] public Rounds;

    mapping(uint256 => uint256) public TermTotalPurchased;
    mapping(uint256 => uint256) public RoundTotalPurchased;
    mapping(address => uint256) public UserGlobalPurchased;
    mapping(address => uint256) public UserTotalHarvested;
    mapping(address => bool) public UserEmergencyClaimed;
    mapping(address => mapping(uint256 => uint256)) public UserTermPurchased;
    mapping(address => mapping(uint256 => bool)) public UserTermClaimed;

    constructor(
        address USDT_,
        address AFI_,
        address UniswapV2Router_,
        address Stake_,
        uint256[2][] memory Rounds_
    ) {
        USDT = IERC20(USDT_);
        AFI = IERC20(AFI_);
        Rounds = Rounds_;
        UniswapV2Router = IUniswapRouter(UniswapV2Router_);
        Stake = IStake(Stake_);

        Terms.push(0);
        USDT.safeApprove(address(UniswapV2Router), 2**256 - 1);
        AFI.safeApprove(address(UniswapV2Router), 2**256 - 1);
        UniswapV2Factory = IUniswapFactory(UniswapV2Router.factory());
    }

    modifier notInEmergencyMode() {
        assert(EmergencyWithdrawBlockSnapshot == 0);
        _;
    }

    modifier inEmergencyMode() {
        assert(EmergencyWithdrawBlockSnapshot != 0);
        _;
    }

    function isOffering() public view returns (bool) {
        uint256[2] memory round = getRound(0);
        return
            round[0] != 0 &&
            block.timestamp >= round[0] &&
            block.timestamp <
            round[0].add(DurationPerTerm.mul(DaysPurchasePerRound));
    }

    modifier isAddLiquiditying(uint256 termTimestamp) {
        uint256[2] memory round = getRound(termTimestamp);
        assert(
            round[0] != 0 &&
                termTimestamp >=
                round[0].add(DurationPerTerm.mul(DaysPurchasePerRound)) &&
                termTimestamp <
                round[0].add(
                    DurationPerTerm.mul(
                        DaysPurchasePerRound + DaysAddLiquidityPerRound
                    )
                )
        );
        _;
    }

    function getRound(uint256 blockTimestamp)
        public
        view
        returns (uint256[2] memory round)
    {
        blockTimestamp = blockTimestamp == 0 ? block.timestamp : blockTimestamp;
        for (uint256 i = 0; i < Rounds.length; i++) {
            if (
                blockTimestamp >= Rounds[i][0] &&
                blockTimestamp <
                Rounds[i][0].add(
                    DurationPerTerm.mul(
                        DaysPurchasePerRound + DaysAddLiquidityPerRound
                    )
                )
            ) {
                return Rounds[i];
            }
        }
    }

    function getTerm(uint256 blockTimestamp) public view returns (uint256) {
        blockTimestamp = blockTimestamp == 0 ? block.timestamp : blockTimestamp;
        uint256[2] memory round = getRound(blockTimestamp);
        return
            round[0].add(
                blockTimestamp.sub(round[0]).div(DurationPerTerm).mul(
                    DurationPerTerm
                )
            );
    }

    function addLiquidity(uint256 timestamp)
        public
        isAddLiquiditying(timestamp)
        notInEmergencyMode
    {
        uint256 termTimestamp = getTerm(timestamp);
        assert(TermTotalPurchased[termTimestamp] == 0);
        TermTotalPurchased[termTimestamp] = 1;
        rebase(repatriation());
        IERC20 lp =
            IERC20(UniswapV2Factory.getPair(address(USDT), address(AFI)));
        lp.safeApprove(address(Stake), lp.balanceOf(address(this)));
        Stake.deposit(Stake.getLPPoolIndex(), lp.balanceOf(address(this)));
    }

    function donate(uint256 amount_) public notInEmergencyMode {
        assert(isOffering());
        USDT.safeTransferFrom(msg.sender, address(this), amount_);
        GlobalPurchased = GlobalPurchased.add(amount_);
        UserGlobalPurchased[msg.sender] = UserGlobalPurchased[msg.sender].add(
            amount_
        );
        uint256 termDate = getTerm(0);
        if (Terms[Terms.length - 1] != termDate) {
            Terms.push(termDate);
        }
        UserTermPurchased[msg.sender][termDate] = UserTermPurchased[msg.sender][
            termDate
        ]
            .add(amount_);
        TermTotalPurchased[termDate] = TermTotalPurchased[termDate].add(
            amount_
        );
        uint256[2] memory round = getRound(0);
        RoundTotalPurchased[round[0]] = RoundTotalPurchased[round[0]].add(
            amount_
        );
    }

    function balanceOf(address account_, uint256 termId)
        public
        view
        returns (uint256)
    {
        if (termId >= getTerm(0) || UserTermClaimed[account_][termId]) {
            return 0;
        }
        uint256[2] memory round = getRound(termId);
        return
            TermTotalPurchased[termId] == 0
                ? 0
                : round[1].mul(UserTermPurchased[account_][termId]).div(
                    TermTotalPurchased[termId]
                );
    }

    function claim(uint256 termId) public notInEmergencyMode {
        uint256 reward = balanceOf(msg.sender, termId);
        assert(reward > 0);
        UserTermClaimed[msg.sender][termId] = true;
        ERC20Mintable(address(AFI)).mint(msg.sender, reward);
    }

    function pendingReward(address user) public returns (uint256) {
        uint256 totalHarvest =
            GlobalHarvested.add(
                Stake.pendingReward(Stake.getLPPoolIndex(), address(this))
            );
        uint256 totalIncome =
            totalHarvest.mul(UserGlobalPurchased[user]).div(GlobalPurchased);
        return totalIncome.sub(UserTotalHarvested[user]);
    }

    function harvest() public notInEmergencyMode {
        uint256 balanceSnapshot = AFI.balanceOf(address(this));
        Stake.claim(Stake.getLPPoolIndex());
        GlobalHarvested = GlobalHarvested.add(
            AFI.balanceOf(address(this)).sub(balanceSnapshot)
        );
        uint256 pending = pendingReward(msg.sender);
        assert(pending > 0);
        GlobalHarvestClaimed = GlobalHarvestClaimed.add(pending);
        UserTotalHarvested[msg.sender] = UserTotalHarvested[msg.sender].add(
            pending
        );
        AFI.safeTransfer(msg.sender, pending);
    }

    function getAmountsOut(uint256 amountIn) public view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(USDT);
        path[1] = address(AFI);
        uint256 amountOut = UniswapV2Router.getAmountsOut(amountIn, path)[1];
        assert(amountOut > 0);
        return amountOut;
    }

    function emergencyUnstake() public onlyOwner notInEmergencyMode {
        EmergencyWithdrawBlockSnapshot = block.number;
        Stake.emergencyWithdraw(Stake.getLPPoolIndex());
        IERC20 lp =
            IERC20(UniswapV2Factory.getPair(address(USDT), address(AFI)));
        uint256 lpBalance = lp.balanceOf(address(this));
        assert (lpBalance > 0);
        lp.safeApprove(address(UniswapV2Router), lpBalance);
            UniswapV2Router.removeLiquidity(
                address(USDT),
                address(AFI),
                lpBalance,
                0,
                0,
                address(this),
                block.timestamp
            );
        EmergencyWithdrawTokenSnapshot = AFI.balanceOf(address(this));
        EmergencyWithdrawUSDTSnapshot = USDT.balanceOf(address(this));
        EmergencyWithdrawTotalSupplySnapshot = AFI.totalSupply();
    }

    function emergencyWithdraw() public inEmergencyMode {
        assert(!UserEmergencyClaimed[msg.sender]);
        UserEmergencyClaimed[msg.sender] = true;
        ERC20Mintable mintable = ERC20Mintable(address(AFI));
        uint256 snapshot =
            mintable.getPriorVotes(msg.sender, EmergencyWithdrawBlockSnapshot);
        AFI.safeTransfer(
            msg.sender,
            EmergencyWithdrawTokenSnapshot.mul(snapshot).div(EmergencyWithdrawTotalSupplySnapshot)
        );
        USDT.safeTransfer(
            msg.sender,
            EmergencyWithdrawUSDTSnapshot.mul(snapshot).div(EmergencyWithdrawTotalSupplySnapshot)
        );
    }

    function repatriation() private returns (uint256) {
        uint256[2] memory round = getRound(0);
        uint256 total =
            RoundTotalPurchased[round[0]].div(DaysAddLiquidityPerRound);
        uint256 toBuy = total.mul(4).div(10);
        uint256 usdtToToken = getAmountsOut(toBuy);
        uint256 tokenAmountOutMin =
            usdtToToken.mul(SlippageTolerance).div(1000);
        address[] memory path = new address[](2);
        path[0] = address(USDT);
        path[1] = address(AFI);
        uint256[] memory outAmounts =
            UniswapV2Router.swapExactTokensForTokens(
                toBuy,
                tokenAmountOutMin,
                path,
                address(this),
                block.timestamp
            );
        assert(outAmounts.length > 0 && outAmounts[outAmounts.length - 1] > 0);
        return total.sub(toBuy);
    }

    function rebase(uint256 toLP) private {
        uint256 usdtToToken = getAmountsOut(toLP);
        uint256 expectToken = usdtToToken.mul(1000).div(95);
        uint256 afiBalance =
            AFI.balanceOf(address(this)).sub(
                GlobalHarvested.sub(GlobalHarvestClaimed)
            );
        if (afiBalance < expectToken)
            ERC20Mintable(address(AFI)).mint(
                address(this),
                expectToken.sub(afiBalance)
            );
        UniswapV2Router.addLiquidity(
            address(USDT),
            address(AFI),
            toLP,
            expectToken,
            toLP,
            usdtToToken,
            address(this),
            block.timestamp
        );
    }
}
