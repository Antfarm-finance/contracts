// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IMigratorChef {
    function migrate(IERC20 token) external returns (IERC20);
}

interface IToken {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function mint(address to, uint256 amount) external;
}

// MasterChef is the master of Reward Token.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once Token is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract Stake is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Tokens
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accRewardPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accRewardPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. Tokens to distribute per block.
        uint256 lastRewardBlock; // Last block number that Tokens distribution occurs.
        uint256 accRewardPerShare; // Accumulated reward per share, times 1e12. See below.
        uint256 depositFee; // deposit fee, 300 means 300/10000 = 3%
    }

    // The reward TOKEN!
    IToken public rewardToken;
    // Dev address.
    address public devAddr1;
    address public devAddr2;
    // Fee address
    address public feeAddr;
    // Reward tokens created per block.
    //uint256 public constant rewardPerBlock = 16e18;
    // Bonus muliplier for early makers.
    // uint256 public constant BONUS_MULTIPLIER = 5;
    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The block number when reward token mining starts.
    uint256 public startBlock;

    uint256 public constant maxTokenMint = 5832000e18;  // 6,000,000 * 97.2%
    uint256 public tokenMinted;

    // OKex:
    // 3.72 seconds per block
    // 30 days (2,592,000 seconds) = 2,592,000/3.72 = 696774 blocks
    // first 30 days rewards 1680000, so in first 30 days, every block rewards 1680000/696774 = 2.411111
    uint256 constant halvedPeriodInBlock = 696774;
    uint256 constant baseReward = 2411111e12;

    uint256 constant maxUint256 = 2**256 - 1;
    uint256 public LPPoolIndex = maxUint256;

    constructor(
        IToken _rewardToken,
        address _devAddr1,
        address _devAddr2,
        address _feeAddr,
        uint256 _startBlock
    ) public {
        rewardToken = _rewardToken;
        devAddr1 = _devAddr1;
        devAddr2 = _devAddr2;
        feeAddr = _feeAddr;
        startBlock = _startBlock;
    }

    // set AFI-USDT LP pool index
    function setLPPoolIndex(uint256 _LPPoolIndex) public onlyOwner {
        LPPoolIndex = _LPPoolIndex;
    }

    // return AFI-USDT LP pool index
    function getLPPoolIndex() external view returns (uint256) {
        require(LPPoolIndex < maxUint256, "LPPoolIndex is not set");
        return LPPoolIndex;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        uint256 _depositFee,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken : _lpToken,
                allocPoint : _allocPoint,
                lastRewardBlock : lastRewardBlock,
                accRewardPerShare : 0,
                depositFee : _depositFee
            })
        );
    }

    // Update the given pool's reward token allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint256 _depositFee,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        if (_allocPoint == 0) {
            updatePool(_pid);
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFee = _depositFee;
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }

    // Return reward over the given _from to _to block.
    function getReward(uint256 _from, uint256 _to)
    public
    view
    returns (uint256)
    {
        require(_from <= _to, "_from must <= _to");
        uint256 res = 0;
        (uint256 rangeStart, uint256 rangeEnd) = nextRewardRange(_from, _to);
        while (true) {
            // compute rewards in (rangeStart, rangeEnd]
            res = res.add(
                rangeEnd.sub(rangeStart).mul(getRewardPerBlock(rangeStart))
            );
            if (rangeEnd == _to) {
                // all sub range are computed
                return res;
            }
            require(rangeEnd < _to, "getReward: bad");
            // find next range
            (rangeStart, rangeEnd) = nextRewardRange(rangeEnd, _to);
        }
        // Never reach here!
        return res;
    }

    // Return next reward range
    // More information, see function getReward
    function nextRewardRange(uint256 _from, uint256 _to)
    public
    view
    returns (uint256, uint256)
    {
        // if _from and _to in same range, return it directly
        // otherwise, return first range
        if (_from.sub(startBlock).div(halvedPeriodInBlock) == _to.sub(startBlock).div(halvedPeriodInBlock)) {
            return (_from, _to);
        } else {
            return (_from, startBlock.add(
                halvedPeriodInBlock.mul(_from.sub(startBlock).div(halvedPeriodInBlock).add(1))));
        }
    }

    // get reward per block
    function getRewardPerBlock(uint256 blockNumber)
    public
    view
    returns (uint256)
    {
        if (blockNumber == 0) {
            blockNumber = block.number;
        }
        if (blockNumber < startBlock) {
            return 0;
        }
        uint256 rangeNumber = blockNumber.sub(startBlock).div(halvedPeriodInBlock);
        uint256 rangeFactor = 2 ** rangeNumber;
        if (rangeFactor == 0) { // if rangeNumber is too big, rangeFactor may overflow to 0
            return 0;
        } else {
            return baseReward.div(rangeFactor);
        }
    }

    function pendingReward(uint256 _pid, address _user)
    external
    view
    returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 reward = getReward(pool.lastRewardBlock, block.number);
            uint256 rewardForPool = 0;
            if (pool.allocPoint > 0) {
                rewardForPool = reward.mul(pool.allocPoint).div(totalAllocPoint);
            }

            if (tokenMinted.add(rewardForPool) >= maxTokenMint) {
                rewardForPool = maxTokenMint.sub(tokenMinted);
            }

            uint256 rewardForUsers = rewardForPool.sub(rewardForPool.div(10));
            // reserve 10% for dev team
            accRewardPerShare = accRewardPerShare.add(
                rewardForUsers.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        if (pool.allocPoint == 0) {
            return;
        }
        uint256 reward = getReward(pool.lastRewardBlock, block.number);
        uint256 rewardForPool = reward.mul(pool.allocPoint).div(totalAllocPoint);

        if (tokenMinted.add(rewardForPool) >= maxTokenMint) {
            rewardForPool = maxTokenMint.sub(tokenMinted);
        }
        tokenMinted = tokenMinted.add(rewardForPool);

        // dev1, dev2
        // 6%,   4%
        uint256 forAllDevs = rewardForPool.div(10);
        // forAllDevs: 10%
        uint256 forDev2 = forAllDevs.mul(4).div(10);
        // 4/10
        uint256 forDev1 = forAllDevs.sub(forDev2);
        rewardToken.mint(address(devAddr1), forDev1);
        rewardToken.mint(address(devAddr2), forDev2);

        uint256 rewardForUsers = rewardForPool.sub(forAllDevs);
        rewardToken.mint(address(this), rewardForUsers);
        pool.accRewardPerShare = pool.accRewardPerShare.add(
            rewardForUsers.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        require(_amount > 0, "deposit: _amount must > 0");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];
        require(pool.allocPoint > 0, "deposit: failed because pool alloc point is zero");
        // transfer fee to feeAddr
        uint256 fee = _amount.mul(pool.depositFee).div(10000);
        pool.lpToken.safeTransferFrom(
            address(_msgSender()),
            address(feeAddr),
            fee
        );
        _amount = _amount.sub(fee);

        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accRewardPerShare).div(1e12).sub(user.rewardDebt);
            safeRewardTokenTransfer(_msgSender(), pending);
        }
        pool.lpToken.safeTransferFrom(
            address(_msgSender()),
            address(this),
            _amount
        );
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
        emit Deposit(_msgSender(), _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        require(_amount > 0, "withdraw: _amount must > 0");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accRewardPerShare).div(1e12).sub(user.rewardDebt);
        safeRewardTokenTransfer(_msgSender(), pending);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
        pool.lpToken.safeTransfer(address(_msgSender()), _amount);
        emit Withdraw(_msgSender(), _pid, _amount);
    }

    function claim(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accRewardPerShare).div(1e12).sub(
            user.rewardDebt
        );
        if (pending > 0) {
            safeRewardTokenTransfer(_msgSender(), pending);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
    }

    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];
        pool.lpToken.safeTransfer(address(_msgSender()), user.amount);
        emit EmergencyWithdraw(_msgSender(), _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    function safeRewardTokenTransfer(address _to, uint256 _amount) internal {
        uint256 bal = rewardToken.balanceOf(address(this));
        if (_amount > bal) {
            rewardToken.transfer(_to, bal);
        } else {
            rewardToken.transfer(_to, _amount);
        }
    }

    function dev1(address _devAddr1) public {
        require(_msgSender() == devAddr1, "dev1: wut?");
        devAddr1 = _devAddr1;
    }

    function dev2(address _devAddr2) public {
        require(_msgSender() == devAddr2, "dev2: wut?");
        devAddr2 = _devAddr2;
    }
}
