# Phase 1: Pre-Deployment Validation Checklist

This comprehensive validation checklist serves as the final verification step before proceeding to VPS deployment. Ensure all pre-deployment requirements are met.

---

## 1. Infisical Configuration ✓

- [ ] Infisical account created at https://app.infisical.com
- [ ] Project created with name "MojoRust Trading Bot" (or similar)
- [ ] Machine identity created with Universal Auth
- [ ] Client ID obtained and set in `.env` as `INFISICAL_CLIENT_ID`
- [ ] Client Secret obtained and set in `.env` as `INFISICAL_CLIENT_SECRET`
- [ ] Project ID obtained and set in `.env` as `INFISICAL_PROJECT_ID`
- [ ] Environment set to "production" in `.env`
- [ ] Infisical CLI installed: `npm install -g infisical`
- [ ] Infisical login successful: `infisical login`
- [ ] Secrets list accessible: `infisical secrets list --projectId <ID> --env production`
- [ ] Optional: Sensitive secrets stored in Infisical (API keys, passwords)

**Validation Command:**
```bash
infisical secrets list --projectId $INFISICAL_PROJECT_ID --env production
```

**Expected Result**: List of secrets displayed without errors

---

## 2. Environment File Configuration ✓

- [ ] `.env` file created from `.env.production.example`
- [ ] File permissions set to 600: `chmod 600 .env`
- [ ] `TRADING_ENV=production` set
- [ ] `EXECUTION_MODE=paper` set (for initial testing)
- [ ] `SERVER_HOST=38.242.239.150` set
- [ ] `SERVER_PORT=8080` set
- [ ] All required keys present (see validation script)
- [ ] No placeholder values remaining (e.g., "your_api_key_here")
- [ ] File not committed to git (verify with `git status`)

**Validation Command:**
```bash
./scripts/validate_config.sh --env-file .env
```

**Expected Result**: "✅ Configuration validation passed!"

---

## 3. API Keys Configuration ✓

- [ ] Helius API key obtained from https://helius.dev
- [ ] `HELIUS_API_KEY` set in `.env` (minimum 20 characters)
- [ ] `HELIUS_RPC_URL` configured with API key
- [ ] QuickNode endpoint obtained from https://www.quicknode.com
- [ ] `QUICKNODE_PRIMARY_RPC` set in `.env`
- [ ] Optional: `QUICKNODE_SECONDARY_RPC` set for failover
- [ ] Jupiter API URL set (no key required): `JUPITER_API_URL=https://quote-api.jup.ag/v6`
- [ ] DexScreener API URL set (no key required): `DEXSCREENER_API_URL=https://api.dexscreener.com/latest/dex`
- [ ] Rate limits configured appropriately

**Validation Commands:**
```bash
# Test Helius
curl -H "Authorization: Bearer $HELIUS_API_KEY" https://api.helius.xyz/v0/addresses/tokens

# Test QuickNode
curl -X POST -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' \
     $QUICKNODE_PRIMARY_RPC
```

**Expected Result**: Valid JSON responses without authentication errors

---

## 4. Solana Wallet Configuration ✓

- [ ] Wallet keypair generated or imported
- [ ] Keypair file exists at `secrets/keypair.json` (or custom path)
- [ ] File permissions set to 600: `chmod 600 secrets/keypair.json`
- [ ] File format validated (JSON array of 64 integers)
- [ ] Public key extracted: `solana-keygen pubkey secrets/keypair.json`
- [ ] `SOLANA_PUBLIC_KEY` set in `.env` with extracted public key
- [ ] `WALLET_ADDRESS` set in `.env` (same as public key)
- [ ] `SOLANA_KEYPAIR_FILE` path set correctly in `.env`
- [ ] Wallet has sufficient SOL balance for testing (minimum 0.1 SOL recommended)
- [ ] Backup created and stored securely (encrypted)

**Validation Commands:**
```bash
# Check file exists and permissions
ls -la secrets/keypair.json
# Expected: -rw------- (600 permissions)

# Validate JSON format
python3 -m json.tool secrets/keypair.json > /dev/null
# Expected: No errors

# Extract public key
solana-keygen pubkey secrets/keypair.json
# Expected: Base58 public key (44 characters)

# Check balance
solana balance secrets/keypair.json
# Expected: Balance in SOL
```

**Expected Result**: All commands succeed, public key matches `.env` configuration

---

## 5. Database Configuration ✓

- [ ] DragonflyDB URL configured: `REDIS_URL=rediss://default:gv7g6u9svsf1@612ehcb9i.dragonflydb.cloud:6385`
- [ ] Or local Redis configured with password
- [ ] TimescaleDB credentials set (if using local database)
- [ ] `TIMESCALEDB_PASSWORD` is strong and secure
- [ ] `REDIS_PASSWORD` is strong and secure (if using local Redis)
- [ ] Database connection strings do not contain special characters that need escaping

**Validation Command:**
```bash
# Test DragonflyDB connection
redis-cli -u $REDIS_URL ping
# Expected: PONG
```

---

## 6. Trading Parameters Configuration ✓

- [ ] `INITIAL_CAPITAL` set conservatively (recommended: 1.0 SOL for testing)
- [ ] `MAX_POSITION_SIZE` set to 0.10 (10% of capital)
- [ ] `MAX_DRAWDOWN` set to 0.15 (15% maximum loss)
- [ ] `DAILY_TRADE_LIMIT` set to reasonable value (50 recommended)
- [ ] `CIRCUIT_BREAKER_DRAWDOWN` set to 0.10 (10% emergency stop)
- [ ] Risk parameters reviewed and understood
- [ ] Paper trading mode confirmed: `EXECUTION_MODE=paper`

**Warning**: Do NOT set `EXECUTION_MODE=live` until paper trading is validated for 24+ hours

---

## 7. Security Configuration ✓

- [ ] `JWT_SECRET_KEY` generated (minimum 32 characters, random)
- [ ] `ALLOWED_IPS` configured with management IPs
- [ ] Firewall rules planned (ports 22, 8080, 9090, 3000)
- [ ] SSL/TLS certificates obtained (if using HTTPS)
- [ ] `.env` file permissions verified: 600
- [ ] `secrets/` directory permissions verified: 700
- [ ] No sensitive data in git history: `git log --all --full-history --source -- .env`

**Validation Command:**
```bash
# Check .env permissions
stat -c "%a" .env
# Expected: 600

# Check secrets directory
stat -c "%a" secrets/
# Expected: 700
```

---

## 8. Directory Structure ✓

- [ ] `src/` directory exists with all Mojo source files
- [ ] `scripts/` directory exists with deployment scripts
- [ ] `logs/` directory created: `mkdir -p logs`
- [ ] `secrets/` directory created: `mkdir -p secrets`
- [ ] `config/` directory exists with TOML configurations
- [ ] `rust-modules/` directory exists with Rust FFI code
- [ ] All scripts are executable: `chmod +x scripts/*.sh`

**Validation Command:**
```bash
./scripts/validate_config.sh --env-file .env
```

**Expected Result**: All directory checks pass

---

## 9. Automated Validation ✓

Run the comprehensive validation script:

```bash
./scripts/validate_config.sh --env-file .env --strict
```

**Expected Output:**
```
✅ Configuration validation passed!
📊 Configuration Validation Summary:
  ✅ No critical errors found
  ✅ No warnings found

Files checked:
  📄 Environment file: .env
  📁 Directory structure
  🔧 Configuration files
  🔗 Infisical connectivity
```

**If validation fails:**
- Review error messages carefully
- Fix issues one by one
- Re-run validation after each fix
- Use `--fix-permissions` flag to auto-fix permission issues

---

## 10. Pre-Deployment Checklist Summary ✓

- [ ] All Infisical credentials configured and tested
- [ ] `.env` file created with all required values
- [ ] All API keys obtained and validated
- [ ] Solana wallet created and secured
- [ ] Database connections configured
- [ ] Trading parameters set conservatively
- [ ] Security measures implemented
- [ ] Directory structure verified
- [ ] Automated validation passed: `./scripts/validate_config.sh`
- [ ] Backup of `.env` and wallet created and stored securely
- [ ] Documentation reviewed: `DEPLOY_NOW.md`, `WALLET_SETUP_GUIDE.md`

---

## Next Steps After Validation

Once all items are checked:

1. **Proceed to Phase 2**: VPS Infrastructure Setup
   - SSH to server: `ssh root@38.242.239.150`
   - Run: `scripts/vps_setup.sh`

2. **Transfer Configuration**:
   ```bash
   scp .env root@38.242.239.150:~/mojo-trading-bot/
   scp secrets/keypair.json root@38.242.239.150:~/mojo-trading-bot/secrets/
   ```

3. **Verify on Server**:
   ```bash
   ssh root@38.242.239.150
   cd ~/mojo-trading-bot
   ./scripts/validate_config.sh
   ```

4. **Deploy**: Follow `DEPLOY_NOW.md` steps 6-8

---

## Troubleshooting Common Issues

**Issue**: Infisical connection fails
- **Solution**: Check firewall allows HTTPS to app.infisical.com, verify credentials

**Issue**: API key validation fails
- **Solution**: Verify API key is active in provider dashboard, check for extra spaces

**Issue**: Wallet format invalid
- **Solution**: Regenerate wallet using `solana-keygen new`, ensure JSON array format

**Issue**: Permission errors
- **Solution**: Run `./scripts/validate_config.sh --fix-permissions`

**Issue**: Missing environment variables
- **Solution**: Compare `.env` with `.env.production.example`, add missing keys

---

## Emergency Contacts & Resources

- **Infisical Support**: https://infisical.com/docs
- **Helius Support**: https://docs.helius.dev
- **QuickNode Support**: https://www.quicknode.com/docs
- **Solana Documentation**: https://docs.solana.com
- **Project Documentation**: `DEPLOYMENT.md`, `DEPLOY_NOW.md`
- **Validation Script**: `scripts/validate_config.sh`

Refer to the validation script implementation in `scripts/validate_config.sh` for detailed validation logic and error handling.