# 🎬 Royalties Streaming per View

A Clarity smart contract that enables **instant micropayment streaming** to movie contributors (writers, actors, editors) every time their movie NFT is viewed! 🚀

## ✨ Features

- 🎥 **Movie NFT Minting**: Create unique NFTs for movies with custom pricing
- 👥 **Multi-Contributor Support**: Add writers, actors, editors with custom royalty percentages  
- 💰 **Instant Streaming Payments**: Automatic micropayments distributed per view
- 📊 **Revenue Tracking**: Real-time view counts and earnings analytics
- 🔄 **Batch Operations**: Efficient bulk contributor management
- ⚡ **Low Platform Fees**: Only 2.5% platform fee (adjustable by contract owner)

## 🚀 Quick Start

### Prerequisites
- Clarinet installed
- STX wallet with testnet tokens

### Installation

```bash
git clone <repo-url>
cd Royalties-Streaming-per-View
clarinet check
```

## 📖 Usage

### 1. Mint a Movie NFT 🎬

```clarity
(contract-call? .Royalties-Streaming-per-veiw mint-movie "The Matrix" u1000000 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

### 2. Add Contributors 👨‍🎭

```clarity
;; Add a single contributor
(contract-call? .Royalties-Streaming-per-veiw add-contributor u1 'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG "actor" u3000)

;; Bulk add contributors (up to 10 at once)
(contract-call? .Royalties-Streaming-per-veiw bulk-add-contributors u1 
    (list 
        {contributor: 'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG, role: "writer", percentage: u4000}
        {contributor: 'ST2JHG361ZXG51QTKY2NQCVBPPRRE2KZB1HR05NNC, role: "director", percentage: u3000}
    )
)
```

### 3. Stream a View 📺

```clarity
;; Watch a movie and trigger instant royalty payments
(contract-call? .Royalties-Streaming-per-veiw stream-view u1)
```

### 4. Check Earnings 💵

```clarity
;; Check your earnings
(contract-call? .Royalties-Streaming-per-veiw get-contributor-earnings 'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG)

;; Withdraw earnings
(contract-call? .Royalties-Streaming-per-veiw withdraw-earnings)
```

### 5. Movie Analytics 📈

```clarity
;; Get movie statistics
(contract-call? .Royalties-Streaming-per-veiw get-movie-stats u1)

;; Get movie revenue
(contract-call? .Royalties-Streaming-per-veiw get-movie-revenue u1)
```

## 🏗️ Contract Functions

### Public Functions

| Function | Description | Access |
|----------|-------------|--------|
| `mint-movie` | 🎬 Create a new movie NFT | Contract Owner |
| `add-contributor` | 👥 Add single contributor to movie | Movie Creator |
| `bulk-add-contributors` | 👥 Add multiple contributors at once | Movie Creator |
| `stream-view` | 📺 Watch movie and trigger payments | Anyone |
| `withdraw-earnings` | 💰 Withdraw accumulated earnings | Contributors |
| `update-platform-fee` | ⚙️ Update platform fee percentage | Contract Owner |
| `update-movie-price` | 💲 Change movie viewing price | Movie Creator |
| `transfer` | 🔄 Transfer movie NFT ownership | NFT Owner |

### Read-Only Functions

| Function | Description |
|----------|-------------|
| `get-movie-details` | 📋 Get movie information |
| `get-movie-stats` | 📊 Get comprehensive movie statistics |
| `get-contributor-details` | 👤 Get contributor information |
| `get-contributor-earnings` | 💵 Check earnings for address |
| `get-movie-contributors` | 👥 List all movie contributors |
| `get-view-details` | 📺 Get specific view transaction details |

## 🔧 Configuration

- **Platform Fee**: 2.5% (250 basis points) - adjustable by contract owner
- **Max Contributors**: 20 per movie
- **Percentage Precision**: 10000 basis points (100.00%)

## 🎯 Example Workflow

1. **🎬 Create Movie**: Owner mints "Inception" NFT for $10 per view
2. **👥 Add Team**: Creator adds director (30%), writer (25%), actors (20% each)  
3. **📺 User Views**: Viewer pays $10, triggers instant distribution:
   - Platform: $0.25 (2.5%)
   - Director: $2.93 (30% of remaining)
   - Writer: $2.44 (25% of remaining)  
   - Actor 1: $1.95 (20% of remaining)
   - Actor 2: $1.95 (20% of remaining)
4. **💰 Withdrawal**: Contributors withdraw earnings anytime

## 🛡️ Security Features

- ✅ Owner-only minting controls
- ✅ Creator-only contributor management
- ✅ Automatic payment distribution
- ✅ Earnings isolation per contributor
- ✅ Percentage validation (max 100%)

## 🧪 Testing

```bash
clarinet test
```

## 📄 License

MIT License - Build amazing things! 🚀
