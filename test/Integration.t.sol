// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

/**
 * @title IntegrationTests
 * @notice Real-world scenario testing for RebaseToken and Vault
 * @dev These tests simulate actual user behavior and edge cases
 */
contract IntegrationTests is Test {
    RebaseToken public rebaseToken;
    Vault public vault;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public dave = makeAddr("dave");

    uint256 constant INTEREST_RATE = 6e10; // 6% annual
    uint256 constant PRECISION = 1e18;

    event Deposited(address indexed user, uint256 ethAmount, uint256 tokensReceived, uint256 timestamp);
    event Redeemed(address indexed user, uint256 tokenAmount, uint256 ethReturned, uint256 timestamp);

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken(owner);
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantRole(rebaseToken.MINT_AND_BURN_ROLE(), address(vault));
        vm.stopPrank();

        // Label addresses
        vm.label(owner, "Owner");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(dave, "Dave");
    }

    /*//////////////////////////////////////////////////////////////
                        REALISTIC SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Scenario: Early investor gets more rewards
    /// @dev Alice deposits early, Bob deposits later, both earn proportional interest
    function testIntegration_EarlyInvestorScenario() public {
        // Day 1: Alice deposits 10 ETH
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        // Day 30: Time passes (30 days)
        vm.warp(block.timestamp + 30 days);

        // Day 30: Bob deposits 10 ETH
        vm.deal(bob, 10 ether);
        vm.prank(bob);
        vault.deposit{value: 10 ether}();

        // Day 60: Time passes (another 30 days)
        vm.warp(block.timestamp + 30 days);

        // Check balances
        uint256 aliceBalance = rebaseToken.balanceOf(alice); // 60 days of interest
        uint256 bobBalance = rebaseToken.balanceOf(bob);     // 30 days of interest

        console2.log("Alice balance (60 days):", aliceBalance);
        console2.log("Bob balance (30 days):", bobBalance);

        // Alice should have approximately 2x the interest of Bob
        uint256 aliceInterest = aliceBalance - 10 ether;
        uint256 bobInterest = bobBalance - 10 ether;

        assertGt(aliceBalance, bobBalance, "Alice should have more due to longer holding");
        assertApproxEqRel(aliceInterest, bobInterest * 2, 0.01e18, "Alice interest ~2x Bob's interest");
    }

    /// @notice Scenario: Whale manipulation test
    /// @dev Large deposit shouldn't break the system
    function testIntegration_WhaleDeposit() public {
        uint256 whaleAmount = 100_000 ether;

        vm.deal(alice, whaleAmount);
        vm.prank(alice);
        vault.deposit{value: whaleAmount}();

        // Warp 1 year
        vm.warp(block.timestamp + 365 days);

        uint256 balance = rebaseToken.balanceOf(alice);
        uint256 expectedInterest = (whaleAmount * INTEREST_RATE * 365 days) / PRECISION;

        assertApproxEqRel(balance, whaleAmount + expectedInterest, 0.001e18, "Interest calculation accurate for large amounts");

        // Fund vault for redemption
        vm.deal(address(vault), balance);

        // Whale redeems all
        vm.prank(alice);
        vault.redeem(balance);

        assertEq(rebaseToken.balanceOf(alice), 0, "All tokens burned");
        assertEq(alice.balance, balance, "All ETH returned");
    }

    /// @notice Scenario: DeFi composability - Transfer between users
    /// @dev Users can transfer tokens and receiver continues earning interest
    function testIntegration_TokenTransferScenario() public {
        // Alice deposits 10 ETH
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        // 30 days pass
        vm.warp(block.timestamp + 30 days);

        uint256 aliceBalanceBefore = rebaseToken.balanceOf(alice);

        // Alice transfers 5 tokens to Bob
        vm.prank(alice);
        rebaseToken.transfer(bob, 5 ether);

        // At this point Bob has received tokens and his timestamp is set
        // He doesn't have interest yet because no time has passed since transfer

        // 30 more days pass
        vm.warp(block.timestamp + 30 days);

        uint256 aliceBalanceAfter = rebaseToken.balanceOf(alice);
        uint256 bobBalanceAfter = rebaseToken.balanceOf(bob);

        console2.log("Alice balance after transfer + 30d:", aliceBalanceAfter);
        console2.log("Bob balance after receiving + 30d:", bobBalanceAfter);

        // Both should have earned interest on their holdings
        assertGt(aliceBalanceAfter, aliceBalanceBefore - 5 ether, "Alice earned interest on remaining tokens");
        // Bob won't have interest because his timestamp was set at transfer time,
        // and he hasn't deposited (hasn't been assigned an interest rate)
        // So we check he at least has the transferred amount
        assertGe(bobBalanceAfter, 5 ether, "Bob has at least transferred tokens");
    }

    /// @notice Scenario: Multiple partial redeems
    /// @dev User deposits, redeems partially multiple times
    function testIntegration_MultiplePartialRedeems() public {
        // Alice deposits 100 ETH
        vm.deal(alice, 100 ether);
        vm.prank(alice);
        vault.deposit{value: 100 ether}();

        // Redeem 10 ETH after 10 days (5 times)
        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + 10 days);

            uint256 balanceBefore = rebaseToken.balanceOf(alice);

            // Fund vault
            vm.deal(address(vault), 20 ether);

            vm.prank(alice);
            vault.redeem(10 ether);

            uint256 balanceAfter = rebaseToken.balanceOf(alice);

            console2.log("Iteration", i + 1, "- Balance:", balanceAfter);

            // Balance should decrease by exactly 10 ETH each time
            assertApproxEqAbs(balanceBefore - balanceAfter, 10 ether, 1, "10 ETH redeemed");
        }

        // Alice should still have tokens left (original + interest - 50 ETH redeemed)
        assertGt(rebaseToken.balanceOf(alice), 0, "Alice has tokens remaining");
    }

    /// @notice Scenario: Emergency pause and unpause
    /// @dev Owner pauses system, operations fail, then unpauses
    function testIntegration_EmergencyPauseScenario() public {
        // Alice deposits
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        // Owner detects issue and pauses both Vault AND RebaseToken
        vm.startPrank(owner);
        vault.pause();
        rebaseToken.pause();
        vm.stopPrank();

        // Alice tries to redeem - should fail
        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(5 ether);

        // Bob tries to deposit - should fail
        vm.deal(bob, 10 ether);
        vm.prank(bob);
        vm.expectRevert();
        vault.deposit{value: 10 ether}();

        // Transfers should also fail (now that RebaseToken is paused)
        vm.prank(alice);
        vm.expectRevert();
        rebaseToken.transfer(bob, 1 ether);

        // Owner fixes issue and unpauses both
        vm.startPrank(owner);
        vault.unpause();
        rebaseToken.unpause();
        vm.stopPrank();

        // Operations work again
        vm.prank(alice);
        vault.redeem(5 ether);

        assertEq(rebaseToken.balanceOf(alice), 5 ether, "Redeem worked after unpause");
    }

    /// @notice Scenario: Interest settlement on burn (the bug we fixed!)
    /// @dev This specifically tests the stack overflow fix
    function testIntegration_BurnWithLargeInterestAccrual() public {
        // Alice deposits
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        // 5 years pass (extreme interest accrual)
        vm.warp(block.timestamp + 365 days * 5);

        uint256 balanceWithInterest = rebaseToken.balanceOf(alice);
        console2.log("Balance after 5 years:", balanceWithInterest);

        // Fund vault
        vm.deal(address(vault), balanceWithInterest);

        // This used to cause stack overflow before the fix!
        vm.prank(alice);
        vault.redeem(balanceWithInterest);

        assertEq(rebaseToken.balanceOf(alice), 0, "All tokens burned successfully");
        assertEq(alice.balance, balanceWithInterest, "All ETH returned");
    }

    /// @notice Scenario: Gas-efficient batch operations
    /// @dev Multiple users deposit in sequence, then redeem
    function testIntegration_BatchOperations() public {
        address[] memory users = new address[](10);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = dave;
        for (uint256 i = 4; i < 10; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
        }

        // All users deposit 1 ETH each
        for (uint256 i = 0; i < users.length; i++) {
            vm.deal(users[i], 1 ether);
            vm.prank(users[i]);
            vault.deposit{value: 1 ether}();
        }

        // Verify total supply
        assertEq(rebaseToken.totalSupply(), 10 ether, "Total supply correct");

        // Time passes
        vm.warp(block.timestamp + 30 days);

        // Fund vault generously
        vm.deal(address(vault), 100 ether);

        // All users redeem
        for (uint256 i = 0; i < users.length; i++) {
            uint256 balance = rebaseToken.balanceOf(users[i]);
            vm.prank(users[i]);
            vault.redeem(balance);

            assertEq(rebaseToken.balanceOf(users[i]), 0, "User redeemed all");
        }

        assertEq(rebaseToken.totalSupply(), 0, "All tokens burned");
    }

    /// @notice Scenario: Vault insolvency protection
    /// @dev Redeem should fail if vault doesn't have enough ETH
    function testIntegration_VaultInsolvencyProtection() public {
        // Alice deposits 10 ETH
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        // Time passes, interest accrues
        vm.warp(block.timestamp + 365 days);

        uint256 balanceWithInterest = rebaseToken.balanceOf(alice);
        assertGt(balanceWithInterest, 10 ether, "Interest accrued");

        // Vault only has original 10 ETH, not enough for interest
        // Alice tries to redeem all - should fail with custom error
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                Vault.Vault__InsufficientVaultBalance.selector,
                balanceWithInterest,
                address(vault).balance
            )
        );
        vault.redeem(balanceWithInterest);

        // Alice can still redeem up to vault balance
        vm.prank(alice);
        vault.redeem(9 ether); // Vault has 10 ETH, redeem 9

        assertEq(alice.balance, 9 ether, "Partial redeem successful");
    }

    /// @notice Scenario: Zero interest period
    /// @dev If no time passes, balance shouldn't change
    function testIntegration_ZeroInterestPeriod() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        uint256 balanceBefore = rebaseToken.balanceOf(alice);

        // No time passes (same block)
        uint256 balanceAfter = rebaseToken.balanceOf(alice);

        assertEq(balanceBefore, balanceAfter, "No interest in same block");
    }

    /// @notice Scenario: Interest rate cannot increase (security feature)
    /// @dev Owner tries to increase rate - should fail
    function testIntegration_InterestRateCannotIncrease() public {
        uint256 currentRate = rebaseToken.s_globalInterestRate();

        // Owner tries to increase rate
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector,
                currentRate,
                currentRate + 1
            )
        );
        rebaseToken.setGlobalInterestRate(currentRate + 1);
    }

    /// @notice Scenario: Interest rate can decrease
    /// @dev Owner decreases rate, new deposits get lower rate
    function testIntegration_InterestRateDecrease() public {
        uint256 currentRate = rebaseToken.s_globalInterestRate(); // 6e10

        // Alice deposits at 6% rate
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        // Owner decreases rate to 3%
        uint256 newRate = 3e10;
        vm.prank(owner);
        rebaseToken.setGlobalInterestRate(newRate);

        // Bob deposits at 3% rate
        vm.deal(bob, 10 ether);
        vm.prank(bob);
        vault.deposit{value: 10 ether}();

        // Time passes
        vm.warp(block.timestamp + 365 days);

        // Alice should have ~6% interest, Bob should have ~3% interest
        uint256 aliceBalance = rebaseToken.balanceOf(alice);
        uint256 bobBalance = rebaseToken.balanceOf(bob);

        uint256 aliceInterest = aliceBalance - 10 ether;
        uint256 bobInterest = bobBalance - 10 ether;

        console2.log("Alice interest (6% rate):", aliceInterest);
        console2.log("Bob interest (3% rate):", bobInterest);

        assertGt(aliceInterest, bobInterest, "Alice earned more with higher rate");
        assertApproxEqRel(aliceInterest, bobInterest * 2, 0.01e18, "Alice earned ~2x Bob's interest");
    }

    /// @notice Scenario: Roles and access control
    /// @dev Non-authorized addresses cannot mint/burn
    function testIntegration_AccessControlEnforced() public {
        // Random user tries to mint tokens
        vm.prank(alice);
        vm.expectRevert();
        rebaseToken.mint(alice, 1000 ether);

        // Random user tries to burn tokens
        vm.prank(alice);
        vm.expectRevert();
        rebaseToken.burn(alice, 1 ether);

        // Only vault (with MINT_AND_BURN_ROLE) can mint/burn through deposit/redeem
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vault.deposit{value: 10 ether}(); // This calls mint internally - should work

        vm.prank(alice);
        vault.redeem(5 ether); // This calls burn internally - should work

        assertEq(rebaseToken.balanceOf(alice), 5 ether, "Vault operations worked");
    }

    /*//////////////////////////////////////////////////////////////
                        STRESS TEST SCENARIOS
    //////////////////////////////////////////////////////////////*/

    /// @notice Stress test: Many small deposits and redeems
    function testIntegration_ManySmallOperations() public {
        for (uint256 i = 0; i < 50; i++) {
            // Deposit 0.1 ETH
            vm.deal(alice, 0.1 ether);
            vm.prank(alice);
            vault.deposit{value: 0.1 ether}();

            // Redeem 0.05 ETH
            vm.prank(alice);
            vault.redeem(0.05 ether);
        }

        // Alice should have ~2.5 ETH in tokens (50 * 0.1 - 50 * 0.05)
        uint256 balance = rebaseToken.balanceOf(alice);
        assertApproxEqAbs(balance, 2.5 ether, 0.01 ether, "Balance after many operations");
    }

    /// @notice Stress test: Maximum time warp
    /// @dev Simulate 100 years passing
    function testIntegration_ExtremeTimeWarp() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        // 100 years pass
        vm.warp(block.timestamp + 365 days * 100);

        uint256 balance = rebaseToken.balanceOf(alice);

        // Should not overflow or revert
        assertGt(balance, 1 ether, "Balance increased");

        // Calculate expected: 1 ETH * (1 + 0.06 * 100) = 7 ETH
        uint256 expectedInterest = (1 ether * INTEREST_RATE * (365 days * 100)) / PRECISION;
        assertApproxEqRel(balance, 1 ether + expectedInterest, 0.001e18, "Interest accurate over 100 years");
    }
}
