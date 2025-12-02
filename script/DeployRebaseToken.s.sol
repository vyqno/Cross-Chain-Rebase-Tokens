// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

/**
 * @title DeployRebaseToken
 * @notice Deployment script for RebaseToken and Vault contracts
 * @dev Use with: forge script script/DeployRebaseToken.s.sol --rpc-url <RPC> --broadcast
 */
contract DeployRebaseToken is Script {
    // Deployment configuration
    struct DeploymentConfig {
        address deployer;
        address mintAndBurnRecipient; // Will be set to Vault address
    }

    function run() external returns (RebaseToken rebaseToken, Vault vault) {
        // Get deployment configuration
        DeploymentConfig memory config = getConfig();

        console2.log("=== Starting Deployment ===");
        console2.log("Deployer:", config.deployer);
        console2.log("Chain ID:", block.chainid);

        // Start broadcasting transactions
        vm.startBroadcast(config.deployer);

        // Deploy RebaseToken (pass deployer as temporary mintAndBurn recipient)
        console2.log("\n1. Deploying RebaseToken...");
        rebaseToken = new RebaseToken(config.deployer);
        console2.log("RebaseToken deployed at:", address(rebaseToken));

        // Deploy Vault
        console2.log("\n2. Deploying Vault...");
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        console2.log("Vault deployed at:", address(vault));

        // Grant MINT_AND_BURN_ROLE to Vault
        console2.log("\n3. Granting MINT_AND_BURN_ROLE to Vault...");
        bytes32 mintAndBurnRole = rebaseToken.MINT_AND_BURN_ROLE();
        rebaseToken.grantRole(mintAndBurnRole, address(vault));
        console2.log("Role granted successfully");

        // Verify deployment
        console2.log("\n=== Deployment Verification ===");
        console2.log("RebaseToken address:", address(rebaseToken));
        console2.log("Vault address:", address(vault));
        console2.log("Owner:", rebaseToken.owner());
        console2.log("Global interest rate:", rebaseToken.s_globalInterestRate());
        console2.log("Vault has MINT_AND_BURN_ROLE:", rebaseToken.hasRole(mintAndBurnRole, address(vault)));

        vm.stopBroadcast();

        console2.log("\n=== Deployment Complete ===");

        return (rebaseToken, vault);
    }

    /// @notice Get deployment configuration based on chain ID
    function getConfig() internal view returns (DeploymentConfig memory) {
        DeploymentConfig memory config;

        // Get deployer from environment or use default
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0));

        if (deployerPrivateKey != 0) {
            config.deployer = vm.addr(deployerPrivateKey);
        } else {
            // For local testing, use default anvil account
            config.deployer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        }

        return config;
    }
}
