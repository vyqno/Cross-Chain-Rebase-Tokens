// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";

/**
 * @title Handler
 * @notice Handler contract for stateful fuzzing (invariant testing)
 * @dev This contract wraps vault operations and tracks ghost variables for invariant checks
 */
contract Handler is Test {
    RebaseToken public rebaseToken;
    Vault public vault;

    // Ghost variables to track state across fuzz runs
    uint256 public ghost_depositSum;
    uint256 public ghost_redeemSum;
    uint256 public ghost_depositCount;
    uint256 public ghost_redeemCount;
    uint256 public ghost_timeWarps;

    // Track individual user deposits for more complex invariants
    mapping(address => uint256) public ghost_userDeposits;

    // Array of actors that have interacted with the system
    address[] public actors;
    mapping(address => bool) public isActor;

    // Current actor for this transaction
    address public currentActor;

    // Modifiers
    modifier useActor(uint256 actorIndexSeed) {
        currentActor = _getRandomActor(actorIndexSeed);
        _;
    }

    modifier countCall(string memory functionName) {
        _;
        console2.log(functionName, "called by", currentActor);
    }

    constructor(RebaseToken _rebaseToken, Vault _vault) {
        rebaseToken = _rebaseToken;
        vault = _vault;
    }

    /*//////////////////////////////////////////////////////////////
                        HANDLER FUNCTIONS (ACTIONS)
    //////////////////////////////////////////////////////////////*/

    /// @notice Handler for deposit function
    function deposit(uint256 actorSeed, uint256 amount) public useActor(actorSeed) countCall("deposit") {
        // Bound amount to reasonable values
        amount = bound(amount, 0.01 ether, 1000 ether);

        // Give actor enough ETH
        vm.deal(currentActor, amount);

        // Perform deposit
        vm.prank(currentActor);
        try vault.deposit{value: amount}() {
            // Track successful deposit
            ghost_depositSum += amount;
            ghost_depositCount++;
            ghost_userDeposits[currentActor] += amount;

            // Add to actors list if new
            if (!isActor[currentActor]) {
                actors.push(currentActor);
                isActor[currentActor] = true;
            }
        } catch {
            // Deposit failed, don't update ghost variables
        }
    }

    /// @notice Handler for redeem function
    function redeem(uint256 actorSeed, uint256 amount) public useActor(actorSeed) countCall("redeem") {
        // Get user's current balance
        uint256 balance = rebaseToken.balanceOf(currentActor);

        if (balance == 0) return; // Skip if no balance

        // Bound redeem amount to user's balance
        amount = bound(amount, 1, balance);

        // Fund vault if needed (simulate vault having enough ETH)
        uint256 vaultBalance = address(vault).balance;
        if (vaultBalance < amount) {
            vm.deal(address(vault), amount);
        }

        // Perform redeem
        vm.prank(currentActor);
        try vault.redeem(amount) {
            // Track successful redeem
            ghost_redeemSum += amount;
            ghost_redeemCount++;
        } catch {
            // Redeem failed, don't update ghost variables
        }
    }

    /// @notice Handler for redeem max
    function redeemMax(uint256 actorSeed) public useActor(actorSeed) countCall("redeemMax") {
        uint256 balance = rebaseToken.balanceOf(currentActor);

        if (balance == 0) return;

        // Fund vault
        vm.deal(address(vault), balance);

        vm.prank(currentActor);
        try vault.redeem(type(uint256).max) {
            ghost_redeemSum += balance;
            ghost_redeemCount++;
        } catch {}
    }

    /// @notice Handler for time warp (simulates passage of time)
    function warpTime(uint256 timeToWarp) public countCall("warpTime") {
        timeToWarp = bound(timeToWarp, 1 hours, 365 days);

        vm.warp(block.timestamp + timeToWarp);
        ghost_timeWarps++;
    }

    /// @notice Handler for token transfer between users
    function transfer(uint256 fromActorSeed, uint256 toActorSeed, uint256 amount) public countCall("transfer") {
        if (actors.length < 2) return; // Need at least 2 actors

        address from = _getRandomActor(fromActorSeed);
        address to = _getRandomActor(toActorSeed);

        if (from == to) return; // Skip self-transfers

        uint256 balance = rebaseToken.balanceOf(from);
        if (balance == 0) return;

        amount = bound(amount, 1, balance);

        vm.prank(from);
        try rebaseToken.transfer(to, amount) {
            // Transfer succeeded
        } catch {}
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get a random actor from existing actors or create a new one
    function _getRandomActor(uint256 seed) internal returns (address) {
        if (actors.length == 0) {
            address newActor = address(uint160(seed));
            actors.push(newActor);
            isActor[newActor] = true;
            return newActor;
        }

        // 80% chance to use existing actor, 20% chance to create new one
        if (seed % 100 < 80 && actors.length > 0) {
            return actors[seed % actors.length];
        } else {
            address newActor = address(uint160(seed));
            if (!isActor[newActor]) {
                actors.push(newActor);
                isActor[newActor] = true;
            }
            return newActor;
        }
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get total number of unique actors
    function getActorCount() external view returns (uint256) {
        return actors.length;
    }

    /// @notice Get sum of all user balances
    function getTotalUserBalances() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < actors.length; i++) {
            total += rebaseToken.balanceOf(actors[i]);
        }
        return total;
    }

    /// @notice Get total deposits across all users
    function getTotalDeposits() external view returns (uint256) {
        return ghost_depositSum;
    }

    /// @notice Get total redeems across all users
    function getTotalRedeems() external view returns (uint256) {
        return ghost_redeemSum;
    }
}
