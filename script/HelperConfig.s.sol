// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";

/**
 * @title HelperConfig
 * @notice Configuration helper for different networks
 * @dev Provides network-specific configuration for deployments
 */
contract HelperConfig is Script {
    struct NetworkConfig {
        string name;
        uint256 chainId;
        string rpcUrl;
    }

    NetworkConfig public activeNetworkConfig;

    mapping(uint256 => NetworkConfig) public networkConfigs;

    constructor() {
        // Ethereum Mainnet
        networkConfigs[1] = NetworkConfig({
            name: "Ethereum Mainnet",
            chainId: 1,
            rpcUrl: vm.envOr("MAINNET_RPC_URL", string(""))
        });

        // Sepolia Testnet
        networkConfigs[11155111] = NetworkConfig({
            name: "Sepolia",
            chainId: 11155111,
            rpcUrl: vm.envOr("SEPOLIA_RPC_URL", string(""))
        });

        // Local Anvil
        networkConfigs[31337] = NetworkConfig({
            name: "Anvil Local",
            chainId: 31337,
            rpcUrl: "http://127.0.0.1:8545"
        });

        // Set active config based on current chain
        activeNetworkConfig = getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(uint256 chainId) public view returns (NetworkConfig memory) {
        if (networkConfigs[chainId].chainId != 0) {
            return networkConfigs[chainId];
        }

        // Default to Anvil if chain not configured
        return networkConfigs[31337];
    }

    function getActiveNetworkConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}
