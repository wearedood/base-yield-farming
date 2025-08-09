// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title BaseYieldFarm
 * @dev Advanced yield farming contract for Base blockchain with multi-token rewards
 * Features: Boost mechanics, time-locked rewards, emergency controls
 */
contract BaseYieldFarm is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 boostMultiplier;
        uint256 lastDepositTime;
        uint256 lockEndTime;
    }

    struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accRewardPerShare;
        uint256 totalStaked;
        uint256 minLockPeriod;
        bool isActive;
    }

    IERC20 public rewardToken;
    uint256 public rewardPerBlock;
    uint256 public startBlock;
    uint256 public bonusEndBlock;
    uint256 public constant BONUS_MULTIPLIER = 2;
    uint256 public totalAllocPoint = 0;
    uint256 public maxBoostMultiplier = 300; // 3x max boost

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(address => uint256) public userBoostPoints;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardClaimed(address indexed user, uint256 indexed pid, uint256 amount);
    event BoostActivated(address indexed user, uint256 multiplier);

    constructor(
        IERC20 _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) {
        rewardToken = _rewardToken;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        uint256 _minLockPeriod,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint += _allocPoint;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accRewardPerShare: 0,
                totalStaked: 0,
                minLockPeriod: _minLockPeriod,
                isActive: true
            })
        );
    }

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return (_to - _from) * BONUS_MULTIPLIER;
        } else if (_from >= bonusEndBlock) {
            return _to - _from;
        } else {
            return (bonusEndBlock - _from) * BONUS_MULTIPLIER + (_to - bonusEndBlock);
        }
    }

    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = pool.totalStaked;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 reward = (multiplier * rewardPerBlock * pool.allocPoint) / totalAllocPoint;
            accRewardPerShare += (reward * 1e12) / lpSupply;
        }
        uint256 pending = ((user.amount * accRewardPerShare) / 1e12) - user.rewardDebt;
        return (pending * user.boostMultiplier) / 100;
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
        uint256 lpSupply = pool.totalStaked;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 reward = (multiplier * rewardPerBlock * pool.allocPoint) / totalAllocPoint;
        pool.accRewardPerShare += (reward * 1e12) / lpSupply;
        pool.lastRewardBlock = block.number;
    }

    function deposit(uint256 _pid, uint256 _amount, uint256 _lockPeriod) public nonReentrant whenNotPaused {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(pool.isActive, "Pool not active");
        require(_lockPeriod >= pool.minLockPeriod, "Lock period too short");
        
        updatePool(_pid);
        
        if (user.amount > 0) {
            uint256 pending = ((user.amount * pool.accRewardPerShare) / 1e12) - user.rewardDebt;
            if (pending > 0) {
                pending = (pending * user.boostMultiplier) / 100;
                safeRewardTransfer(msg.sender, pending);
                emit RewardClaimed(msg.sender, _pid, pending);
            }
        }
        
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount += _amount;
            pool.totalStaked += _amount;
            user.lastDepositTime = block.timestamp;
            user.lockEndTime = block.timestamp + _lockPeriod;
            
            // Calculate boost multiplier based on lock period
            uint256 boostMultiplier = calculateBoostMultiplier(_lockPeriod, userBoostPoints[msg.sender]);
            user.boostMultiplier = boostMultiplier;
            
            emit BoostActivated(msg.sender, boostMultiplier);
        }
        
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e12;
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "Insufficient balance");
        require(block.timestamp >= user.lockEndTime, "Tokens still locked");
        
        updatePool(_pid);
        
        uint256 pending = ((user.amount * pool.accRewardPerShare) / 1e12) - user.rewardDebt;
        if (pending > 0) {
            pending = (pending * user.boostMultiplier) / 100;
            safeRewardTransfer(msg.sender, pending);
            emit RewardClaimed(msg.sender, _pid, pending);
        }
        
        if (_amount > 0) {
            user.amount -= _amount;
            pool.totalStaked -= _amount;
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e12;
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function calculateBoostMultiplier(uint256 _lockPeriod, uint256 _boostPoints) internal view returns (uint256) {
        uint256 baseMultiplier = 100; // 1x
        uint256 lockBonus = (_lockPeriod * 50) / (30 days); // +0.5x per month
        uint256 pointsBonus = (_boostPoints * 100) / 1000; // +0.1x per 1000 points
        
        uint256 totalMultiplier = baseMultiplier + lockBonus + pointsBonus;
        return totalMultiplier > maxBoostMultiplier ? maxBoostMultiplier : totalMultiplier;
    }

    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.totalStaked -= amount;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    function safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 rewardBal = rewardToken.balanceOf(address(this));
        if (_amount > rewardBal) {
            rewardToken.safeTransfer(_to, rewardBal);
        } else {
            rewardToken.safeTransfer(_to, _amount);
        }
    }

    function setRewardPerBlock(uint256 _rewardPerBlock) public onlyOwner {// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title BaseYieldFarmV2
 * @dev Advanced yield farming protocol for Base blockchain with enhanced features
 * @dev Supports multiple reward tokens, dynamic APY, and sophisticated boost mechanics
 */
contract BaseYieldFarmV2 is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accRewardPerShare;
        uint256 totalStaked;
        uint256 minStakeAmount;
        uint256 lockupPeriod;
        bool active;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 pendingRewards;
        uint256 lastStakeTime;
        uint256 boostMultiplier;
        uint256 lockEndTime;
    }

    struct RewardToken {
        IERC20 token;
        uint256 rewardPerBlock;
        uint256 totalAllocated;
        uint256 totalDistributed;
        bool active;
    }

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(uint256 => RewardToken) public rewardTokens;
    mapping(address => uint256) public userTotalStaked;

    uint256 public totalAllocPoint = 0;
    uint256 public startBlock;
    uint256 public bonusEndBlock;
    uint256 public constant BONUS_MULTIPLIER = 2;
    uint256 public constant PRECISION = 1e12;
    uint256 public rewardTokenCount = 0;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 indexed pid, uint256 amount, address rewardToken);

    constructor(uint256 _startBlock, uint256 _bonusEndBlock) {
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
    }

    function addPool(uint256 _allocPoint, IERC20 _lpToken, uint256 _minStakeAmount, uint256 _lockupPeriod) external onlyOwner {
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint += _allocPoint;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accRewardPerShare: 0,
            totalStaked: 0,
            minStakeAmount: _minStakeAmount,
            lockupPeriod: _lockupPeriod,
            active: true
        }));
    }

    function addRewardToken(IERC20 _token, uint256 _rewardPerBlock) external onlyOwner {
        rewardTokens[rewardTokenCount] = RewardToken({
            token: _token,
            rewardPerBlock: _rewardPerBlock,
            totalAllocated: 0,
            totalDistributed: 0,
            active: true
        });
        rewardTokenCount++;
    }

    function deposit(uint256 _pid, uint256 _amount) external nonReentrant whenNotPaused {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(pool.active, "Pool not active");
        require(_amount >= pool.minStakeAmount, "Amount below minimum");
        
        if (user.amount > 0) {
            uint256 pending = user.amount * pool.accRewardPerShare / PRECISION - user.rewardDebt;
            if (pending > 0) {
                user.pendingRewards += pending;
            }
        }
        
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            user.amount += _amount;
            pool.totalStaked += _amount;
            user.lastStakeTime = block.timestamp;
            user.lockEndTime = block.timestamp + pool.lockupPeriod;
            userTotalStaked[msg.sender] += _amount;
        }
        
        user.rewardDebt = user.amount * pool.accRewardPerShare / PRECISION;
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "Insufficient balance");
        require(block.timestamp >= user.lockEndTime, "Tokens still locked");
        
        uint256 pending = user.amount * pool.accRewardPerShare / PRECISION - user.rewardDebt;
        if (pending > 0) {
            user.pendingRewards += pending;
        }
        
        if (_amount > 0) {
            user.amount -= _amount;
            pool.totalStaked -= _amount;
            pool.lpToken.safeTransfer(msg.sender, _amount);
            userTotalStaked[msg.sender] -= _amount;
        }
        
        user.rewardDebt = user.amount * pool.accRewardPerShare / PRECISION;
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function claimRewards(uint256 _pid) external nonReentrant {
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 totalReward = user.pendingRewards;
        
        if (totalReward > 0) {
            for (uint256 i = 0; i < rewardTokenCount; i++) {
                if (rewardTokens[i].active) {
                    uint256 tokenReward = totalReward / rewardTokenCount;
                    if (rewardTokens[i].token.balanceOf(address(this)) >= tokenReward) {
                        rewardTokens[i].token.safeTransfer(msg.sender, tokenReward);
                        rewardTokens[i].totalDistributed += tokenReward;
                        emit RewardPaid(msg.sender, _pid, tokenReward, address(rewardTokens[i].token));
                    }
                }
            }
            user.pendingRewards = 0;
        }
    }

    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_pid][_user];
        return user.pendingRewards;
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}
        massUpdatePools();
        rewardPerBlock = _rewardPerBlock;
    }

    function addBoostPoints(address _user, uint256 _points) public onlyOwner {
        userBoostPoints[_user] += _points;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setPoolStatus(uint256 _pid, bool _isActive) public onlyOwner {
        poolInfo[_pid].isActive = _isActive;
    }
}
