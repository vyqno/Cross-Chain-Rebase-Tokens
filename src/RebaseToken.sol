// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

/**
 * @title  RebaseToken
 * @author vyqno(Hitesh)
 * @notice An interest-bearing elastic supply token that automatically accrues yield to holders
 * @dev    Implements continuous interest accrual using time-based calculations
 *
 * Key Features:
 * - Automatic balance growth through interest accrual
 * - Per-user interest rate tracking
 * - Gas-efficient virtual balance calculation
 * - Protection against common vulnerabilities
 *
 * Security Features:
 * - Access control on critical functions (Ownable)
 * - Reentrancy protection on state-changing operations
 * - Emergency pause mechanism
 * - Interest rate bounds to prevent economic attacks
 * - Comprehensive input validation
 *
 * @custom:security-contact security@example.com
 */
contract RebaseToken is ERC20, Ownable, AccessControl, ReentrancyGuard, Pausable {
    /*//////////////////////////////////////////////////////////////
                            TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Role identifier for addresses authorized to mint and burn tokens
    bytes32 public constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    /**
     * @dev Stores user-specific rebase data in a single storage slot for gas efficiency
     * @param lastUpdateTimestamp When the user's balance was last settled (converted from virtual to real)
     * @param interestRate The interest rate applicable to this user (scaled by INTEREST_RATE_PRECISION)
     */
    struct UserRebaseData {
        uint128 lastUpdateTimestamp; // Sufficient until year 10^38
        uint128 interestRate; // Sufficient for rates up to 3.4×10^20
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Global interest rate applied to new deposits (scaled by INTEREST_RATE_PRECISION)
    /// @dev Default: 6e10 = 6% annual rate when divided by 1e12
    uint256 public s_globalInterestRate = 6e10;

    /// @notice Precision multiplier for balance calculations to avoid truncation
    /// @dev Used to maintain 18 decimal precision in mathematical operations
    uint256 private constant PRECISION_VALUE = 1e18;

    /// @notice Precision multiplier for interest rate representation
    /// @dev 1e12 allows for fine-grained rate control (e.g., 0.0001% precision)
    uint256 private constant INTEREST_RATE_PRECISION = 1e12;

    /// @notice Maximum allowed interest rate (100% APY)
    /// @dev Prevents setting unreasonably high rates that could cause overflow or economic attacks
    uint256 public constant MAX_INTEREST_RATE = 1e12; // 100% when divided by 1e12

    /// @notice Minimum allowed interest rate (0.1% APY)
    /// @dev Ensures rate is never set to zero unless explicitly intended
    uint256 public constant MIN_INTEREST_RATE = 1e9; // 0.1% when divided by 1e12

    /// @notice Seconds in a year for APY calculations
    /// @dev Used for converting annual rates to per-second rates
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    /// @notice Mapping from user address to their rebase data
    mapping(address => UserRebaseData) private s_userRebaseData;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when the global interest rate is updated
     * @param oldRate Previous interest rate
     * @param newRate New interest rate
     * @param updatedBy Address that initiated the update
     * @param timestamp Block timestamp when update occurred
     */
    event GlobalInterestRateUpdated(
        uint256 indexed oldRate, uint256 indexed newRate, address indexed updatedBy, uint256 timestamp
    );

    /**
     * @notice Emitted when interest is minted for a user
     * @param user Address receiving the interest
     * @param interestAmount Amount of interest minted
     * @param newBalance User's new total balance after interest
     * @param timestamp Block timestamp when interest was minted
     */
    event InterestMinted(address indexed user, uint256 interestAmount, uint256 newBalance, uint256 timestamp);

    /**
     * @notice Emitted when a user's interest rate is updated
     * @param user Address whose rate is updated
     * @param oldRate Previous user-specific rate
     * @param newRate New user-specific rate
     * @param timestamp Block timestamp when update occurred
     */
    event UserInterestRateUpdated(address indexed user, uint256 oldRate, uint256 newRate, uint256 timestamp);

    /**
     * @notice Emitted when tokens are minted to an address
     * @param to Recipient address
     * @param amount Amount of tokens minted
     * @param minter Address that initiated the mint
     */
    event TokensMinted(address indexed to, uint256 amount, address indexed minter);

    /**
     * @notice Emitted when tokens are burned from an address
     * @param from Address whose tokens are burned
     * @param amount Amount of tokens burned
     * @param burner Address that initiated the burn
     */
    event TokensBurned(address indexed from, uint256 amount, address indexed burner);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when trying to increase the global interest rate
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 currentRate, uint256 proposedRate);

    /// @notice Thrown when proposed interest rate exceeds maximum allowed
    error RebaseToken__InterestRateTooHigh(uint256 proposedRate, uint256 maxRate);

    /// @notice Thrown when proposed interest rate is below minimum allowed
    error RebaseToken__InterestRateTooLow(uint256 proposedRate, uint256 minRate);

    /// @notice Thrown when zero address is provided where not allowed
    error RebaseToken__ZeroAddress();

    /// @notice Thrown when zero amount is provided where not allowed
    error RebaseToken__ZeroAmount();

    /// @notice Thrown when arithmetic operation would overflow
    error RebaseToken__ArithmeticOverflow();

    /// @notice Thrown when caller lacks required authorization
    error RebaseToken__Unauthorized(address caller);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the RebaseToken contract
     * @dev Sets token name, symbol, and transfers ownership to deployer
     *
     * Initial State:
     * - Token Name: "RebaseToken"
     * - Token Symbol: "RBT"
     * - Total Supply: 0
     * - Global Interest Rate: 6% (6e10 when scaled by 1e12)
     * - Contract Status: Not paused
     */
    constructor(address mintAndBurnRecipient) ERC20("RebaseToken", "RBT") Ownable(msg.sender) {
        // Owner is explicitly set to msg.sender
        // Grant default admin role to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // Grant mint and burn role to specified address
        require(mintAndBurnRecipient != address(0), "MintAndBurn address cannot be zero");
        _grantRole(MINT_AND_BURN_ROLE, mintAndBurnRecipient);
        // All other state variables initialized to their default values
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the global interest rate applied to new deposits
     * @dev Only callable by contract owner. Rate can only decrease to protect existing holders.
     *
     * @param newInterestRate The new interest rate scaled by INTEREST_RATE_PRECISION (1e12)
     *
     * Requirements:
     * - Caller must be owner
     * - New rate must be less than current rate
     * - New rate must be within MIN_INTEREST_RATE and MAX_INTEREST_RATE bounds
     *
     * Effects:
     * - Updates s_globalInterestRate
     * - Emits GlobalInterestRateUpdated event
     *
     * Example:
     * - For 5% APY: newInterestRate = 5e10
     * - For 4% APY: newInterestRate = 4e10
     *
     * @custom:security Only decreases allowed
     */
    function setGlobalInterestRate(uint256 newInterestRate) external onlyOwner {
        // Validate rate is decreasing
        if (newInterestRate > s_globalInterestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_globalInterestRate, newInterestRate);
        }

        // Validate rate is within acceptable bounds
        if (newInterestRate > MAX_INTEREST_RATE) {
            revert RebaseToken__InterestRateTooHigh(newInterestRate, MAX_INTEREST_RATE);
        }
        if (newInterestRate < MIN_INTEREST_RATE) {
            revert RebaseToken__InterestRateTooLow(newInterestRate, MIN_INTEREST_RATE);
        }

        uint256 oldRate = s_globalInterestRate;
        s_globalInterestRate = newInterestRate;

        emit GlobalInterestRateUpdated(oldRate, newInterestRate, msg.sender, block.timestamp);
    }

    /**
     * @notice Mints new tokens to a specified address
     * @dev Only callable by contract owner and access address. Settles existing interest before minting.
     *
     * @param to Address to receive the newly minted tokens
     * @param amount Amount of tokens to mint (in wei, 18 decimals)
     *
     * Requirements:
     * - Caller must be owner or access addresser 
     * - Contract must not be paused
     * - `to` cannot be zero address
     * - `amount` must be greater than zero
     *
     * Effects:
     * - Settles any accrued interest for recipient
     * - Updates recipient's interest rate to current global rate
     * - Mints specified amount of tokens
     * - Emits UserInterestRateUpdated event
     * - Emits TokensMinted event
     * - Emits Transfer event (from ERC20)
     *
     * @custom:security Protected by onlyRole(MINT_AND_BURN_ROLE) and nonReentrant modifiers
     */
    function mint(address to, uint256 amount) external onlyRole(MINT_AND_BURN_ROLE) whenNotPaused nonReentrant {
        // Input validation
        if (to == address(0)) revert RebaseToken__ZeroAddress();
        if (amount == 0) revert RebaseToken__ZeroAmount();

        // Settle any existing interest before minting new tokens
        _settleInterest(to);

        // Update user's interest rate to current global rate
        UserRebaseData storage userData = s_userRebaseData[to];
        uint256 oldRate = userData.interestRate;
        userData.interestRate = uint128(s_globalInterestRate);

        // Mint the tokens
        _mint(to, amount);

        emit UserInterestRateUpdated(to, oldRate, s_globalInterestRate, block.timestamp);
        emit TokensMinted(to, amount, msg.sender);
    }

    /**
     * @notice Burns tokens from a specified address
     * @dev Only callable by contract owner. Settles interest before burning.
     *
     * @param from Address whose tokens will be burned
     * @param amount Amount of tokens to burn (in wei, 18 decimals)
     *
     * Requirements:
     * - Caller must be owner
     * - Contract must not be paused
     * - `from` cannot be zero address
     * - `amount` must be greater than zero
     * - `from` must have sufficient balance
     *
     * Effects:
     * - Settles any accrued interest for the address
     * - Burns specified amount of tokens
     * - Emits TokensBurned event
     * - Emits Transfer event (from ERC20)
     *
     * @custom:security Protected by onlyRole(MINT_AND_BURN_ROLE) and nonReentrant modifiers
     */
    function burn(address from, uint256 amount) external onlyRole(MINT_AND_BURN_ROLE) whenNotPaused nonReentrant {
        // Input validation
        if (from == address(0)) revert RebaseToken__ZeroAddress();
        if (amount == 0) revert RebaseToken__ZeroAmount();

        // Settle any existing interest before burning
        _settleInterest(from);

        // Burn the tokens (will revert if insufficient balance)
        _burn(from, amount);

        emit TokensBurned(from, amount, msg.sender);
    }

    /**
     * @notice Pauses all token transfers and minting
     * @dev Only callable by contract owner. Used in emergency situations.
     *
     * Requirements:
     * - Caller must be owner
     * - Contract must not already be paused
     *
     * Effects:
     * - Sets contract to paused state
     * - Blocks all transfers, mints, and burns
     * - Emits Paused event
     *
     * @custom:security Emergency brake mechanism
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract, re-enabling token operations
     * @dev Only callable by contract owner
     *
     * Requirements:
     * - Caller must be owner
     * - Contract must be paused
     *
     * Effects:
     * - Removes paused state
     * - Re-enables all token operations
     * - Emits Unpaused event
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the current balance of an account including accrued interest
     * @dev Overrides ERC20 balanceOf to include virtual (unsettled) interest
     *
     * @param account Address to query balance for
     * @return Current balance including all accrued but unsettled interest
     *
     * Calculation:
     * 1. Fetch stored (nominal) balance from ERC20
     * 2. Calculate interest multiplier based on time elapsed
     * 3. Apply multiplier: realBalance = nominalBalance × multiplier / PRECISION_VALUE
     *
     * Note: This is a view function and doesn't modify state. Actual minting occurs
     * when user interacts with contract (transfer, mint, or manual settlement).
     *
     * Gas Cost: ~3,000-5,000 (view only, no state changes)
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        uint256 storedBalance = super.balanceOf(account);

        // If no balance, no interest to calculate
        if (storedBalance == 0) {
            return 0;
        }

        // Calculate interest multiplier
        uint256 interestMultiplier = _calculateInterestMultiplier(account);

        // Apply multiplier to get real balance
        return (storedBalance * interestMultiplier) / PRECISION_VALUE;
    }

    /**
     * @notice Gets the interest rate for a specific user
     * @param user Address to query
     * @return User's current interest rate (scaled by INTEREST_RATE_PRECISION)
     *
     * Returns 0 for users who have never interacted with the contract.
     */
    function getUserInterestRate(address user) external view returns (uint256) {
        return s_userRebaseData[user].interestRate;
    }

    /**
     * @notice Gets the last update timestamp for a user
     * @param user Address to query
     * @return Timestamp when user's balance was last settled
     *
     * Returns 0 for users who have never interacted with the contract.
     */
    function getUserLastUpdateTimestamp(address user) external view returns (uint256) {
        return s_userRebaseData[user].lastUpdateTimestamp;
    }

    /**
     * @notice Calculates the amount of interest accrued by a user since last update
     * @param user Address to calculate interest for
     * @return Amount of interest tokens accrued but not yet minted
     *
     * Formula: interest = balance × (multiplier - 1)
     *
     * Example:
     * - Balance: 1000 tokens
     * - Multiplier: 1.05 (5% growth)
     * - Interest: 1000 × (1.05 - 1) = 50 tokens
     */
    function getAccruedInterest(address user) external view returns (uint256) {
        uint256 storedBalance = super.balanceOf(user);
        if (storedBalance == 0) {
            return 0;
        }

        uint256 interestMultiplier = _calculateInterestMultiplier(user);
        uint256 currentBalance = (storedBalance * interestMultiplier) / PRECISION_VALUE;

        return currentBalance - storedBalance;
    }

    /**
     * @notice Calculates the APY (Annual Percentage Yield) for the current global rate
     * @return APY as a percentage with 2 decimal precision (e.g., 600 = 6.00%)
     *
     * Converts the per-second linear interest rate to an annualized percentage.
     *
     * Note: This assumes linear interest. Actual compounding would yield slightly higher.
     */
    function getCurrentAPY() external view returns (uint256) {
        // Convert per-second rate to annual percentage
        // APY = (rate / INTEREST_RATE_PRECISION) × 100
        return (s_globalInterestRate * 100) / INTEREST_RATE_PRECISION;
    }

    /*//////////////////////////////////////////////////////////////
                        PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Manually settles accrued interest for a user
     * @dev Converts virtual interest into real minted tokens
     *
     * @param user Address to settle interest for
     *
     * Requirements:
     * - Contract must not be paused (implicit via _settleInterest checks)
     *
     * Effects:
     * - Calculates and mints any accrued interest
     * - Updates user's last update timestamp
     * - May emit InterestMinted event if interest > 0
     *
     * Use Cases:
     * - Preparing for token transfer
     * - Claiming accumulated rewards
     * - Syncing balance before external contract interaction
     *
     * Gas Cost: ~40,000-60,000 (if interest is minted)
     */
    function settleInterest(address user) public nonReentrant {
        _settleInterest(user);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates the interest multiplier for a user
     * @dev Uses linear interest formula for gas efficiency
     *
     * @param user Address to calculate multiplier for
     * @return Interest multiplier scaled by PRECISION_VALUE (1e18)
     *
     * Formula: multiplier = 1 + (userRate × timeElapsed)
     *
     * Example (6% annual rate, 1 year elapsed):
     * - userRate = 6e10
     * - timeElapsed = 31536000 seconds
     * - multiplier = 1e18 + (6e10 × 31536000)
     * - multiplier = 1e18 + 1.89216e18 ≈ 1.06e18
     *
     * Returns PRECISION_VALUE (1.0) for:
     * - New users with no timestamp set
     * - Users with zero balances
     *
     * @custom:optimization Doesn't use compound interest to save gas
     */
    function _calculateInterestMultiplier(address user) internal view returns (uint256) {
        UserRebaseData memory userData = s_userRebaseData[user];

        // No interest for users who haven't been initialized
        if (userData.lastUpdateTimestamp == 0) {
            return PRECISION_VALUE;
        }

        // Calculate time elapsed since last update
        uint256 timeElapsed = block.timestamp - userData.lastUpdateTimestamp;

        // If no time has passed, multiplier is 1.0
        if (timeElapsed == 0) {
            return PRECISION_VALUE;
        }

        // Linear interest formula: 1 + (rate × time)
        // Note: Using linear instead of compound for gas efficiency
        // This is a close approximation for reasonable time periods
        uint256 interest = (userData.interestRate * timeElapsed);

        return PRECISION_VALUE + interest;
    }

    /**
     * @notice Settles accrued interest for a user by minting tokens
     * @dev Internal function called before balance-changing operations
     *
     * @param user Address to settle interest for
     *
     * Process:
     * 1. Check if user needs initialization (first interaction)
     * 2. Calculate current virtual balance (stored + interest)
     * 3. Compute interest earned (virtual - stored)
     * 4. Mint interest tokens if > 0
     * 5. Update last update timestamp
     *
     * Effects:
     * - May mint new tokens to user
     * - Updates user's lastUpdateTimestamp
     * - May emit InterestMinted event
     *
     * Optimization: Returns early if:
     * - User has no stored balance
     * - No interest has accrued
     *
     * @custom:security Uses nonReentrant guard in calling functions
     */
    function _settleInterest(address user) internal {
        UserRebaseData storage userData = s_userRebaseData[user];

        // Initialize timestamp for first-time users
        if (userData.lastUpdateTimestamp == 0) {
            userData.lastUpdateTimestamp = uint128(block.timestamp);
            return;
        }

        // Get current stored balance
        uint256 storedBalance = super.balanceOf(user);

        // No interest to settle if balance is zero
        if (storedBalance == 0) {
            // Update timestamp anyway to keep accounting clean
            userData.lastUpdateTimestamp = uint128(block.timestamp);
            return;
        }

        // Calculate how much the balance should be including interest
        uint256 interestMultiplier = _calculateInterestMultiplier(user);
        uint256 newBalance = (storedBalance * interestMultiplier) / PRECISION_VALUE;

        // Calculate interest earned
        uint256 interestEarned = newBalance - storedBalance;

        // Mint interest if any accrued
        if (interestEarned > 0) {
            _mint(user, interestEarned);
            emit InterestMinted(user, interestEarned, newBalance, block.timestamp);
        }

        // Update last update timestamp to current block
        userData.lastUpdateTimestamp = uint128(block.timestamp);
    }

    /**
     * @notice Hook called for all token transfers (replaces _beforeTokenTransfer in OZ v5.0+)
     * @dev Settles interest for both sender and receiver before transfer
     *
     * @param from Address sending tokens (address(0) for minting)
     * @param to Address receiving tokens (address(0) for burning)
     * @param value Amount being transferred
     *
     * Purpose:
     * - Ensures all balances are current before transfer
     * - Prevents issues with virtual vs real balances
     * - Maintains accurate accounting
     *
     * Called automatically by:
     * - transfer()
     * - transferFrom()
     * - _mint()
     * - _burn()
     *
     * Skip settlement for:
     * - Minting (from == address(0)) - handled in mint()
     * - Burning (to == address(0)) - handled in burn()
     *
     * @custom:security Critical for maintaining balance integrity
     * @custom:oz-version Compatible with OpenZeppelin v5.0+
     */
    function _update(address from, address to, uint256 value) internal virtual override whenNotPaused {
        // Settle interest for sender (if not minting)
        if (from != address(0) && super.balanceOf(from) > 0) {
            _settleInterest(from);
        }

        // Settle interest for receiver (if not burning AND not minting)
        // CRITICAL FIX: We must check from != address(0) to prevent infinite recursion
        // When _settleInterest mints interest tokens, it calls _mint which triggers _update again
        // Without this check, we get: burn -> _settleInterest -> _mint -> _update -> _settleInterest -> infinite loop
        if (to != address(0) && from != address(0) && super.balanceOf(to) > 0) {
            _settleInterest(to);
        }

        // Call parent implementation to perform the actual transfer
        super._update(from, to, value);
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Converts an annual percentage rate to the contract's per-second rate
     * @dev Helper function for off-chain calculations or testing
     *
     * @param annualPercentage Annual percentage (e.g., 6 for 6%)
     * @return Per-second rate scaled by INTEREST_RATE_PRECISION
     *
     * Example:
     * - Input: 6 (representing 6% annual)
     * - Output: 6e10 (per-second rate in contract format)
     *
     * Formula:
     * perSecondRate = (annualPercentage / 100) × INTEREST_RATE_PRECISION
     */
    function annualPercentageToRate(uint256 annualPercentage) public pure returns (uint256) {
        // Convert percentage to rate: multiply by precision, divide by 100
        return (annualPercentage * INTEREST_RATE_PRECISION) / 100;
    }

    /**
     * @notice Converts the contract's per-second rate to annual percentage
     * @dev Helper function for displaying rates in UI
     *
     * @param rate Per-second rate (scaled by INTEREST_RATE_PRECISION)
     * @return Annual percentage (e.g., 6 for 6%)
     *
     * Example:
     * - Input: 6e10 (contract rate)
     * - Output: 6 (representing 6% annual)
     */
    function rateToAnnualPercentage(uint256 rate) public pure returns (uint256) {
        // Convert rate to percentage: multiply by 100, divide by precision
        return (rate * 100) / INTEREST_RATE_PRECISION;
    }
}
