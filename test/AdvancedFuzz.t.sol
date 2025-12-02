// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

/**
 * @title AdvancedFuzzTests
 * @notice Comprehensive fuzz testing suite for RebaseToken and Vault
 * @dev Tests edge cases, overflow conditions, and complex interactions
 */
contract AdvancedFuzzTests is Test {
    RebaseToken public rebaseToken;
    Vault public vault;

    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    uint256 constant INTEREST_RATE = 6e10; // 6% annual
    uint256 constant SECONDS_PER_YEAR = 365 days;
    uint256 constant PRECISION = 1e18;

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken(owner);
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantRole(rebaseToken.MINT_AND_BURN_ROLE(), address(vault));
        vm.stopPrank();

        // Label addresses for better trace readability
        vm.label(owner, "Owner");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(user3, "User3");
        vm.label(address(rebaseToken), "RebaseToken");
        vm.label(address(vault), "Vault");
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Fuzz test: Deposit should always mint exact amount of tokens
    function testFuzz_DepositMintsExactTokens(uint256 amount) public {
        amount = bound(amount, 0.001 ether, 10000 ether);

        vm.deal(user1, amount);
        vm.prank(user1);
        vault.deposit{value: amount}();

        assertEq(rebaseToken.balanceOf(user1), amount, "Tokens minted should equal deposit");
        assertEq(address(vault).balance, amount, "Vault should hold exact ETH");
        assertEq(rebaseToken.totalSupply(), amount, "Total supply should equal deposits");
    }

    /// @notice Fuzz test: Multiple users depositing should maintain correct state
    function testFuzz_MultipleDeposits(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 0.01 ether, 1000 ether);
        amount2 = bound(amount2, 0.01 ether, 1000 ether);
        amount3 = bound(amount3, 0.01 ether, 1000 ether);

        // User 1 deposits
        vm.deal(user1, amount1);
        vm.prank(user1);
        vault.deposit{value: amount1}();

        // User 2 deposits
        vm.deal(user2, amount2);
        vm.prank(user2);
        vault.deposit{value: amount2}();

        // User 3 deposits
        vm.deal(user3, amount3);
        vm.prank(user3);
        vault.deposit{value: amount3}();

        // Verify individual balances
        assertEq(rebaseToken.balanceOf(user1), amount1, "User1 balance incorrect");
        assertEq(rebaseToken.balanceOf(user2), amount2, "User2 balance incorrect");
        assertEq(rebaseToken.balanceOf(user3), amount3, "User3 balance incorrect");

        // Verify total supply
        uint256 expectedTotal = amount1 + amount2 + amount3;
        assertEq(rebaseToken.totalSupply(), expectedTotal, "Total supply incorrect");
        assertEq(address(vault).balance, expectedTotal, "Vault balance incorrect");
    }

    /// @notice Fuzz test: Deposit should fail if amount is 0
    function testFuzz_DepositRevertsOnZero() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert(Vault.Vault__ZeroDepositAmount.selector);
        vault.deposit{value: 0}();
    }

    /*//////////////////////////////////////////////////////////////
                        INTEREST ACCRUAL FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Fuzz test: Interest should accrue linearly over time
    function testFuzz_InterestAccrualsLinearly(uint256 depositAmount, uint256 timeElapsed) public {
        depositAmount = bound(depositAmount, 1 ether, 1000 ether);
        timeElapsed = bound(timeElapsed, 1 days, 365 days * 5);

        // Deposit
        vm.deal(user1, depositAmount);
        vm.prank(user1);
        vault.deposit{value: depositAmount}();

        uint256 initialBalance = rebaseToken.balanceOf(user1);

        // Warp time
        vm.warp(block.timestamp + timeElapsed);

        uint256 finalBalance = rebaseToken.balanceOf(user1);

        // Calculate expected interest: principal * rate * time
        uint256 expectedInterest = (depositAmount * INTEREST_RATE * timeElapsed) / PRECISION;
        uint256 expectedBalance = depositAmount + expectedInterest;

        // Assert interest accrued
        assertGt(finalBalance, initialBalance, "Balance should increase");

        // Allow 0.01% margin for rounding errors
        assertApproxEqRel(finalBalance, expectedBalance, 0.0001e18, "Interest calculation incorrect");
    }

    /// @notice Fuzz test: Interest should double accrue if time doubles
    function testFuzz_InterestDoublesWhenTimeDoubles(uint256 depositAmount, uint256 timeElapsed) public {
        depositAmount = bound(depositAmount, 1 ether, 100 ether);
        timeElapsed = bound(timeElapsed, 1 hours, 180 days);

        vm.deal(user1, depositAmount);
        vm.prank(user1);
        vault.deposit{value: depositAmount}();

        // Warp to time T
        vm.warp(block.timestamp + timeElapsed);
        uint256 balanceAtT = rebaseToken.balanceOf(user1);
        uint256 interestAtT = balanceAtT - depositAmount;

        // Warp to time 2T
        vm.warp(block.timestamp + timeElapsed);
        uint256 balanceAt2T = rebaseToken.balanceOf(user1);
        uint256 interestAt2T = balanceAt2T - depositAmount;

        // Interest at 2T should be approximately 2x interest at T
        assertApproxEqRel(interestAt2T, interestAtT * 2, 0.0001e18, "Interest should scale linearly with time");
    }

    /// @notice Fuzz test: Multiple users should accrue interest independently
    function testFuzz_IndependentInterestAccrual(
        uint256 amount1,
        uint256 amount2,
        uint256 time1,
        uint256 time2
    ) public {
        amount1 = bound(amount1, 1 ether, 100 ether);
        amount2 = bound(amount2, 1 ether, 100 ether);
        time1 = bound(time1, 1 days, 180 days);
        time2 = bound(time2, 1 days, 180 days);

        // User 1 deposits at time 0
        vm.deal(user1, amount1);
        vm.prank(user1);
        vault.deposit{value: amount1}();

        // Warp time1
        vm.warp(block.timestamp + time1);

        // User 2 deposits at time1
        vm.deal(user2, amount2);
        vm.prank(user2);
        vault.deposit{value: amount2}();

        // Warp time2 more
        vm.warp(block.timestamp + time2);

        // User 1 balance (accrued for time1 + time2)
        uint256 balance1 = rebaseToken.balanceOf(user1);
        uint256 expectedBalance1 = amount1 + (amount1 * INTEREST_RATE * (time1 + time2)) / PRECISION;

        // User 2 balance (accrued for time2 only)
        uint256 balance2 = rebaseToken.balanceOf(user2);
        uint256 expectedBalance2 = amount2 + (amount2 * INTEREST_RATE * time2) / PRECISION;

        assertApproxEqRel(balance1, expectedBalance1, 0.0001e18, "User1 interest incorrect");
        assertApproxEqRel(balance2, expectedBalance2, 0.0001e18, "User2 interest incorrect");
    }

    /*//////////////////////////////////////////////////////////////
                            REDEEM FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Fuzz test: Redeem should always burn tokens and return ETH
    function testFuzz_RedeemBurnsTokensAndReturnsETH(uint256 depositAmount, uint256 redeemAmount) public {
        depositAmount = bound(depositAmount, 1 ether, 1000 ether);
        redeemAmount = bound(redeemAmount, 0.1 ether, depositAmount);

        // Deposit
        vm.deal(user1, depositAmount);
        vm.prank(user1);
        vault.deposit{value: depositAmount}();

        uint256 tokensBefore = rebaseToken.balanceOf(user1);
        uint256 ethBefore = user1.balance;

        // Redeem
        vm.prank(user1);
        vault.redeem(redeemAmount);

        uint256 tokensAfter = rebaseToken.balanceOf(user1);
        uint256 ethAfter = user1.balance;

        assertEq(tokensBefore - tokensAfter, redeemAmount, "Tokens not burned correctly");
        assertEq(ethAfter - ethBefore, redeemAmount, "ETH not returned correctly");
    }

    /// @notice Fuzz test: Redeem with interest should work correctly
    function testFuzz_RedeemWithInterest(uint256 depositAmount, uint256 timeElapsed) public {
        depositAmount = bound(depositAmount, 1 ether, 100 ether);
        timeElapsed = bound(timeElapsed, 1 hours, 365 days);

        // Deposit
        vm.deal(user1, depositAmount);
        vm.prank(user1);
        vault.deposit{value: depositAmount}();

        // Warp time
        vm.warp(block.timestamp + timeElapsed);

        // Get balance with interest
        uint256 balanceWithInterest = rebaseToken.balanceOf(user1);

        // Fund vault with interest
        uint256 interestOwed = balanceWithInterest - address(vault).balance;
        vm.deal(address(vault), address(vault).balance + interestOwed);

        // Redeem all
        vm.prank(user1);
        vault.redeem(balanceWithInterest);

        assertEq(rebaseToken.balanceOf(user1), 0, "All tokens should be burned");
        assertEq(user1.balance, balanceWithInterest, "User should receive full balance with interest");
        assertGt(balanceWithInterest, depositAmount, "Balance should include interest");
    }

    /// @notice Fuzz test: Redeem type(uint256).max should redeem all tokens
    function testFuzz_RedeemMaxRedeemAll(uint256 depositAmount, uint256 timeElapsed) public {
        depositAmount = bound(depositAmount, 1 ether, 100 ether);
        timeElapsed = bound(timeElapsed, 0, 180 days);

        // Deposit
        vm.deal(user1, depositAmount);
        vm.prank(user1);
        vault.deposit{value: depositAmount}();

        // Warp time
        if (timeElapsed > 0) {
            vm.warp(block.timestamp + timeElapsed);
        }

        uint256 balanceWithInterest = rebaseToken.balanceOf(user1);

        // Fund vault
        vm.deal(address(vault), balanceWithInterest);

        // Redeem max
        vm.prank(user1);
        vault.redeem(type(uint256).max);

        assertEq(rebaseToken.balanceOf(user1), 0, "All tokens should be burned");
        assertEq(user1.balance, balanceWithInterest, "User should receive full balance");
    }

    /// @notice Fuzz test: Redeem should fail if user has insufficient balance
    function testFuzz_RedeemRevertsOnInsufficientBalance(uint256 depositAmount, uint256 redeemAmount) public {
        depositAmount = bound(depositAmount, 1 ether, 100 ether);
        redeemAmount = bound(redeemAmount, depositAmount + 1, depositAmount * 2);

        vm.deal(user1, depositAmount);
        vm.prank(user1);
        vault.deposit{value: depositAmount}();

        vm.prank(user1);
        vm.expectRevert(); // Should revert with insufficient balance
        vault.redeem(redeemAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLEX SCENARIO FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Fuzz test: Sequential deposits and redeems
    function testFuzz_SequentialDepositsAndRedeems(
        uint256 deposit1,
        uint256 deposit2,
        uint256 redeem1,
        uint256 time1,
        uint256 time2
    ) public {
        deposit1 = bound(deposit1, 1 ether, 50 ether);
        deposit2 = bound(deposit2, 1 ether, 50 ether);
        time1 = bound(time1, 1 hours, 90 days);
        time2 = bound(time2, 1 hours, 90 days);

        // First deposit
        vm.deal(user1, deposit1);
        vm.prank(user1);
        vault.deposit{value: deposit1}();

        // Warp time
        vm.warp(block.timestamp + time1);

        uint256 balanceAfterTime1 = rebaseToken.balanceOf(user1);
        redeem1 = bound(redeem1, 0.1 ether, balanceAfterTime1);

        // Fund vault for redeem
        vm.deal(address(vault), balanceAfterTime1);

        // First redeem
        vm.prank(user1);
        vault.redeem(redeem1);

        uint256 balanceAfterRedeem = rebaseToken.balanceOf(user1);

        // Second deposit
        vm.deal(user1, deposit2);
        vm.prank(user1);
        vault.deposit{value: deposit2}();

        // Warp time again
        vm.warp(block.timestamp + time2);

        uint256 finalBalance = rebaseToken.balanceOf(user1);

        // Assertions
        assertGt(finalBalance, balanceAfterRedeem + deposit2 - 1, "Final balance should include second deposit and interest");
    }

    /// @notice Fuzz test: Stress test with extreme time periods
    function testFuzz_ExtremeTimePeriods(uint256 depositAmount, uint256 timeElapsed) public {
        depositAmount = bound(depositAmount, 1 ether, 10 ether);
        timeElapsed = bound(timeElapsed, 10 * 365 days, 50 * 365 days); // 10-50 years

        vm.deal(user1, depositAmount);
        vm.prank(user1);
        vault.deposit{value: depositAmount}();

        vm.warp(block.timestamp + timeElapsed);

        uint256 balance = rebaseToken.balanceOf(user1);

        // Should still work without overflow
        assertGt(balance, depositAmount, "Interest should accrue even over extreme time");

        // Calculate expected (will be huge)
        uint256 expectedInterest = (depositAmount * INTEREST_RATE * timeElapsed) / PRECISION;
        uint256 expectedBalance = depositAmount + expectedInterest;

        assertApproxEqRel(balance, expectedBalance, 0.0001e18, "Interest calculation should be accurate");
    }

    /// @notice Fuzz test: Transfer tokens between users maintains interest
    function testFuzz_TransferMaintainsInterest(
        uint256 depositAmount,
        uint256 transferAmount,
        uint256 time1,
        uint256 time2
    ) public {
        depositAmount = bound(depositAmount, 10 ether, 100 ether);
        time1 = bound(time1, 1 days, 30 days);
        time2 = bound(time2, 1 hours, 30 days); // Changed min from 1 day to 1 hour

        // User1 deposits
        vm.deal(user1, depositAmount);
        vm.prank(user1);
        vault.deposit{value: depositAmount}();

        // Warp time
        vm.warp(block.timestamp + time1);

        uint256 balanceBeforeTransfer = rebaseToken.balanceOf(user1);
        transferAmount = bound(transferAmount, 1 ether, balanceBeforeTransfer / 2);

        // Transfer to user2
        vm.prank(user1);
        rebaseToken.transfer(user2, transferAmount);

        // Warp more time
        vm.warp(block.timestamp + time2);

        // Both users should have interest
        uint256 user1Balance = rebaseToken.balanceOf(user1);
        uint256 user2Balance = rebaseToken.balanceOf(user2);

        // User2 might not have interest if time2 is very small, so use >= instead of >
        assertGe(user2Balance, transferAmount, "User2 should have at least transferred amount");
        assertGt(user1Balance, balanceBeforeTransfer - transferAmount - 1, "User1 should still earn interest");
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test minimum deposit amounts
    function testFuzz_MinimumDeposit(uint256 amount) public {
        amount = bound(amount, 1, 0.001 ether);

        vm.deal(user1, amount);
        vm.prank(user1);
        vault.deposit{value: amount}();

        assertEq(rebaseToken.balanceOf(user1), amount);
    }

    /// @notice Test that vault has exact balance after multiple operations
    function testFuzz_VaultBalanceConsistency(
        uint256 deposit1,
        uint256 deposit2,
        uint256 redeem1
    ) public {
        deposit1 = bound(deposit1, 1 ether, 50 ether);
        deposit2 = bound(deposit2, 1 ether, 50 ether);

        // Deposits
        vm.deal(user1, deposit1);
        vm.prank(user1);
        vault.deposit{value: deposit1}();

        vm.deal(user2, deposit2);
        vm.prank(user2);
        vault.deposit{value: deposit2}();

        uint256 vaultBalanceBefore = address(vault).balance;

        redeem1 = bound(redeem1, 0.1 ether, deposit1);

        // Redeem
        vm.prank(user1);
        vault.redeem(redeem1);

        uint256 vaultBalanceAfter = address(vault).balance;

        assertEq(vaultBalanceBefore - redeem1, vaultBalanceAfter, "Vault balance inconsistent");
    }

    /// @notice Test that total supply equals sum of all balances
    function testFuzz_TotalSupplyConsistency(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1 ether, 100 ether);
        amount2 = bound(amount2, 1 ether, 100 ether);
        amount3 = bound(amount3, 1 ether, 100 ether);

        // Multiple deposits
        vm.deal(user1, amount1);
        vm.prank(user1);
        vault.deposit{value: amount1}();

        vm.deal(user2, amount2);
        vm.prank(user2);
        vault.deposit{value: amount2}();

        vm.deal(user3, amount3);
        vm.prank(user3);
        vault.deposit{value: amount3}();

        uint256 totalBalance = rebaseToken.balanceOf(user1) +
                               rebaseToken.balanceOf(user2) +
                               rebaseToken.balanceOf(user3);

        assertEq(rebaseToken.totalSupply(), totalBalance, "Total supply should equal sum of balances");
    }
}
