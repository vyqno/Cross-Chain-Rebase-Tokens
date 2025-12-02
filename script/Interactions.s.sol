// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

/**
 * @title Interactions
 * @notice Scripts to interact with deployed contracts
 * @dev Uses foundry-devops to find most recent deployments
 */

/// @notice Script to deposit ETH into the vault
contract Deposit is Script {
    function run() external {
        address mostRecentVault = DevOpsTools.get_most_recent_deployment("Vault", block.chainid);

        console2.log("Interacting with Vault at:", mostRecentVault);

        depositToVault(mostRecentVault);
    }

    function depositToVault(address vaultAddress) public {
        uint256 depositAmount = 1 ether;

        vm.startBroadcast();

        Vault vault = Vault(payable(vaultAddress));
        vault.deposit{value: depositAmount}();

        console2.log("Deposited", depositAmount, "ETH to vault");

        vm.stopBroadcast();
    }
}

/// @notice Script to redeem tokens from the vault
contract Redeem is Script {
    function run() external {
        address mostRecentVault = DevOpsTools.get_most_recent_deployment("Vault", block.chainid);

        console2.log("Interacting with Vault at:", mostRecentVault);

        redeemFromVault(mostRecentVault);
    }

    function redeemFromVault(address vaultAddress) public {
        vm.startBroadcast();

        Vault vault = Vault(payable(vaultAddress));

        // Get RebaseToken address
        address rebaseTokenAddress = vault.getRebaseTokenAddress();
        RebaseToken rebaseToken = RebaseToken(rebaseTokenAddress);

        // Get user's balance
        uint256 balance = rebaseToken.balanceOf(msg.sender);
        console2.log("User balance:", balance);

        if (balance > 0) {
            // Redeem all tokens
            vault.redeem(balance);
            console2.log("Redeemed", balance, "tokens");
        } else {
            console2.log("No tokens to redeem");
        }

        vm.stopBroadcast();
    }
}

/// @notice Script to check balances
contract CheckBalance is Script {
    function run() external view {
        address mostRecentVault = DevOpsTools.get_most_recent_deployment("Vault", block.chainid);

        Vault vault = Vault(payable(mostRecentVault));
        address rebaseTokenAddress = vault.getRebaseTokenAddress();
        RebaseToken rebaseToken = RebaseToken(rebaseTokenAddress);

        address user = vm.envAddress("USER_ADDRESS");

        console2.log("=== Balance Check ===");
        console2.log("User:", user);
        console2.log("Token Balance:", rebaseToken.balanceOf(user));
        console2.log("ETH Balance:", user.balance);
        console2.log("Vault ETH Balance:", address(vault).balance);
        console2.log("Total Supply:", rebaseToken.totalSupply());
    }
}

/// @notice Script to simulate time passage and check interest
contract SimulateInterest is Script {
    function run() external {
        address mostRecentVault = DevOpsTools.get_most_recent_deployment("Vault", block.chainid);

        Vault vault = Vault(payable(mostRecentVault));
        address rebaseTokenAddress = vault.getRebaseTokenAddress();
        RebaseToken rebaseToken = RebaseToken(rebaseTokenAddress);

        address user = vm.envAddress("USER_ADDRESS");

        console2.log("=== Interest Simulation ===");
        console2.log("Current timestamp:", block.timestamp);
        console2.log("Balance before:", rebaseToken.balanceOf(user));

        // Warp 30 days
        vm.warp(block.timestamp + 30 days);

        console2.log("New timestamp:", block.timestamp);
        console2.log("Balance after 30 days:", rebaseToken.balanceOf(user));
    }
}
