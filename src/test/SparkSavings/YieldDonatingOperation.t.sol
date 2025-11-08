// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import {YieldDonatingSetup as Setup, ERC20, IStrategyInterface, ITokenizedStrategy} from "./YieldDonatingSetup.sol";

contract YieldDonatingOperationTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_setupStrategyOK() public {
        console2.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(ITokenizedStrategy(address(strategy)).dragonRouter(), dragonRouter);
        assertEq(strategy.keeper(), keeper);
        // Check enableBurning using low-level call since it's not in the interface
        (bool success, bytes memory data) = address(strategy).staticcall(abi.encodeWithSignature("enableBurning()"));
        require(success, "enableBurning call failed");
        bool currentEnableBurning = abi.decode(data, (bool));
        assertEq(currentEnableBurning, enableBurning);
    }

    function test_profitableReport(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        uint256 _timeInDays = 30; // Fixed 30 days

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Move forward in time to simulate yield accrual period
        uint256 timeElapsed = _timeInDays * 1 days;
        skip(timeElapsed);

        // Report profit - should detect the simulated yield
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values - should have profit equal to simulated yield
        assertGt(profit, 0, "!profit should equal expected yield");
        assertEq(loss, 0, "!loss should be 0");

        // Check that profit was minted to dragon router
        uint256 dragonRouterShares = strategy.balanceOf(dragonRouter);
        assertGt(dragonRouterShares, 0, "!dragon router shares");

        // Convert shares back to assets to verify
        uint256 dragonRouterAssets = strategy.convertToAssets(dragonRouterShares);
        assertEq(dragonRouterAssets, profit, "!dragon router assets should equal profit");

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds (user gets original amount, dragon router gets the yield)
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");

        // Assert that dragon router still has shares (the yield portion)
        uint256 dragonRouterSharesAfter = strategy.balanceOf(dragonRouter);
        assertGt(dragonRouterSharesAfter, 0, "!dragon router shares after withdrawal");
    }

    function test_tendTrigger(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        (bool trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Skip some time
        skip(30 days);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(keeper);
        strategy.report();

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);
    }

    function testFuzzDeposit(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        uint256 initialUserAssetBalance = asset.balanceOf(user);
        uint256 initialStrategyTotalAssets = strategy.totalAssets();
        uint256 initialUserStrategyBalance = strategy.balanceOf(user);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // The helper function mints the exact amount to the user and deposits it.
        // so the user's external asset balance should not change.
        assertEq(asset.balanceOf(user), initialUserAssetBalance, "User asset balance should not change");

        // The user should have received strategy shares
        assertGt(strategy.balanceOf(user), initialUserStrategyBalance, "User should have received shares");

        // The total assets of the strategy should increase by the deposited amount
        assertEq(strategy.totalAssets(), initialStrategyTotalAssets + _amount, "Strategy total assets should increase");
    }

    function testFuzzWithdraw(uint256 _depositAmount, uint256 _withdrawFraction) public {
        // Bound the deposit amount to reasonable values
        vm.assume(_depositAmount > minFuzzAmount && _depositAmount < maxFuzzAmount);
        _withdrawFraction = bound(_withdrawFraction, 1, 100); // 1% to 100%

        // Deposit first
        mintAndDepositIntoStrategy(strategy, user, _depositAmount);

        // Let some time pass for interest to accrue, making the test more realistic
        skip(1 days);

        // Calculate shares to withdraw as a fraction of user's current shares
        uint256 userShares = strategy.balanceOf(user);
        uint256 sharesToWithdraw = (userShares * _withdrawFraction) / 100;
        vm.assume(sharesToWithdraw > 0);

        // Get expected assets for the shares to be withdrawn
        uint256 expectedAssets = strategy.previewRedeem(sharesToWithdraw);

        // Balances *before* withdrawal
        uint256 userAssetBalanceBefore = asset.balanceOf(user);
        uint256 strategyTotalAssetsBefore = strategy.totalAssets();

        // Redeem the calculated shares
        vm.startPrank(user);
        uint256 assetsReceived = strategy.redeem(sharesToWithdraw, user, user);
        vm.stopPrank();

        // Verify balances after withdrawal
        assertEq(
            asset.balanceOf(user),
            userAssetBalanceBefore + assetsReceived,
            "User didn't receive correct assets"
        );

        // The assets received should be very close to the previewed amount
        assertApproxEqRel(assetsReceived, expectedAssets, 1e14, "Received assets differ from preview");

        assertEq(
            strategy.balanceOf(user),
            userShares - sharesToWithdraw,
            "Shares not burned correctly"
        );

        // Total assets should decrease by the amount of assets withdrawn
        assertApproxEqRel(
            strategy.totalAssets(),
            strategyTotalAssetsBefore - assetsReceived,
            1e14,
            "Strategy total assets should decrease correctly"
        );
    }

    function testFuzzMultipleDepositsAndWithdrawals(
        uint256 _depositAmount1,
        uint256 _depositAmount2,
        bool _shouldUser1Withdraw,
        bool _shouldUser2Withdraw
    ) public {
        vm.assume(_depositAmount1 > minFuzzAmount && _depositAmount1 < maxFuzzAmount);
        vm.assume(_depositAmount2 > minFuzzAmount && _depositAmount2 < maxFuzzAmount);

        address user2 = makeAddr("user2");

        // First user deposits
        mintAndDepositIntoStrategy(strategy, user, _depositAmount1);

        // Second user deposits
        mintAndDepositIntoStrategy(strategy, user2, _depositAmount2);

        // Verify total assets
        assertEq(
            strategy.totalAssets(),
            _depositAmount1 + _depositAmount2,
            "Total assets should equal deposits"
        );

        // Conditionally withdraw based on fuzz parameters
        if (_shouldUser1Withdraw) {
            vm.startPrank(user);
            uint256 user1Shares = strategy.balanceOf(user);
            if (user1Shares > 1) {
                strategy.redeem(user1Shares - 1, user, user);
            }
            vm.stopPrank();
        }

        if (_shouldUser2Withdraw) {
            vm.startPrank(user2);
            uint256 user2Shares = strategy.balanceOf(user2);
            if (user2Shares > 1) {
                strategy.redeem(user2Shares - 1, user2, user2);
            }
            vm.stopPrank();
        }

        // If both withdrew, strategy should be nearly empty
        if (_shouldUser1Withdraw && _shouldUser2Withdraw) {
            assertLt(
                strategy.totalAssets(),
                _depositAmount1 + _depositAmount2, // Check that assets are less than initial
                "Strategy should have fewer assets after withdrawals"
            );
        }
    }
}
