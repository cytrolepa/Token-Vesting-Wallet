# 🔒 Token Vesting Wallet

A smart contract for token vesting on the Stacks blockchain with linear vesting mechanics.

## ✨ Features

🕒 **Linear Vesting** - Tokens vest gradually over time  
⏰ **Cliff Periods** - Optional delay before vesting begins  
👨‍💼 **Admin Controls** - Create, update, and revoke vesting schedules  
💰 **Automatic Claiming** - Beneficiaries can claim vested tokens anytime  
🔄 **Batch Operations** - Create multiple schedules at once  
🛡️ **Security** - Owner-only administrative functions  

## 🚀 Quick Start

### Deploy the Contract
```bash
clarinet deploy
```

### Create a Vesting Schedule
```clarity
(contract-call? .token-vesting-wallet create-vesting-schedule
  'SP1ABC...  ;; beneficiary
  u1000000    ;; total amount (1M microSTX)
  u1640995200 ;; start time (Unix timestamp)
  u2592000    ;; cliff duration (30 days in seconds)
  u31536000   ;; vesting duration (1 year in seconds)
)
```

### Check Vesting Status
```clarity
(contract-call? .token-vesting-wallet get-schedule-info 'SP1ABC...)
```

### Claim Vested Tokens
```clarity
(contract-call? .token-vesting-wallet claim-tokens)
```

## 📋 Core Functions

### 👑 Admin Functions

#### `create-vesting-schedule`
Creates a new vesting schedule for a beneficiary.
- **beneficiary**: Principal to receive vested tokens
- **total-amount**: Total tokens to vest (in microSTX)
- **start-time**: When vesting begins (Unix timestamp)
- **cliff-duration**: Delay before any vesting (seconds)
- **vesting-duration**: Total vesting period (seconds)

#### `revoke-vesting-schedule`
Revokes an active vesting schedule, paying out vested tokens and returning unvested tokens.

#### `update-vesting-schedule`
Modifies an existing schedule's total amount or duration.

#### `deposit-tokens`
Deposits STX into the contract to fund vesting schedules.

### 🏦 Beneficiary Functions

#### `claim-tokens`
Claims all currently vested and unclaimed tokens.

### 📊 Read-Only Functions

#### `get-schedule-info`
Returns complete vesting information for a beneficiary.

#### `get-claimable-amount`
Returns how many tokens can be claimed right now.

#### `calculate-vested-amount`
Returns total vested tokens (including already claimed).

#### `is-fully-vested`
Checks if vesting is complete.

## 🔧 Usage Examples

### Example 1: Employee Token Vesting
```clarity
;; 4-year vesting with 1-year cliff
(contract-call? .token-vesting-wallet create-vesting-schedule
  'SP1EMPLOYEE123
  u4000000      ;; 4M tokens
  u1672531200   ;; Jan 1, 2023
  u31536000     ;; 1 year cliff
  u126144000    ;; 4 year total vesting
)
```

### Example 2: Advisor Vesting
```clarity
;; 2-year vesting with 6-month cliff
(contract-call? .token-vesting-wallet create-vesting-schedule
  'SP1ADVISOR456
  u500000       ;; 500K tokens
  u1672531200   ;; Jan 1, 2023
  u15552000     ;; 6 month cliff
  u63072000     ;; 2 year total vesting
)
```

### Example 3: Batch Schedule Creation
```clarity
(contract-call? .token-vesting-wallet batch-create-schedules
  (list
    { beneficiary: 'SP1ABC, amount: u1000000, start-time: u1672531200, cliff-duration: u2592000, duration: u31536000 }
    { beneficiary: 'SP1DEF, amount: u2000000, start-time: u1672531200, cliff-duration: u7776000, duration: u63072000 }
  )
)
```

## 🧮 Vesting Calculation

The contract uses **linear vesting**:
```
vested_amount = (total_amount * elapsed_time) / total_duration
```

Where:
- `elapsed_time` = current time - start time (after cliff)
- Tokens vest continuously every second
- No tokens vest before cliff period ends

## 🛠️ Development

### Test the Contract
```bash
clarinet test
```

### Console Testing
```bash
clarinet console
```

## 📖 Contract Architecture

The contract maintains two main data structures:
- **vesting-schedules**: Core vesting parameters per beneficiary
- **vesting-balances**: Token balances for gas optimization

## 🔐 Security Features

- ✅ Owner-only administrative functions
- ✅ Beneficiary validation (can't create schedule for self)
- ✅ Schedule existence checks
- ✅ Amount validation (no zero amounts)
- ✅ Time-based access controls
- ✅ Emergency withdrawal for contract owner

## 📝 License

MIT License
