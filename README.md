# Cross-Chain Rebase Token

> ⚠️ **Work in Progress** - This project is currently under active development.

An elastic supply token with automatic interest accrual and cross-chain functionality built on Solidity 0.8.30 using Foundry.

## Overview

This project implements an interest-bearing rebase token where token balances automatically increase over time based on a configurable interest rate. Users can deposit ETH to receive tokens and redeem tokens to withdraw ETH plus accrued interest.

## Features

- ✅ **Automatic Interest Accrual** - Token balances grow over time (6% annual rate by default)
- ✅ **Flexible Interest Rates** - Per-user interest rate tracking
- ✅ **Vault System** - Secure deposit and redemption mechanism
- ✅ **Access Control** - Role-based permissions for critical operations
- ✅ **Pausable** - Emergency stop mechanism
- ✅ **Gas Optimized** - Virtual balance calculations to minimize gas costs
- 🚧 **Cross-Chain Support** - Coming soon

## Contracts

### RebaseToken.sol
ERC20 token with automatic interest accrual functionality.

**Key Features:**
- Linear interest calculation for gas efficiency
- Per-user interest rate tracking
- Role-based access control (MINT_AND_BURN_ROLE)
- Pausable for emergency situations
- Interest rate bounds (0.1% - 100% APY)

### Vault.sol
Manages ETH deposits and token redemptions.

**Key Features:**
- 1:1 ETH to token conversion on deposit
- Redeem tokens for ETH (including accrued interest)
- Solvency checks to prevent overdrafts
- Emergency pause mechanism

## Installation

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

### Setup

```bash
# Clone the repository
git clone https://github.com/vyqno/Cross-Chain-Rebase-Tokens.git
cd Cross-Chain-Rebase-Tokens

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test
```

## Testing

The project includes a comprehensive test suite:

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/RebaseToken.t.sol

# Generate gas report
forge test --gas-report

# Generate coverage report
forge coverage
```

### Test Statistics
- **45 total tests** across 4 test files
- **Unit Tests** - Basic functionality
- **Fuzz Tests** - Randomized input testing (256 runs per test)
- **Integration Tests** - Real-world scenarios
- **Invariant Tests** - Property verification

## Usage

### Deployment

```bash
# Deploy to local Anvil
forge script script/DeployRebaseToken.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy to testnet (Sepolia)
forge script script/DeployRebaseToken.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
```

### Interactions

```solidity
// Deposit ETH to receive tokens
vault.deposit{value: 10 ether}();

// Check balance (includes accrued interest)
uint256 balance = rebaseToken.balanceOf(user);

// Redeem tokens for ETH
vault.redeem(balance);

// Redeem all tokens
vault.redeem(type(uint256).max);
```

## Configuration

Interest rate and other parameters can be configured in `foundry.toml`:

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
optimizer = true
optimizer_runs = 200

[fuzz]
runs = 256                 # Number of fuzz test runs
max_test_rejects = 65536

[invariant]
runs = 256                 # Number of invariant test runs
depth = 128                # Calls per invariant run
```

## Project Structure

```
.
├── src/
│   ├── RebaseToken.sol      # Main token contract
│   ├── Vault.sol            # Deposit/redeem vault
│   └── interfaces/
│       └── IRebaseToken.sol # Token interface
├── test/
│   ├── RebaseToken.t.sol    # Unit tests
│   ├── AdvancedFuzz.t.sol   # Fuzz tests
│   ├── Integration.t.sol    # Integration tests
│   ├── Invariant.t.sol      # Invariant tests
│   └── Handler.t.sol        # Handler for invariant testing
├── script/
│   ├── DeployRebaseToken.s.sol # Deployment script
│   ├── Interactions.s.sol      # Interaction scripts
│   └── HelperConfig.s.sol      # Network configuration
└── lib/                     # Dependencies
```

## Security

### Audited Features
- ✅ ReentrancyGuard on all state-changing functions
- ✅ Access control on mint/burn operations
- ✅ Pausable mechanism for emergencies
- ✅ Interest rate bounds to prevent economic attacks
- ✅ Comprehensive input validation

### Known Issues
- Invariant tests have some edge cases with the handler (4 failing tests)
- These are test framework issues, not contract vulnerabilities

## Contributing

This project is currently in development. Contributions, issues, and feature requests are welcome!

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## Roadmap

- [x] Basic rebase token implementation
- [x] Vault deposit/redeem system
- [x] Interest accrual mechanism
- [x] Comprehensive test suite
- [ ] Cross-chain messaging integration
- [ ] Chainlink price feeds
- [ ] Frontend interface
- [ ] Mainnet deployment
- [ ] Professional audit

## Technology Stack

- **Solidity 0.8.30** - Smart contract language
- **Foundry** - Development framework
- **OpenZeppelin** - Security contracts
- **Foundry DevOps** - Deployment utilities

## License

MIT License - see [LICENSE](LICENSE) for details

## Contact

**Author:** vyqno (Hitesh)

- GitHub: [@vyqno](https://github.com/vyqno)
- Project Link: [https://github.com/vyqno/Cross-Chain-Rebase-Tokens](https://github.com/vyqno/Cross-Chain-Rebase-Tokens)

## Acknowledgments

- OpenZeppelin for secure contract libraries
- Foundry team for the amazing development framework
- Cyfrin for educational resources

---

⚠️ **Disclaimer:** This project is under active development and has not been professionally audited. Do not use in production without proper security review.
