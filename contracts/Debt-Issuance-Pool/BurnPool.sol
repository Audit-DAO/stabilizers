// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./lib/SafeMathInt.sol";

contract BurnPool {
    using SafeERC20 for IERC20;
    using SafeMathInt for int256;
    using SafeMath for uint256;

    event LogStartNewDistributionCycle(
        uint256 poolShareAdded_,
        uint256 rewardRate_,
        uint256 periodFinish_
    );

    address public policy;
    address public burnPool1;
    address public burnPool2;

    IERC20 public debase;
    uint256 public debtBalance;
    uint256 public negativeRebaseCount;
    uint256 public blockDuration;
    uint256 public rewardRate;
    uint256 public periodFinish;
    uint256 public lastUpdateBlock;

    bool public lastRebaseWasNotNegative;

    uint256 public peakDebaseRatio = 2;

    mapping(address => mapping(uint256 => uint256)) userCouponBalances;
    uint256 public couponsIssued;
    uint256 public couponsClaimed;

    constructor(
        address debase_,
        address policy_,
        address burnPool1_,
        address burnPool2_
    ) public {
        debase = IERC20(debase_);
        burnPool1 = burnPool1_;
        burnPool2 = burnPool2_;
        policy = policy_;
    }

    function getCirculatinShare() internal view returns (uint256) {
        uint256 totalSupply = debase.totalSupply();

        uint256 circulatingSupply =
            totalSupply.sub(debase.balanceOf(burnPool1)).sub(
                debase.balanceOf(burnPool2)
            );

        return circulatingSupply.mul(10**18).div(totalSupply);
    }

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

        uint256 supplyDeltaUint = uint256(supplyDelta_.abs());
        uint256 debaseSupply = debase.totalSupply();
        uint256 circulatingShare = getCirculatinShare();

        if (supplyDelta_ < 0) {
            uint256 newSupply = debaseSupply.sub(supplyDeltaUint);

            if (lastRebaseWasNotNegative) {
                couponsIssued = 0;
            }

            lastRebaseWasNotNegative = false;
            debtBalance.add(newSupply.mul(circulatingShare).div(10**18));
        } else if (couponsIssued != 0) {
            debtBalance = 0;
            negativeRebaseCount = 0;
            lastRebaseWasNotNegative = true;

            uint256 maximumDebaseToBeRewarded =
                peakDebaseRatio.mul(couponsIssued).mul(10**18);

            startNewDistributionCycle();

            return maximumDebaseToBeRewarded;
        }

        return 0;
    }

    function buyDebt(uint256 debtAmountToBuy) external {}

    function sellCoupons(uint256 couponsAmountToSell) external {}

      function emergencyWithdraw() external onlyOwner {
        debase.safeTransfer(policy, debase.balanceOf(address(this)));
        emit LogEmergencyWithdraw(block.number);
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
      

    function startNewDistributionCycle() internal {
        if (block.number >= periodFinish) {
            rewardRate = couponsIssued.div(blockDuration);
        }
        lastUpdateBlock = block.number;
        periodFinish = block.number.add(blockDuration);

        emit LogStartNewDistributionCycle(
            poolTotalShare,
            rewardRate,
            periodFinish
        );
    }
}
