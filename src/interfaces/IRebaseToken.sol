// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title  IRebaseToken
 * @notice Interface for the RebaseToken contract - an interest-bearing elastic supply token
 * @dev    Extends IERC20 with rebase-specific functionality for automatic interest accrual
 */
interface IRebaseToken is IERC20 {
    /*//////////////////////////////////////////////////////////////
                            TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Stores user-specific rebase data
     * @param lastUpdateTimestamp When the user's balance was last settled
     * @param interestRate The interest rate applicable to this user
     */
    struct UserRebaseData {
        uint128 lastUpdateTimestamp;
        uint128 interestRate;
    }

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

    /// @notice Thrown when trying to decrease the global interest rate
    error RebaseToken__InterestRateCanOnlyIncrease(uint256 currentRate, uint256 proposedRate);

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
                        EXTERNAL ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the global interest rate applied to new deposits
     * @param newInterestRate The new interest rate scaled by INTEREST_RATE_PRECISION (1e12)
     */
    function setGlobalInterestRate(uint256 newInterestRate) external;

    /**
     * @notice Mints new tokens to a specified address
     * @param to Address to receive the newly minted tokens
     * @param amount Amount of tokens to mint (in wei, 18 decimals)
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burns tokens from a specified address
     * @param from Address whose tokens will be burned
     * @param amount Amount of tokens to burn (in wei, 18 decimals)
     */
    function burn(address from, uint256 amount) external;

    /**
     * @notice Pauses all token transfers and minting
     */
    function pause() external;

    /**
     * @notice Unpauses the contract, re-enabling token operations
     */
    function unpause() external;

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the interest rate for a specific user
     * @param user Address to query
     * @return User's current interest rate (scaled by INTEREST_RATE_PRECISION)
     */
    function getUserInterestRate(address user) external view returns (uint256);

    /**
     * @notice Gets the last update timestamp for a user
     * @param user Address to query
     * @return Timestamp when user's balance was last settled
     */
    function getUserLastUpdateTimestamp(address user) external view returns (uint256);

    /**
     * @notice Calculates the amount of interest accrued by a user since last update
     * @param user Address to calculate interest for
     * @return Amount of interest tokens accrued but not yet minted
     */
    function getAccruedInterest(address user) external view returns (uint256);

    /**
     * @notice Calculates the APY (Annual Percentage Yield) for the current global rate
     * @return APY as a percentage with 2 decimal precision (e.g., 600 = 6.00%)
     */
    function getCurrentAPY() external view returns (uint256);

    /**
     * @notice Returns the current global interest rate
     * @return Global interest rate scaled by INTEREST_RATE_PRECISION
     */
    function s_globalInterestRate() external view returns (uint256);

    /**
     * @notice Maximum allowed interest rate (100% APY)
     * @return Maximum interest rate constant
     */
    function MAX_INTEREST_RATE() external view returns (uint256);

    /**
     * @notice Minimum allowed interest rate (0.1% APY)
     * @return Minimum interest rate constant
     */
    function MIN_INTEREST_RATE() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                        PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Manually settles accrued interest for a user
     * @param user Address to settle interest for
     */
    function settleInterest(address user) external;

    /**
     * @notice Converts an annual percentage rate to the contract's per-second rate
     * @param annualPercentage Annual percentage (e.g., 6 for 6%)
     * @return Per-second rate scaled by INTEREST_RATE_PRECISION
     */
    function annualPercentageToRate(uint256 annualPercentage) external pure returns (uint256);

    /**
     * @notice Converts the contract's per-second rate to annual percentage
     * @param rate Per-second rate (scaled by INTEREST_RATE_PRECISION)
     * @return Annual percentage (e.g., 6 for 6%)
     */
    function rateToAnnualPercentage(uint256 rate) external pure returns (uint256);
}
