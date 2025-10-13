# 🔐 Solana Wallet Setup and Verification Guide

## Overview

This guide covers the complete setup and verification of a Solana wallet for the MojoRust Trading Bot. The bot requires a securely configured Solana keypair at `~/.config/solana/id.json` with proper permissions to operate safely and efficiently.

## Wallet Verification Checklist

### ✅ File Existence Check
- [ ] Wallet file exists at `~/.config/solana/id.json`
- [ ] File is readable by the current user
- [ ] File is not empty and contains valid data

### ✅ Permission Security Check
- [ ] File permissions are set to **600** (owner read/write only)
- [ ] No group or other users have access
- [ ] File owned by the correct user

### ✅ Format Validation Check
- [ ] Content is valid JSON format
- [ ] Content is an array structure
- [ ] Array contains exactly **64 numbers** (Solana keypair format)
- [ ] All elements are integers between 0-255

### ✅ Public Key Extraction Check
- [ ] Public key successfully extracted from keypair (first 32 bytes)
- [ ] Public key displayed in base58 format
- [ ] Public key matches `WALLET_ADDRESS` environment variable (if set)

### ✅ Network Connectivity Check
- [ ] Solana RPC endpoint connection successful
- [ ] Wallet balance query completed (if Solana CLI available)
- [ ] Wallet is valid and recognized on the network

### ✅ Environment Integration Check
- [ ] `WALLET_ADDRESS` environment variable is set
- [ ] Address matches keypair public key
- [ ] `WALLET_PRIVATE_KEY_PATH` works if using custom path

## Wallet Creation Steps

### Option 1: Generate New Wallet (Recommended for Testing)
```bash
# Create Solana config directory
mkdir -p ~/.config/solana

# Generate new keypair
solana-keygen new --no-bip39-passphrase --silent

# Save the output to the correct location
# Copy the JSON array from the output and save it:
nano ~/.config/solana/id.json

# Set secure permissions
chmod 600 ~/.config/solana/id.json

# Extract and save the public key for reference
solana-keygen pubkey ~/.config/solana/id.json > ~/.config/solana/address.txt
echo "Your public address: $(cat ~/.config/solana/address.txt)"
```

### Option 2: Import Existing Wallet
```bash
# Create Solana config directory if it doesn't exist
mkdir -p ~/.config/solana

# Import from existing keypair file
solana-keygen pubkey <path-to-existing-keypair.json> > ~/.config/solana/address.txt
cp <path-to-existing-keypair.json> ~/.config/solana/id.json

# Set secure permissions
chmod 600 ~/.config/solana/id.json

echo "Imported wallet with address: $(cat ~/.config/solana/address.txt)"
```

### Option 3: Generate from Seed Phrase
```bash
# Create config directory
mkdir -p ~/.config/solana

# Generate keypair from seed (be careful with seed phrase security)
solana-keygen recover "prompt:" --no-bip39-passphrase

# Save to correct location when prompted
# The process will save to ~/.config/solana/id.json automatically

# Set secure permissions
chmod 600 ~/.config/solana/id.json
```

## Security Best Practices

### 🔐 File Security
- **Never commit wallet files to version control**
- Add `~/.config/solana/` to `.gitignore`
- Use `chmod 600` on all wallet files
- Backup wallet files to encrypted storage

### 🔐 Production Security
- **Use hardware wallets for production** (Ledger, Trezor)
- Implement multi-signature wallets for large amounts
- Use dedicated machines for wallet operations
- Regular security audits of wallet access

### 🔐 Operational Security
- **Monitor wallet activity regularly**
- Set up alerts for unauthorized transactions
- Use rate limiting on API access
- Implement IP whitelisting for sensitive operations

### 🔐 Backup Strategy
```bash
# Create encrypted backup
gpg -c --cipher-algo AES256 ~/.config/solana/id.json > ~/backups/solana-wallet-$(date +%Y%m%d).gpg

# Create offline backup (USB drive, air-gapped system)
# Store multiple copies in different secure locations

# Document backup recovery process
echo "Wallet backup instructions:"
echo "1. Decrypt: gpg -d solana-wallet-YYYYMMDD.gpg > ~/.config/solana/id.json"
echo "2. Set permissions: chmod 600 ~/.config/solana/id.json"
echo "3. Verify: solana-keygen pubkey ~/.config/solana/id.json"
```

## Wallet Verification Commands

### Basic File Checks
```bash
# Check if wallet file exists
ls -la ~/.config/solana/id.json
# Expected: -rw------- 1 user user 2048 Dec 1 12:00 id.json

# Verify permissions (should show 600)
stat -c "%a" ~/.config/solana/id.json
# Expected: 600

# Check file size (should be reasonable, not empty)
wc -c ~/.config/solana/id.json
# Expected: around 100-200 bytes for JSON array
```

### Content Validation
```bash
# Check JSON format
python3 -c "
import json
import sys
try:
    with open('~/.config/solana/id.json', 'r') as f:
        data = json.load(f)
    if isinstance(data, list) and len(data) == 64:
        print('✅ Valid keypair format: 64 elements')
        print(f'First element: {data[0]} (0-255)')
        print(f'Last element: {data[63]} (0-255)')
    else:
        print('❌ Invalid format: expected array of 64 elements')
        sys.exit(1)
except Exception as e:
    print(f'❌ JSON error: {e}')
    sys.exit(1)
"
```

### Public Key Extraction
```bash
# Extract and display public key (requires Solana CLI)
if command -v solana >/dev/null 2>&1; then
    echo "🔑 Public Key:"
    solana-keygen pubkey ~/.config/solana/id.json

    echo ""
    echo "📊 Wallet Balance:"
    solana balance ~/.config/solana/id.json
else
    echo "❌ Solana CLI not installed. Install with:"
    echo "sh -c \"\$(curl -sSfL https://release.solana.com/v1.36/install)\""
fi
```

### Network Connectivity Test
```bash
# Test connection to Solana network
echo "🌐 Testing Solana network connectivity..."

# Test against mainnet-beta RPC
curl -s -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' \
    https://api.mainnet-beta.solana.com | jq -r '.result // "Connection failed"'

# Test cluster health
solana cluster-version 2>/dev/null || echo "Solana CLI not available for cluster check"
```

## Integration with Trading Bot

### Default Configuration
The trading bot automatically reads the wallet from the standard Solana location:
- **Default path**: `~/.config/solana/id.json`
- **Environment override**: `WALLET_PRIVATE_KEY_PATH`
- **Public key**: Must be set in `WALLET_ADDRESS` environment variable

### Environment Variable Setup
```bash
# Extract public key and set environment variable
if [ -f ~/.config/solana/id.json ]; then
    PUBLIC_KEY=$(solana-keygen pubkey ~/.config/solana/id.json 2>/dev/null)
    if [ -n "$PUBLIC_KEY" ]; then
        echo "export WALLET_ADDRESS=$PUBLIC_KEY" >> ~/.bashrc
        echo "✅ WALLET_ADDRESS set to: $PUBLIC_KEY"
    fi
fi

# Reload environment
source ~/.bashrc
```

### .env Configuration
```bash
# Add to your .env file
WALLET_ADDRESS=$(solana-keygen pubkey ~/.config/solana/id.json)
# or manually: WALLET_ADDRESS=YourPublicKeyHere

# Custom wallet path (if not using default)
# WALLET_PRIVATE_KEY_PATH=/path/to/your/wallet.json
```

## Bot Wallet Validation
When the trading bot starts, it performs these wallet validation steps:
1. Checks wallet file exists and is readable
2. Validates JSON format and structure
3. Extracts public key from keypair
4. Verifies public key matches `WALLET_ADDRESS` environment variable
5. Tests wallet connectivity to Solana network
6. Queries initial balance for portfolio initialization

## Troubleshooting

### Issue: "Permission denied" errors
**Symptoms**: Bot fails to read wallet file
**Solutions**:
```bash
# Fix permissions
chmod 600 ~/.config/solana/id.json

# Check ownership
ls -la ~/.config/solana/id.json

# Fix ownership if needed
sudo chown $USER:$USER ~/.config/solana/id.json
```

### Issue: "Invalid format" errors
**Symptoms**: Bot reports wallet JSON format issues
**Solutions**:
```bash
# Validate JSON format
python3 -m json.tool ~/.config/solana/id.json > /dev/null

# Check content structure
head -20 ~/.config/solana/id.json
# Should start with [ and end with ]

# Recreate wallet if corrupted
rm ~/.config/solana/id.json
solana-keygen new --no-bip39-passphrase --silent
# Save output as described above
```

### Issue: "Connection errors"
**Symptoms**: Bot cannot connect to Solana network
**Solutions**:
```bash
# Test network connectivity
ping 8.8.8.8

# Check DNS resolution
nslookup api.mainnet-beta.solana.com

# Test RPC endpoint manually
curl -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' \
    https://api.mainnet-beta.solana.com

# Try alternative RPC endpoints
# https://api.devnet.solana.com (for testing)
# https://api.testnet.solana.com (for testing)
```

### Issue: "Balance issues"
**Symptoms**: Bot reports zero balance or balance errors
**Solutions**:
```bash
# Check actual balance
solana balance ~/.config/solana/id.json

# Check network (might be on wrong network)
solana config get
# Should show mainnet-beta for production

# Add test funds if needed (for testing)
solana airdrop 2 ~/.config/solana/id.json
```

### Issue: "Multiple wallets"
**Symptoms**: Bot picks wrong wallet or gets confused
**Solutions**:
```bash
# Check for multiple wallet files
find ~/.config/solana -name "*.json" -type f

# Ensure only id.json exists
ls -la ~/.config/solana/

# Remove or rename extra wallets
mv ~/.config/solana/backup_wallet.json ~/.config/solana/backup_wallet.json.bak
```

## Advanced Configuration

### Custom Wallet Path
```bash
# Set custom wallet location
export WALLET_PRIVATE_KEY_PATH=/secure/path/to/wallet.json

# Update bot configuration to use custom path
echo "WALLET_PRIVATE_KEY_PATH=/secure/path/to/wallet.json" >> .env
```

### Multiple Wallet Support
```bash
# Create separate wallets for different environments
cp ~/.config/solana/id.json ~/.config/solana/paper_wallet.json
cp ~/.config/solana/id.json ~/.config/solana/live_wallet.json

# Switch between wallets
export WALLET_PRIVATE_KEY_PATH=~/.config/solana/paper_wallet.json  # For testing
export WALLET_PRIVATE_KEY_PATH=~/.config/solana/live_wallet.json   # For production
```

### Hardware Wallet Integration
```bash
# Connect Ledger wallet
solana config set --keypair usb://ledger

# Connect Trezor wallet
solana config set --keypair usb://trezor

# Export keypair to file (be careful with this)
solana config get keypair > ~/.config/solana/hardware_wallet.json
chmod 600 ~/.config/solana/hardware_wallet.json
```

## Verification Scripts

### Complete Wallet Verification
```bash
#!/bin/bash
# Complete wallet verification script
echo "🔐 Solana Wallet Verification"
echo "=========================="

WALLET_PATH="$HOME/.config/solana/id.json"

# Check file exists
if [ ! -f "$WALLET_PATH" ]; then
    echo "❌ Wallet file not found: $WALLET_PATH"
    exit 1
fi
echo "✅ Wallet file found: $WALLET_PATH"

# Check permissions
PERMS=$(stat -c "%a" "$WALLET_PATH")
if [ "$PERMS" != "600" ]; then
    echo "⚠️  Permissions not secure: $PERMS (should be 600)"
    echo "   Fixing permissions..."
    chmod 600 "$WALLET_PATH"
else
    echo "✅ Permissions secure: 600"
fi

# Check format
if python3 -c "import json; json.load(open('$WALLET_PATH'))" 2>/dev/null; then
    echo "✅ Valid JSON format"
else
    echo "❌ Invalid JSON format"
    exit 1
fi

# Check public key extraction
if command -v solana-keygen >/dev/null 2>&1; then
    PUBKEY=$(solana-keygen pubkey "$WALLET_PATH" 2>/dev/null)
    if [ -n "$PUBKEY" ]; then
        echo "✅ Public key extracted: $PUBKEY"

        # Check balance
        BALANCE=$(solana balance "$WALLET_PATH" 2>/dev/null | cut -d' ' -f1)
        if [ -n "$BALANCE" ]; then
            echo "✅ Balance check successful: $BALANCE SOL"
        else
            echo "⚠️  Balance check failed"
        fi
    else
        echo "❌ Failed to extract public key"
        exit 1
    fi
else
    echo "⚠️  Solana CLI not available for key extraction"
fi

echo "=========================="
echo "🎉 Wallet verification completed successfully!"
```

Save this script as `scripts/verify_wallet.sh` and run it before starting the bot.

## References

- **Solana Documentation**: https://docs.solana.com/
- **Solana CLI Installation**: https://docs.solana.com/cli/install-solana-cli-tools
- **Wallet Security**: https://docs.solana.com/wallet-guide
- **Quick Deploy Script**: `scripts/quick_deploy.sh` (lines 367-397)
- **Environment Configuration**: `.env.example` (lines 68-73)

---

**⚠️ SECURITY WARNING**: Never share your wallet files, private keys, or seed phrases with anyone. Store backups in encrypted, offline locations. Always verify wallet addresses before sending funds.

**🔐 BEST PRACTICE**: Use hardware wallets for production environments and keep test/production wallets completely separate.