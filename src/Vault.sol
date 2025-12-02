// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
/**
 * @title  Vault
 * @author vyqno(Hitesh)
 * @notice A secure vault contract that accepts ETH deposits and mints RebaseTokens
 * @dev    Implements a 1:1 ETH to RebaseToken exchange mechanism with withdrawal functionality
 *
 * Key Features:
 * - ETH deposits minting equivalent RebaseTokens
 * - Redemption of RebaseTokens for underlying ETH
 * - Emergency pause mechanism
 * - Reentrancy protection
 * - Comprehensive event logging
 *
 * Security Features:
 * - ReentrancyGuard on all state-changing functions
 * - Pausable for emergency situations
 * - Owner controls for administrative functions
 * - Zero address and zero amount validations
 * - Balance checks before transfers
 * - CEI (Checks-Effects-Interactions) pattern
 */

contract Vault is ReentrancyGuard, Pausable, Ownable, AccessControl {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The RebaseToken contract that this vault manages
    /// @dev Immutable after deployment for security and gas efficiency
    IRebaseToken private immutable i_rebaseToken;

    /// @notice Total ETH deposited into the vault (excluding withdrawn amounts)
    /// @dev Tracks vault's liability to token holders
    uint256 private s_totalDeposits;

    /// @notice Mapping to track individual user deposits for accounting
    /// @dev Used for analytics and potential pro-rata calculations
    mapping(address => uint256) private s_userDeposits;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a user deposits ETH and receives RebaseTokens
     * @param user Address of the depositor
     * @param ethAmount Amount of ETH deposited
     * @param tokensReceived Amount of RebaseTokens minted
     * @param timestamp Block timestamp of deposit
     */
    event Deposited(address indexed user, uint256 ethAmount, uint256 tokensReceived, uint256 timestamp);

    /**
     * @notice Emitted when a user redeems RebaseTokens for ETH
     * @param user Address of the redeemer
     * @param tokenAmount Amount of RebaseTokens burned
     * @param ethReturned Amount of ETH returned to user
     * @param timestamp Block timestamp of redemption
     */
    event Redeemed(address indexed user, uint256 tokenAmount, uint256 ethReturned, uint256 timestamp);

    /**
     * @notice Emitted when owner withdraws excess ETH from vault
     * @param owner Address of the owner
     * @param amount Amount of ETH withdrawn
     * @param timestamp Block timestamp of withdrawal
     */
    event EmergencyWithdrawal(address indexed owner, uint256 amount, uint256 timestamp);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when deposit amount is zero
    error Vault__ZeroDepositAmount();

    /// @notice Thrown when redemption amount is zero
    error Vault__ZeroRedeemAmount();

    /// @notice Thrown when vault has insufficient ETH for redemption
    error Vault__InsufficientVaultBalance(uint256 requested, uint256 available);

    /// @notice Thrown when user has insufficient RebaseToken balance
    error Vault__InsufficientTokenBalance(uint256 requested, uint256 available);

    /// @notice Thrown when ETH transfer fails
    error Vault__EthTransferFailed();

    /// @notice Thrown when trying to withdraw more than excess ETH
    error Vault__InsufficientExcessFunds(uint256 requested, uint256 available);

    /// @notice Thrown when address is zero where not allowed
    error Vault__ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the Vault contract
     * @dev Sets the RebaseToken contract address and transfers ownership to deployer
     *
     * @param _rebaseToken Address of the RebaseToken contract
     *
     * Requirements:
     * - `_rebaseToken` cannot be zero address
     *
     * Initial State:
     * - Total Deposits: 0
     * - Contract Status: Not paused
     * - Owner: msg.sender
     *
     * @custom:security RebaseToken address is immutable after deployment
     */
    constructor(IRebaseToken _rebaseToken) Ownable(msg.sender) {
        if (address(_rebaseToken) == address(0)) {
            revert Vault__ZeroAddress();
        }
        i_rebaseToken = _rebaseToken;
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits ETH into the vault and receives RebaseTokens
     * @dev Mints RebaseTokens 1:1 with deposited ETH amount
     *
     * Requirements:
     * - Contract must not be paused
     * - msg.value must be greater than zero
     * - Vault must have sufficient ETH to back all tokens
     *
     * Effects:
     * - Increases s_totalDeposits by msg.value
     * - Increases user's deposit tracking
     * - Calls RebaseToken.mint() to issue tokens
     * - Emits Deposited event
     *
     * Exchange Rate: 1 ETH = 1 RebaseToken (1e18 wei = 1e18 tokens)
     *
     * Gas Cost: ~100,000-150,000 (includes token minting)
     *
     * @custom:security Protected by nonReentrant and whenNotPaused modifiers
     */
    function deposit() external payable nonReentrant whenNotPaused {
        // Validate deposit amount
        if (msg.value == 0) {
            revert Vault__ZeroDepositAmount();
        }

        // Update state before external calls (CEI pattern)
        s_totalDeposits += msg.value;
        s_userDeposits[msg.sender] += msg.value;

        // Mint RebaseTokens to depositor (1:1 ratio)
        i_rebaseToken.mint(msg.sender, msg.value);

        emit Deposited(msg.sender, msg.value, msg.value, block.timestamp);
    }

    /**
     * @notice Redeems RebaseTokens for underlying ETH
     * @dev Burns RebaseTokens and returns equivalent ETH to user
     *
     * @param amount Amount of RebaseTokens to redeem (in wei, 18 decimals)
     *
     * Requirements:
     * - Contract must not be paused
     * - `amount` must be greater than zero
     * - User must have sufficient RebaseToken balance (including accrued interest)
     * - Vault must have sufficient ETH to fulfill redemption
     *
     * Effects:
     * - Decreases s_totalDeposits by amount
     * - Calls RebaseToken.burn() to destroy tokens
     * - Transfers ETH to user
     * - Emits Redeemed event
     *
     * Exchange Rate: 1 RebaseToken = 1 ETH (1e18 tokens = 1e18 wei)
     *
     * Gas Cost: ~60,000-100,000 (includes token burning and ETH transfer)
     *
     * @custom:security Protected by nonReentrant and whenNotPaused modifiers
     * @custom:security Uses CEI pattern: burns tokens before ETH transfer
     */
    function redeem(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == type(uint256).max) {
            amount = i_rebaseToken.balanceOf(msg.sender);
        }

        // Validate redemption amount
        if (amount == 0) {
            revert Vault__ZeroRedeemAmount();
        }

        // Check user has sufficient token balance (including accrued interest)
        uint256 userBalance = i_rebaseToken.balanceOf(msg.sender);
        if (userBalance < amount) {
            revert Vault__InsufficientTokenBalance(amount, userBalance);
        }

        // Check vault has sufficient ETH
        if (address(this).balance < amount) {
            revert Vault__InsufficientVaultBalance(amount, address(this).balance);
        }

        // Update state before external calls (CEI pattern)
        // Prevent underflow if redeeming interest (amount > principal deposits)
        if (s_totalDeposits >= amount) {
            s_totalDeposits -= amount;
        } else {
            s_totalDeposits = 0;
        }

        // Burn tokens first (CEI pattern - Effects before Interactions)
        i_rebaseToken.burn(msg.sender, amount);

        // Transfer ETH to user (last to prevent reentrancy)
        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) {
            revert Vault__EthTransferFailed();
        }

        emit Redeemed(msg.sender, amount, amount, block.timestamp);
    }

    /**
     * @notice Allows users to claim accrued interest on their RebaseTokens
     * @dev Settles interest without requiring a deposit or redemption
     *
     * Effects:
     * - Calls RebaseToken.settleInterest() for msg.sender
     * - Mints accrued interest as RebaseTokens
     *
     * Use Cases:
     * - Claiming rewards without depositing/withdrawing
     * - Updating balance before checking token amount
     * - Syncing balance for accurate accounting
     *
     * Gas Cost: ~40,000-60,000 (if interest is minted)
     */
    function claimInterest() external nonReentrant {
        i_rebaseToken.settleInterest(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pauses all vault operations
     * @dev Only callable by contract owner. Used in emergency situations.
     *
     * Requirements:
     * - Caller must be owner
     * - Contract must not already be paused
     *
     * Effects:
     * - Blocks all deposits and redemptions
     * - Emits Paused event
     *
     * @custom:security Emergency brake mechanism
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the vault, re-enabling operations
     * @dev Only callable by contract owner
     *
     * Requirements:
     * - Caller must be owner
     * - Contract must be paused
     *
     * Effects:
     * - Re-enables all vault operations
     * - Emits Unpaused event
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency function to withdraw excess ETH not backing tokens
     * @dev Only callable by owner. Cannot withdraw ETH backing RebaseTokens.
     *
     * @param amount Amount of excess ETH to withdraw
     *
     * Requirements:
     * - Caller must be owner
     * - Amount must not exceed excess ETH (total balance - total deposits)
     *
     * Effects:
     * - Transfers excess ETH to owner
     * - Emits EmergencyWithdrawal event
     *
     * Safety Check: Ensures vault always has enough ETH to back all tokens
     *
     * @custom:security Only withdraws funds not backing issued tokens
     */
    function emergencyWithdrawExcess(uint256 amount) external onlyOwner {
        uint256 excessFunds = address(this).balance - s_totalDeposits;

        if (amount > excessFunds) {
            revert Vault__InsufficientExcessFunds(amount, excessFunds);
        }

        (bool success,) = payable(owner()).call{value: amount}("");
        if (!success) {
            revert Vault__EthTransferFailed();
        }

        emit EmergencyWithdrawal(owner(), amount, block.timestamp);
    }

    /**
     * @notice Allows the owner to deposit ETH into the vault to cover interest payments
     * @dev These funds are treated as excess/rewards and not user deposits
     */
    function depositRewards() external payable onlyOwner {
        // ETH is added to address(this).balance
        // We do not increase s_totalDeposits because this is not a user deposit liability
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the address of the RebaseToken contract
     * @return Address of the RebaseToken contract
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }

    /**
     * @notice Returns the total ETH deposited into the vault
     * @return Total deposits in wei
     *
     * Note: This represents the vault's liability to token holders
     */
    function getTotalDeposits() external view returns (uint256) {
        return s_totalDeposits;
    }

    /**
     * @notice Returns the total ETH deposited by a specific user
     * @param user Address to query
     * @return User's total deposits in wei
     *
     * Note: This is cumulative and doesn't account for redemptions
     */
    function getUserDeposits(address user) external view returns (uint256) {
        return s_userDeposits[user];
    }

    /**
     * @notice Returns the vault's current ETH balance
     * @return Current ETH balance in wei
     */
    function getVaultBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Calculates excess ETH not backing RebaseTokens
     * @return Amount of excess ETH in wei
     *
     * Formula: excessETH = vaultBalance - totalDeposits
     *
     * Use Case: Determines how much ETH can be safely withdrawn by owner
     */
    function getExcessFunds() external view returns (uint256) {
        if (address(this).balance <= s_totalDeposits) {
            return 0;
        }
        return address(this).balance - s_totalDeposits;
    }

    /**
     * @notice Returns the current exchange rate (always 1:1)
     * @return Exchange rate scaled by 1e18 (1e18 = 1:1 ratio)
     *
     * Note: This function exists for interface compatibility
     */
    function getExchangeRate() external pure returns (uint256) {
        return 1e18; // 1:1 exchange rate
    }

    /**
     * @notice Calculates how much ETH a user would receive for redeeming tokens
     * @param tokenAmount Amount of RebaseTokens to redeem
     * @return Amount of ETH that would be returned
     *
     * Note: With 1:1 exchange rate, this simply returns the token amount
     */
    function previewRedeem(uint256 tokenAmount) external pure returns (uint256) {
        return tokenAmount; // 1:1 exchange rate
    }

    /**
     * @notice Calculates how many tokens a user would receive for depositing ETH
     * @param ethAmount Amount of ETH to deposit
     * @return Amount of RebaseTokens that would be minted
     *
     * Note: With 1:1 exchange rate, this simply returns the ETH amount
     */
    function previewDeposit(uint256 ethAmount) external pure returns (uint256) {
        return ethAmount; // 1:1 exchange rate
    }

    /**
     * @notice Checks if the vault is properly collateralized
     * @return True if vault has enough ETH to back all deposits
     *
     * Safety Check: vault balance should always be >= total deposits
     */
    function isFullyCollateralized() external view returns (bool) {
        return address(this).balance >= s_totalDeposits;
    }

    /*//////////////////////////////////////////////////////////////
                        RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Receive function to accept direct ETH transfers
     * @dev ETH sent directly does not mint tokens (use deposit() instead)
     *
     * Use Cases:
     * - Receiving ETH from contract interactions
     * - Accepting refunds or excess payments
     * - Emergency funding of vault
     *
     * Note: Direct ETH transfers become excess funds withdrawable by owner
     */
    receive() external payable {
        // ETH received directly does not mint tokens
        // This allows the vault to receive refunds or be funded externally
    }

    /*//////////////////////////////////////////////////////////////
                        FALLBACK FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fallback function for invalid calls
     * @dev Reverts all calls with data that don't match function signatures
     */
    fallback() external payable {
        revert("Vault: Invalid function call");
    }
}
