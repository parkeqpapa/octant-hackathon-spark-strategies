pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {YieldDonatingSetup as Setup, ERC20, IStrategyInterface} from "./YieldDonatingSetup.sol";
import {IPool} from "../../../src/interfaces/SparkLend/IPool.sol";
import {IAToken} from "../../../src/interfaces/SparkLend/IAToken.sol";
import {SparkLendStrategy} from "../../../src/strategies/yieldDonating/SparkLend/SparkLendStrategy.sol";

contract YieldDonatingShutdownTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_shutdownCanWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Skip some time
        skip(30 days);

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }

    function test_emergencyWithdraw_maxUint(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Skip some time
        skip(30 days);

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // should be able to pass uint 256 max and not revert.
        vm.prank(emergencyAdmin);
        strategy.emergencyWithdraw(type(uint256).max);

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }

    function testLossDoesNotTriggerTooMuchLossError() public {
        uint256 depositAmount = minFuzzAmount;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, depositAmount);
        uint256 sharesBeforeLoss = strategy.balanceOf(user);
        uint256 assetsBeforeLoss = strategy.previewRedeem(sharesBeforeLoss);

        // Simulate a 10% loss by transferring aTokens to a dead address
        SparkLendStrategy sparkLendStrategy = SparkLendStrategy(address(strategy));
        IPool sparkPool = sparkLendStrategy.pool();
        IAToken aToken = IAToken(sparkPool.getReserveData(address(asset)).aTokenAddress);
        uint256 aTokenBalanceBeforeLoss = aToken.balanceOf(address(strategy));
        uint256 aTokenLoss = aTokenBalanceBeforeLoss / 10;
        vm.prank(address(strategy));
        aToken.transfer(address(0xdead), aTokenLoss);
        vm.stopPrank();

        // Call report to update the strategy's internal totalAssets after the simulated loss
        vm.prank(keeper); // Only keeper can call report
        strategy.report();

        // Now, calculate expected assets after loss
        uint256 assetsAfterLoss = strategy.previewRedeem(sharesBeforeLoss);
        assertTrue(assetsAfterLoss < assetsBeforeLoss, "previewRedeem should reflect the loss");

        // 1. Try to withdraw the original asset amount. This should fail due to loss.
        // The 3-argument `withdraw` has maxLoss = 0 by default.
        vm.startPrank(user);
        vm.expectRevert("ERC4626: withdraw more than max");
        strategy.withdraw(assetsBeforeLoss, user, user); // Try to withdraw the amount before loss
        vm.stopPrank();

        // 2. Redeem all shares. The 3-argument `redeem` accepts any loss.
        vm.startPrank(user);
        uint256 assetsReceived = strategy.redeem(sharesBeforeLoss, user, user);
        vm.stopPrank();

        // 3. Verify that assets received are less than the original amount, due to the loss.
        assertTrue(assetsReceived < assetsBeforeLoss, "Assets received should be less than original due to loss");
        assertTrue(assetsReceived > 0, "Should still receive some assets");
        assertApproxEqRel(assetsReceived, assetsAfterLoss, 1e14, "Assets received should match preview after loss");


        // 4. Verify the strategy is now empty.
        assertLt(strategy.balanceOf(user), 2, "User should have no shares left (or dust)");
        assertLt(strategy.totalAssets(), 10, "Strategy should be nearly empty");
    }

}
