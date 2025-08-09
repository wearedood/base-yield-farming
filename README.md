# Base Yield Farming Protocol

Advanced yield farming protocol built specifically for Base blockchain with multi-token rewards, boost mechanics, and liquidity mining capabilities.

## Features

🚀 **Multi-Token Rewards**: Support for primary and bonus token rewards
⚡ **Boost Mechanics**: Dynamic multipliers based on user activity and holdings
🔒 **Lock Periods**: Configurable lock periods for different pools
💰 **Deposit Fees**: Customizable deposit fees for sustainability
🎯 **Pool Management**: Flexible pool allocation and management system

## Smart Contracts

- `BaseYieldFarm.sol` - Main yield farming contract
- `BoostContract.sol` - Boost multiplier calculation contract
- `RewardToken.sol` - Primary reward token contract

## Base Blockchain Integration

This protocol is optimized for Base blockchain, leveraging:
- Low transaction costs for frequent reward claims
- Fast block times for responsive farming
- Base ecosystem token compatibility
- Seamless integration with Base DeFi protocols

## Getting Started

1. Deploy the BaseYieldFarm contract
2. Add liquidity pools with allocation points
3. Set reward rates and boost parameters
4. Users can deposit LP tokens to earn rewards

## Architecture

The protocol uses a pool-based system where:
- Each pool has its own LP token and allocation points
- Rewards are distributed proportionally based on allocation
- Users earn boosted rewards based on their multiplier
- Lock periods prevent immediate withdrawals

## Security Features

- ReentrancyGuard protection
- Pausable functionality for emergencies
- Owner-only administrative functions
- Safe token transfer mechanisms

## Deployment

Ready for deployment on Base Mainnet with full verification on Basescan for maximum Builder Rewards recognition.

---

Built for Base Builder Rewards Summer League 🏆
