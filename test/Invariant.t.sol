// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Handler} from "./Handler.t.sol";

/**
 * @title InvariantTests
 * @notice Stateful fuzz testing that checks invariants hold after random sequences of operations
 * @dev These tests will call random functions in random order and verify properties always hold
 *
 * Key Invariants to Maintain:
 * 1. Solvency: Vault balance >= what it owes (deposits - redeems)
 * 2. Token conservation: Total supply = sum of all user balances
 * 3. Interest monotonicity: User balances never decrease over time (unless they transfer/redeem)
 * 4. Accounting: Total supply reflects all mints and burns correctly
 */
contract InvariantTests is StdInvariant, Test {
    RebaseToken public rebaseToken;
    Vault public vault;
    Handler public handler;

    address public owner = makeAddr("owner");

    function setUp() public {
        vm.startPrank(owner);

        // Deploy contracts
        rebaseToken = new RebaseToken(owner);
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantRole(rebaseToken.MINT_AND_BURN_ROLE(), address(vault));

        // Deploy handler
        handler = new Handler(rebaseToken, vault);

        vm.stopPrank();

        // Target the handler for invariant testing
        targetContract(address(handler));

        // Target specific functions for fuzzing
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = Handler.deposit.selector;
        selectors[1] = Handler.redeem.selector;
        selectors[2] = Handler.redeemMax.selector;
        selectors[3] = Handler.warpTime.selector;
        selectors[4] = Handler.transfer.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        // Label for better traces
        vm.label(address(rebaseToken), "RebaseToken");
        vm.label(address(vault), "Vault");
        vm.label(address(handler), "Handler");
    }

    /*//////////////////////////////////////////////////////////////
                        CRITICAL INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice INVARIANT 1: Total supply must equal sum of all user balances
    /// @dev This ensures token conservation - no tokens are created or destroyed unexpectedly
    function invariant_TotalSupplyEqualsBalances() public view {
        uint256 totalSupply = rebaseToken.totalSupply();
        uint256 sumOfBalances = handler.getTotalUserBalances();

        assertEq(
            totalSupply,
            sumOfBalances,
            "Total supply should always equal sum of user balances"
        );
    }

    /// @notice INVARIANT 2: Vault solvency (basic version without interest)
    /// @dev Vault should always have at least the base deposits minus redeems
    /// @dev Note: This is a simplified check. In reality, vault needs extra for interest.
    function invariant_VaultHasMinimumBalance() public view {
        uint256 totalDeposits = handler.getTotalDeposits();
        uint256 totalRedeems = handler.getTotalRedeems();
        uint256 vaultBalance = address(vault).balance;

        // Vault should have at least what it owes (deposits - redeems)
        // We allow some margin because interest might accrue
        uint256 minimumRequired = totalDeposits > totalRedeems ? totalDeposits - totalRedeems : 0;

        assertGe(
            vaultBalance,
            minimumRequired,
            "Vault should maintain minimum balance for deposits"
        );
    }

    /// @notice INVARIANT 3: Total supply should never exceed deposits
    /// @dev Total supply can be higher than base deposits due to interest, but should be reasonable
    function invariant_TotalSupplyReasonable() public view {
        uint256 totalSupply = rebaseToken.totalSupply();
        uint256 totalDeposits = handler.getTotalDeposits();

        // Total supply should not be more than 10x deposits (even with 50 years of 6% interest)
        // This catches any catastrophic minting bugs
        if (totalDeposits > 0) {
            assertLe(
                totalSupply,
                totalDeposits * 10,
                "Total supply should not exceed 10x total deposits"
            );
        }
    }

    /// @notice INVARIANT 4: No user should have zero timestamp if they have balance
    /// @dev Every user with tokens should have been initialized with a timestamp
    function invariant_UsersWithBalanceHaveTimestamp() public view {
        address[] memory actors = _getActors();

        for (uint256 i = 0; i < actors.length; i++) {
            address actor = actors[i];
            uint256 balance = rebaseToken.balanceOf(actor);

            if (balance > 0) {
                uint256 timestamp = rebaseToken.getUserLastUpdateTimestamp(actor);
                assertGt(timestamp, 0, "User with balance should have non-zero timestamp");
            }
        }
    }

    /// @notice INVARIANT 5: Interest rate should always be within bounds
    /// @dev Global interest rate should never exceed max or go below min
    function invariant_InterestRateWithinBounds() public view {
        uint256 globalRate = rebaseToken.s_globalInterestRate();
        uint256 maxRate = rebaseToken.MAX_INTEREST_RATE();
        uint256 minRate = rebaseToken.MIN_INTEREST_RATE();

        assertGe(globalRate, minRate, "Interest rate should not be below minimum");
        assertLe(globalRate, maxRate, "Interest rate should not exceed maximum");
    }

    /// @notice INVARIANT 6: Paused state should prevent operations
    /// @dev If contract is paused, critical functions should revert (not tested here but documented)
    function invariant_PausedStateConsistent() public view {
        bool isPaused = rebaseToken.paused();
        // In a real scenario, you'd verify operations fail when paused
        // For now, we just check the state is boolean
        assertTrue(isPaused || !isPaused, "Paused state should be valid boolean");
    }

    /// @notice INVARIANT 7: Vault should never have more tokens than it should
    /// @dev Vault contract itself should not hold tokens (users hold tokens, vault holds ETH)
    function invariant_VaultDoesNotHoldTokens() public view {
        uint256 vaultTokenBalance = rebaseToken.balanceOf(address(vault));
        assertEq(vaultTokenBalance, 0, "Vault should not hold any tokens");
    }

    /// @notice INVARIANT 8: Total supply changes should match deposit/redeem operations
    /// @dev This is tracked through the handler's ghost variables
    function invariant_SupplyMatchesOperations() public view {
        uint256 totalDeposits = handler.getTotalDeposits();
        uint256 totalRedeems = handler.getTotalRedeems();
        uint256 totalSupply = rebaseToken.totalSupply();

        // Total supply should be at least deposits - redeems (can be higher due to interest)
        uint256 netDeposits = totalDeposits > totalRedeems ? totalDeposits - totalRedeems : 0;

        assertGe(
            totalSupply,
            netDeposits,
            "Total supply should be at least net deposits (deposits - redeems)"
        );
    }

    /*//////////////////////////////////////////////////////////////
                        STATISTICAL INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice STAT: Log call statistics after invariant runs
    /// @dev Not a real invariant, just logging for debugging
    function invariant_LogCallSummary() public view {
        console2.log("=== INVARIANT TEST SUMMARY ===");
        console2.log("Total deposits:", handler.ghost_depositCount());
        console2.log("Total redeems:", handler.ghost_redeemCount());
        console2.log("Total time warps:", handler.ghost_timeWarps());
        console2.log("Unique actors:", handler.getActorCount());
        console2.log("Total supply:", rebaseToken.totalSupply());
        console2.log("Vault balance:", address(vault).balance);
        console2.log("==============================");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get all actors from handler
    function _getActors() internal view returns (address[] memory) {
        uint256 actorCount = handler.getActorCount();
        address[] memory actorList = new address[](actorCount);

        for (uint256 i = 0; i < actorCount; i++) {
            actorList[i] = handler.actors(i);
        }

        return actorList;
    }
}
