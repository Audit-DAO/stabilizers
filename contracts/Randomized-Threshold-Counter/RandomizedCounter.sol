// SPDX-License-Identifier: MIT
/*
   ____            __   __        __   _
  / __/__ __ ___  / /_ / /  ___  / /_ (_)__ __
 _\ \ / // // _ \/ __// _ \/ -_)/ __// / \ \ /
/___/ \_, //_//_/\__//_//_/\__/ \__//_/ /_\_\
     /___/

* Synthetix: YAMRewards.sol
*
* Docs: https://docs.synthetix.io/
*
*
* MIT License
* ===========
*
* Copyright (c) 2020 Synthetix
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
*/

pragma solidity >=0.6.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./RandomNumberConsumer.sol";

contract LPTokenWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public y;

    function setStakeToken(address _y) internal {
        y = IERC20(_y);
    }

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        y.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        y.safeTransfer(msg.sender, amount);
    }
}

contract RandomizedCounter is Ownable, Initializable, LPTokenWrapper {
    using Address for address;

    event LogEmergencyWithdraw(uint256 timestamp);
    event LogSetCountThreshold(uint256 countThreshold_);
    event LogSetBeforePeriodFinish(bool beforePeriodFinish_);
    event LogSetCountInSequence(bool countInSequence_);
    event LogSetRewardPercentage(uint256 rewardPercentage_);
    event LogSetRevokeReward(bool revokeReward_);
    event LogSetRevokeRewardPrecentage(uint256 revokeRewardPrecentage_);
    event LogSetNormalDistribution(
        uint256 noramlDistributionMean_,
        uint256 normalDistributionDeviation_,
        uint256[100] normalDistribution_
    );
    event LogSetRandomNumberConsumer(
        RandomNumberConsumer randomNumberConsumer_
    );
    event LogSetBlockDurationReward(uint256 blockdurationReward_);
    event LogStartNewDistribtionCycle(
        uint256 poolShareAdded_,
        uint256 rewardRate_,
        uint256 periodFinish_,
        uint256 count_,
        uint256 randomThreshold_
    );
    event LogRandomThresold(uint256 randomNumber);
    event LogSetPoolEnabled(bool poolEnabled_);
    event LogSetEnableUserLpLimit(bool enableUserLpLimit_);
    event LogSetEnablePoolLpLimit(bool enablePoolLpLimit_);
    event LogSetUserLpLimit(uint256 userLpLimit_);
    event LogSetPoolLpLimit(uint256 poolLpLimit_);
    event LogRewardsClaimed(uint256 rewardAmount_);
    event LogRewardAdded(uint256 reward);
    event LogRewardRevoked(uint256 precentageRevoked, uint256 amountRevoked);
    event LogStaked(address indexed user, uint256 amount);
    event LogWithdrawn(address indexed user, uint256 amount);
    event LogRewardPaid(address indexed user, uint256 reward);
    event LogManualPoolStarted(uint256 startedAt);

    IERC20 public debase;
    address public policy;
    bool public poolEnabled;

    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public lastUpdateBlock;
    uint256 public rewardPerTokenStored;
    uint256 public rewardPercentage;
    uint256 public rewardDistributed;

    uint256 public blockDurationReward;

    //Flag to enable amount of lp that can be staked by a account
    bool public enableUserLpLimit;
    //Amount of lp that can be staked by a account
    uint256 public userLpLimit;

    //Flag to enable total amount of lp that can be staked by all users
    bool public enablePoolLpLimit;
    //Total amount of lp tat can be staked
    uint256 public poolLpLimit;

    // Revokes reward in relation to the percentage
    uint256 public revokeRewardPrecentage;

    // Should revoke reward
    bool public revokeReward;

    uint256 public lastRewardClaimed;

    uint256 public revokeRewardDuration;

    // The count of s hitting their target
    uint256 public count;

    // Flag to enable or disable   sequence checker
    bool public countInSequence;

    // Address for the random number contract (chainlink vrf)
    RandomNumberConsumer public randomNumberConsumer;

    //Address of the link token
    IERC20 public link;

    // Flag to send reward before stabilizer pool period time finished
    bool public beforePeriodFinish;

    // The mean for the normal distribution added
    uint256 public noramlDistributionMean;

    // The deviation for te normal distribution added
    uint256 public normalDistributionDeviation;

    // The array of normal distribution value data
    uint256[100] public normalDistribution;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    modifier enabled() {
        require(poolEnabled, "Pool isn't enabled");
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateBlock = lastBlockRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /**
     * @notice Function to set how much reward the stabilizer will request
     */
    function setRewardPercentage(uint256 rewardPercentage_) external onlyOwner {
        rewardPercentage = rewardPercentage_;
        emit LogSetRewardPercentage(rewardPercentage);
    }

    /**
     * @notice Function to enable or disable count should be in sequence
     */
    function setCountInSequence(bool countInSequence_) external onlyOwner {
        countInSequence = countInSequence_;
        count = 0;
        emit LogSetCountInSequence(!countInSequence);
    }

    /**
     * @notice Function to enable or disable reward revoking
     */
    function setRevokeReward(bool revokeReward_) external onlyOwner {
        revokeReward = revokeReward_;
        emit LogSetRevokeReward(revokeReward);
    }

    /**
     * @notice Function to set how much of the reward duration should be revoked
     */
    function setRevokeRewardPercentage(uint256 revokeRewardPrecentage_)
        external
        onlyOwner
    {
        revokeRewardPrecentage = revokeRewardPrecentage_;
        emit LogSetRevokeRewardPrecentage(revokeRewardPrecentage_);
    }

    /**
     * @notice Function to allow reward distribution before previous rewards have been distributed
     */
    function setBeforePeriodFinish(bool beforePeriodFinish_)
        external
        onlyOwner
    {
        beforePeriodFinish = beforePeriodFinish_;
        emit LogSetBeforePeriodFinish(beforePeriodFinish);
    }

    /**
     * @notice Function to set reward drop period
     */
    function setBlockDurationReward(uint256 blockDurationReward_)
        external
        onlyOwner
    {
        require(blockDurationReward >= 1);
        blockDurationReward = blockDurationReward_;
        emit LogSetBlockDurationReward(blockDurationReward);
    }

    /**
     * @notice Function enabled or disable pool staking,withdraw
     */
    function setPoolEnabled(bool poolEnabled_) external onlyOwner {
        poolEnabled = poolEnabled_;
        count = 0;
        emit LogSetPoolEnabled(poolEnabled);
    }

    /**
     * @notice Function to enable user lp limit
     */
    function setEnableUserLpLimit(bool enableUserLpLimit_) external onlyOwner {
        enableUserLpLimit = enableUserLpLimit_;
        emit LogSetEnableUserLpLimit(enableUserLpLimit);
    }

    /**
     * @notice Function to set user lp limit
     */
    function setUserLpLimit(uint256 userLpLimit_) external onlyOwner {
        require(
            userLpLimit_ <= poolLpLimit,
            "User lp limit can't be more than pool limit"
        );
        userLpLimit = userLpLimit_;
        emit LogSetUserLpLimit(userLpLimit);
    }

    /**
     * @notice Function to enable pool lp limit
     */
    function setEnablePoolLpLimit(bool enablePoolLpLimit_) external onlyOwner {
        enablePoolLpLimit = enablePoolLpLimit_;
        emit LogSetEnablePoolLpLimit(enablePoolLpLimit);
    }

    /**
     * @notice Function to set pool lp limit
     */
    function setPoolLpLimit(uint256 poolLpLimit_) external onlyOwner {
        require(
            poolLpLimit_ >= userLpLimit,
            "Pool lp limit can't be less than user lp limit"
        );
        poolLpLimit = poolLpLimit_;
        emit LogSetPoolLpLimit(poolLpLimit);
    }

    /**
     * @notice Function to set address of the random number consumer (chain link vrf)
     */
    function setRandomNumberConsumer(RandomNumberConsumer randomNumberConsumer_)
        external
        onlyOwner
    {
        randomNumberConsumer = RandomNumberConsumer(randomNumberConsumer_);
        emit LogSetRandomNumberConsumer(randomNumberConsumer);
    }

    /**
     * @notice Function to set the normal distribution array and its associated mean/deviation
     */
    function setNormalDistribution(
        uint256 normalDistributionMean_,
        uint256 normalDistributionDeviation_,
        uint256[100] calldata normalDistribution_
    ) external onlyOwner {
        noramlDistributionMean = normalDistributionMean_;
        normalDistributionDeviation = normalDistributionDeviation_;
        normalDistribution = normalDistribution_;
        emit LogSetNormalDistribution(
            noramlDistributionMean,
            normalDistributionDeviation,
            normalDistribution
        );
    }

    function initialize(
        address debase_,
        address pairToken_,
        address policy_,
        address randomNumberConsumer_,
        address link_,
        uint256 rewardPercentage_,
        uint256 blockDurationReward_,
        uint256 userLpLimit_,
        uint256 poolLpLimit_,
        uint256 revokeRewardPrecentage_,
        uint256 normalDistributionMean_,
        uint256 normalDistributionDeviation_,
        uint256[100] memory normalDistribution_
    ) public initializer {
        setStakeToken(pairToken_);
        debase = IERC20(debase_);
        link = IERC20(link_);
        randomNumberConsumer = RandomNumberConsumer(randomNumberConsumer_);
        policy = policy_;
        count = 0;

        blockDurationReward = blockDurationReward_;
        userLpLimit = userLpLimit_;
        poolLpLimit = poolLpLimit_;
        rewardPercentage = rewardPercentage_;
        revokeRewardPrecentage = revokeRewardPrecentage_;
        countInSequence = true;
        normalDistribution = normalDistribution_;
        noramlDistributionMean = normalDistributionMean_;
        normalDistributionDeviation = normalDistributionDeviation_;
    }

    /**
     * @notice When a rebase happens this function is called by the rebase function. If the supplyDelta is positive (supply increase) a random
     * will be constructed using Chainlink VRF. The mod of the random number is taken to get a number between 0-100. This result
     * is used as a index to get a number from the normal distribution array. The number returned will be compared against the current count of
     * positive rebases and if the count is equal to or greater that the number obtained from array, then the pool will request rewards from the stabilizer pool.
     */
    function checkStabilizerAndGetReward(
        int256 supplyDelta_,
        int256 rebaseLag_,
        uint256 exchangeRate_,
        uint256 debasePolicyBalance
    ) external returns (uint256 rewardAmount_) {
        require(
            msg.sender == policy,
            "Only debase policy contract can call this"
        );

        if (supplyDelta_ > 0) {
            count = count.add(1);

            // Call random number fetcher only if the random number consumer has link in its balance to do so. Otherwise return 0
            if (
                link.balanceOf(address(randomNumberConsumer)) >=
                randomNumberConsumer.fee() &&
                (beforePeriodFinish || block.timestamp >= periodFinish)
            ) {
                uint256 rewardToClaim =
                    debasePolicyBalance.mul(rewardPercentage).div(10**18);

                if (debasePolicyBalance >= rewardToClaim) {
                    lastRewardClaimed = rewardToClaim;
                    randomNumberConsumer.getRandomNumber(block.timestamp);

                    emit LogRewardsClaimed(rewardToClaim);
                    return rewardToClaim;
                }
            }
        } else if (countInSequence) {
            count = 0;

            if (revokeReward && block.timestamp < periodFinish) {
                uint256 timeRemaining = periodFinish.sub(block.timestamp);
                // Rewards will only be revoked from period after the current period so unclaimed rewards arent taken away.
                if (timeRemaining >= revokeRewardDuration) {
                    //Set reward distribution period back
                    periodFinish = periodFinish.sub(revokeRewardDuration);
                    //Calculate reward to rewark by amount the reward moved back
                    uint256 rewardToRevoke =
                        rewardRate.mul(revokeRewardDuration);
                    lastUpdateBlock = block.timestamp;

                    debase.safeTransfer(policy, rewardToRevoke);
                    emit LogRewardRevoked(revokeRewardDuration, rewardToRevoke);
                }
            }
        }
        return 0;
    }

    function claimer(uint256 randomNumber) external {
        require(
            msg.sender == address(randomNumberConsumer),
            "Only debase policy contract can call this"
        );

        uint256 randomThreshold = normalDistribution[randomNumber.mod(100)];
        emit LogRandomThresold(randomThreshold);

        if (count >= randomThreshold) {
            startNewDistribtionCycle(randomThreshold);
            count = 0;
        } else {
            debase.safeTransfer(policy, lastRewardClaimed);
        }
        lastRewardClaimed = 0;
    }

    /**
     * @notice Function allows for emergency withdrawal of all reward tokens back into stabilizer fund
     */
    function emergencyWithdraw() external onlyOwner {
        debase.safeTransfer(policy, debase.balanceOf(address(this)));
        emit LogEmergencyWithdraw(block.timestamp);
    }

    function lastBlockRewardApplicable() internal view returns (uint256) {
        return Math.min(block.number, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastBlockRewardApplicable()
                    .sub(lastUpdateBlock)
                    .mul(rewardRate)
                    .mul(10**18)
                    .div(totalSupply())
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(10**18)
                .add(rewards[account]);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 amount)
        public
        override
        updateReward(msg.sender)
        enabled
    {
        require(
            !address(msg.sender).isContract(),
            "Caller must not be a contract"
        );
        require(amount > 0, "Cannot stake 0");

        if (enablePoolLpLimit) {
            uint256 lpBalance = totalSupply();
            require(
                amount.add(lpBalance) <= poolLpLimit,
                "Can't stake pool lp limit reached"
            );
        }
        if (enableUserLpLimit) {
            uint256 userLpBalance = balanceOf(msg.sender);
            require(
                userLpBalance.add(amount) <= userLpLimit,
                "Can't stake more than lp limit"
            );
        }

        super.stake(amount);
        emit LogStaked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public override updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        super.withdraw(amount);
        emit LogWithdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    function getReward() public updateReward(msg.sender) enabled {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;

            uint256 rewardToClaim =
                debase.totalSupply().mul(reward).div(10**18);

            debase.safeTransfer(msg.sender, rewardToClaim);

            emit LogRewardPaid(msg.sender, rewardToClaim);
            rewardDistributed = rewardDistributed.add(reward);
        }
    }

    function startNewDistribtionCycle(uint256 randomThreshold)
        internal
        updateReward(address(0))
    {
        uint256 newPoolTotalShare =
            lastRewardClaimed.div(debase.totalSupply()).mul(10**18);

        if (block.timestamp >= periodFinish) {
            rewardRate = newPoolTotalShare.div(blockDurationReward);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = newPoolTotalShare.add(leftover).div(
                blockDurationReward
            );
        }
        lastUpdateBlock = block.timestamp;
        periodFinish = block.timestamp.add(blockDurationReward);

        emit LogStartNewDistribtionCycle(
            newPoolTotalShare,
            rewardRate,
            periodFinish,
            count,
            randomThreshold
        );
    }
}
