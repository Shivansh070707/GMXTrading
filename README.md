# GMX Trading Platform Contracts

=====================================

## Overview

---

This repository contains the smart contracts for the GMX Trading Platform, a decentralized trading platform built on the Arbitrum network. The platform allows users to create accounts, transfer margin, open and close positions, cancel orders, and claim performance fees.

## Contracts

---

The platform consists of three main contracts:

- **GMXTrading**: The main entry point for the trading platform, responsible for managing user accounts, whitelists, and supported assets.
- **UserAccount**: Represents a user's account on the trading platform, allowing users to open and close positions, cancel orders, and receive performance fees.
- **Vault**: Responsible for managing users' balances and transferring funds between users and the trading platform.

## Installation

---

To install the contracts, follow these steps:

1. Clone the repository: `git clone https://github.com/Shivansh070707/GMXTrading.git`
2. Install dependencies: `npm install`
3. Test the contracts: `npx hardhat test`


### GMXTrading

- `createAccount()`: Creates a new user account
- `transferMargin(uint256 amount)`: Transfers margin to the user's account
- `openPosition(address indexToken, uint256 amountIn, uint256 sizeDelta, bool isLong, uint256 acceptablePrice, uint256 executionFee)`: Opens a new position
- `closePosition(address indexToken, uint256 amountIn, uint256 sizeDelta, bool isLong, uint256 acceptablePrice, uint256 executionFee)`: Closes an existing position
- `cancelOrder(bytes32 orderId)`: Cancels an order
- `claimPerformanceFees()`: Claims performance fees for the user

### UserAccount

- `openPosition(address indexToken, uint256 amountIn, uint256 sizeDelta, uint256 minOut, bool isLong, uint256 acceptablePrice, uint256 executionFee)`: Opens a new position
- `closePosition(address indexToken, uint256 collateralDelta, uint256 sizeDelta, uint256 minOut, bool isLong, uint256 acceptablePrice, uint256 executionFee)`: Closes an existing position
- `cancelOrder(bytes32 orderId)`: Cancels an order
- `gmxPositionCallback(bytes32 positionKey, bool isExecuted, bool isIncrease)`: Callback function for GMX position updates

### Vault

- `deposit(address user, uint256 amount)`: Deposits funds into the user's account
- `withdraw(address user, uint256 amount)`: Withdraws funds from the user's account
- `transferToUserAccount(address user, address userAccount, uint256 amount)`: Transfers funds to the user's account
- `getBalance(address user)`: Returns the user's balance
