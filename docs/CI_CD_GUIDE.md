# CI/CD Pipeline Guide - MojoRust Trading Bot

## Table of Contents

1. [Overview](#overview)
2. [GitHub Actions Workflows](#github-actions-workflows)
3. [GitHub Secrets Configuration](#github-secrets-configuration)
4. [Pre-commit Hooks](#pre-commit-hooks)
5. [Makefile Commands](#makefile-commands)
6. [Deployment Process](#deployment-process)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)

## Overview

The MojoRust Trading Bot uses a comprehensive CI/CD pipeline built on GitHub Actions to ensure code quality, security, and reliable deployments.

### Architecture Benefits

- **Automated Quality Gates**: Every commit is validated for code quality, security, and functionality
- **Zero-Touch Deployments**: Automated deployments to staging and production environments
- **Security First**: Comprehensive secret scanning and vulnerability detection
- **Developer Experience**: Pre-commit hooks and local testing prevent CI failures
- **Reliability**: Health checks and automatic rollback on deployment failures

### Pipeline Flow

```
Developer Commit → Pre-commit Hooks → Push → CI Pipeline → CD Pipeline → Deployment
     │                │              │         │           │
  Local Validation  Code Format    Build     Deploy     Health Check
                     Security Scan   Test     Approve    Monitor
```

## GitHub Actions Workflows

### CI Workflow (`ci.yml`)

**Purpose**: Validate code quality and functionality before allowing merges.

**Triggers**:
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop`
- Manual workflow dispatch

**Jobs**:

1. **Lint Job** (~2 minutes)
   - **Mojo Linting**: `mojo format --check src/`
   - **Rust Linting**: `cargo clippy --all-targets --all-features -- -D warnings`
   - **Shell Script Linting**: `shellcheck scripts/*.sh`
   - **TOML/YAML Validation**: Syntax and structure validation

2. **Security Job** (~3 minutes)
   - **Secrets Detection**: `scripts/validate_config.sh --strict`
   - **Gitleaks Scan**: Comprehensive credential detection
   - **Dependency Audit**: `cargo audit` for known vulnerabilities
   - **SAST Scan**: Semgrep for security patterns

3. **Build Job** (~5 minutes)
   - **Mojo Build**: Compile main application and ultimate version
   - **Rust Build**: Compile modules with optimizations
   - **Artifact Upload**: Store binaries for subsequent jobs

4. **Test Job** (~3 minutes)
   - **Mojo Tests**: `mojo test tests/test_suite.mojo`
   - **Rust Tests**: `cargo test --all-features`
   - **Integration Tests**: Cross-component testing
   - **Coverage Reporting**: Generate test coverage metrics

5. **Integration Job** (~2 minutes)
   - **Configuration Validation**: `scripts/validate_config.sh --env-file .env.example --strict`
   - **FFI Verification**: `scripts/verify_ffi.sh`
   - **Deployment Script Test**: `scripts/deploy.sh --dry-run`

**Caching**: Dependencies and build artifacts are cached for faster builds.

**Artifacts**: Build binaries, test reports, and validation results are stored for 7 days.

### Deploy Workflow (`deploy.yml`)

**Purpose**: Automated deployment to staging and production environments.

**Triggers**:
- Push to `develop` branch (staging)
- Push to `main` branch (production)
- Version tag creation (`v*.*.*`)
- Manual dispatch with environment selection

**Jobs**:

1. **Validate Job** (~1 minute)
   - **CI Status Check**: Ensure CI workflow passed
   - **Version Consistency**: Verify version numbers across files
   - **Configuration Validation**: Production configuration sanity checks
   - **Build Verification**: Confirm all artifacts exist

2. **Package Job** (~2 minutes)
   - **Download Artifacts**: Get binaries from CI workflow
   - **Create Deployment Package**: Bundle all necessary files
   - **Generate Manifest**: Include version, commit, and metadata
   - **Upload Package**: Store for deployment jobs

3. **Deploy-Staging Job** (~3 minutes)
   - **Environment**: Staging server (no approval required)
   - **Mode**: Always paper trading
   - **Health Checks**: Verify bot starts correctly
   - **Rollback**: Automatic on failure

4. **Deploy-Production Job** (~5 minutes)
   - **Environment**: Production server (38.242.239.150)
   - **Approval Required**: Manual approval from maintainers
   - **Mode**: Configurable (paper/live)
   - **Backup**: Automatic backup before deployment
   - **Health Checks**: Comprehensive post-deployment validation
   - **Rollback**: Automatic on failure

5. **Post-Deploy Job** (~1 minute)
   - **Notifications**: Telegram/Discord alerts
   - **Deployment Events**: GitHub deployment API integration
   - **Summary Reports**: Detailed deployment outcomes

**Environments**:
- **Staging**: No approval required, paper trading only
- **Production**: Approval required, configurable mode

**Security**:
- SSH keys stored in GitHub secrets
- Environment-specific secret isolation
- Automatic rollback on health check failures

### Security Scan Workflow (`security-scan.yml`)

**Purpose**: Deep security analysis and vulnerability detection.

**Triggers**:
- Daily schedule at 2 AM UTC
- Manual dispatch
- Changes to security-sensitive files

**Jobs**:

1. **Dependency Scanning** (~3 minutes)
   - **Rust Audit**: `cargo audit` for known vulnerabilities
   - **Advisory Creation**: Automatic GitHub Security Advisories
   - **License Compliance**: Check for problematic licenses

2. **Secret Scanning** (~5 minutes)
   - **Gitleaks**: Full repository history scan
   - **TruffleHog**: High-entropy string detection
   - **Custom Detection**: Project-specific secret patterns

3. **SAST Analysis** (~4 minutes)
   - **Semgrep**: Security pattern detection
   - **CodeQL**: Advanced vulnerability analysis (if available)
   - **Custom Rules**: Trading-bot specific security checks

4. **Container Scanning** (~3 minutes)
   - **Docker Build**: Create security scan image
   - **Trivy Scan**: Container vulnerability assessment
   - **Base Image Analysis**: CVE detection in dependencies

5. **Security Reporting** (~1 minute)
   - **Report Generation**: Consolidated security findings
   - **Issue Creation**: Automatic GitHub issues for critical findings
   - **Notifications**: Security alerts to maintainers

## GitHub Secrets Configuration

### Required Secrets

Create these secrets in **Repository Settings → Secrets and variables → Actions**:

#### API Keys
```
HELIUS_API_KEY=your_helius_api_key_here
QUICKNODE_RPC_URL=https://your-quicknode-url.solana-mainnet.quiknode.pro/your-key/
DEXSCREENER_API_KEY=your_dexscreener_key_here  # Optional
BIRDEYE_API_KEY=your_birdeye_key_here  # Optional
```

#### Infisical Secrets Management
```
INFISICAL_PROJECT_ID=your_infisical_project_id
INFISICAL_CLIENT_ID=your_infisical_client_id
INFISICAL_CLIENT_SECRET=your_infisical_client_secret
```

#### Modular (Mojo) Authentication
```
MODULAR_AUTH_TOKEN=your_modular_auth_token_here
```
*Note: This token is required for non-interactive installation of the Mojo SDK on GitHub Actions runners. You can create a token at [https://www.modular.com](https://www.modular.com).*

#### Deployment Credentials
```
PRODUCTION_SERVER_IP=38.242.239.150
PRODUCTION_SSH_USER=root
PRODUCTION_SSH_KEY=-----BEGIN OPENSSH PRIVATE KEY-----
# Your private SSH key content
-----END OPENSSH PRIVATE KEY-----

STAGING_SERVER_IP=staging-server-ip
STAGING_SSH_USER=staging-user
STAGING_SSH_KEY=-----BEGIN OPENSSH PRIVATE KEY-----
# Your staging SSH key content
-----END OPENSSH PRIVATE KEY-----
```

#### Notification Credentials (Optional)
```
TELEGRAM_BOT_TOKEN=your_telegram_bot_token
TELEGRAM_CHAT_ID=your_telegram_chat_id
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/your-webhook
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/your-webhook
```

#### Database Credentials
```
DB_PASSWORD=your_database_password
DB_HOST=localhost
DB_PORT=5432
DB_NAME=trading_bot
```

### Environment-Specific Secrets

#### Staging Environment
Create secrets under the **staging** environment:
- Override any repository secrets with staging-specific values
- Use staging API endpoints and test credentials

#### Production Environment
Create secrets under the **production** environment:
- Production API keys and credentials
- Override repository secrets for production use

### Adding Secrets

1. Go to repository **Settings → Secrets and variables → Actions**
2. Click **New repository secret**
3. Enter secret name (match the names above exactly)
4. Enter secret value
5. Click **Add secret**
6. Verify the secret appears in the list (value will be hidden)

### Security Best Practices

- **Never log secrets**: GitHub Actions automatically masks secret values
- **Use environment secrets**: Isolate secrets by environment
- **Rotate regularly**: Update secrets on a schedule
- **Principle of least privilege**: Grant minimal necessary permissions
- **Audit access**: Review who has access to repository secrets

## Pre-commit Hooks

### Installation

```bash
# Install pre-commit
pip install pre-commit

# Install hooks
pre-commit install

# Install commit-msg hook
pre-commit install --hook-type commit-msg

# Run hooks manually on all files
pre-commit run --all-files
```

### Configured Hooks

#### General Hooks
- **trailing-whitespace**: Remove trailing whitespace
- **end-of-file-fixer**: Ensure files end with newline
- **check-yaml**: Validate YAML syntax
- **check-toml**: Validate TOML syntax
- **check-json**: Validate JSON files
- **check-added-large-files**: Prevent large files (>500KB)
- **check-merge-conflict**: Detect merge conflict markers
- **detect-private-key**: Detect private keys

#### Shell Script Hooks
- **shellcheck**: Lint shell scripts for common issues
- **shfmt**: Format shell scripts consistently

#### Rust Hooks
- **cargo-fmt**: Format Rust code according to style guidelines
- **cargo-clippy**: Lint Rust code for potential issues
- **cargo-check**: Verify code compiles without errors

#### Mojo Hooks
- **mojo-format**: Format Mojo code (when available)
- **mojo-lint**: Lint Mojo code (when available)

#### Security Hooks
- **detect-secrets**: Detect hardcoded credentials. Uses a baseline file (`.secrets.baseline`) to track and ignore false positives.
- **gitleaks**: Scan for leaked credentials
- **validate-config**: Run configuration validation

#### Documentation Hooks
- **markdown-lint**: Ensure consistent markdown formatting
- **check-links**: Verify internal and external links

#### Commit Message Hooks
- **commitizen**: Enforce conventional commit message format

### Running Hooks Manually

```bash
# Run all hooks on all files
pre-commit run --all-files

# Run specific hook
pre-commit run shellcheck --all-files

# Run hooks on staged files only
pre-commit run

# Skip specific hook
SKIP=cargo-clippy pre-commit run

# Skip all hooks (emergency only)
git commit --no-verify
```

### Hook Configuration

The pre-commit configuration is in `.pre-commit-config.yaml`. Key settings:

- **fail_fast: false**: Run all hooks even if some fail
- **default_stages: [commit, push]**: When hooks run
- **minimum_pre_commit_version: 2.20.0**: Minimum version requirement

### Troubleshooting Hooks

**Hook fails:**
1. Review the error message
2. Fix the issue identified
3. Run the hook manually to verify fix
4. Commit again

**Hook too slow:**
1. Review the hook configuration
2. Adjust settings or skip the hook temporarily
3. Report performance issues

**False positives:**
1. Add to exclusion list in configuration
2. For `detect-secrets`, you can update the baseline to ignore a finding. First, audit the baseline file: `detect-secrets audit .secrets.baseline`. Then, follow the interactive prompts to mark items as false positives. Commit the updated `.secrets.baseline` file.
3. Report the false positive to tool maintainers

## Makefile Commands

### Quick Reference

#### Build Commands
```bash
make build          # Build all components
make build-mojo     # Build Mojo application
make build-rust     # Build Rust modules
make build-dev      # Build in development mode
make build-release  # Build optimized release
```

#### Test Commands
```bash
make test           # Run all tests
make test-mojo      # Run Mojo tests
make test-rust      # Run Rust tests
make test-watch     # Run tests in watch mode
make test-coverage  # Generate coverage report
```

#### Lint Commands
```bash
make lint           # Run all linters
make lint-mojo      # Lint Mojo code
make lint-rust      # Lint Rust code
make lint-shell     # Lint shell scripts
make lint-fix       # Auto-fix linting issues
```

#### Deploy Commands
```bash
make deploy         # Deploy to production
make deploy-staging # Deploy to staging
make deploy-production # Deploy to production (with confirmation)
make deploy-dry-run # Simulate deployment
```

#### Development Commands
```bash
make dev            # Start development environment
make run            # Run bot locally
make run-paper      # Run in paper trading mode
make run-live       # Run in live trading mode
make logs           # View bot logs
make status         # Check bot status
```

#### Setup Commands
```bash
make setup          # Initial project setup
make setup-dev      # Setup development environment
make install-deps   # Install dependencies
```

#### CI Commands
```bash
make ci             # Run full CI pipeline locally
make ci-lint        # Run CI linting checks
make ci-test        # Run CI tests
```

### Usage Examples

#### First-time Setup
```bash
# Clone and setup
git clone https://github.com/SynergiaOS/MojoRust.git
cd MojoRust

# Install everything
make setup

# Configure API keys
cp .env.example .env
nano .env  # Add your API keys
```

#### Daily Development Workflow
```bash
# Check current status
make status

# Run tests locally before pushing
make test

# Run full CI pipeline
make ci

# Deploy to staging
make deploy-staging
```

#### Deployment Preparation
```bash
# Build release version
make build-release

# Run comprehensive tests
make test-coverage

# Validate configuration
make validate

# Deploy to production
make deploy-production
```

### Custom Variables

You can customize Make behavior with variables:

```bash
# Custom deployment server
make deploy DEPLOY_SERVER=custom-server

# Custom trading mode
make deploy DEPLOY_MODE=live

# Custom deploy user
make deploy DEPLOY_USER=admin
```

## Deployment Process

### Automated Deployment Flow

#### Staging Deployment (Automatic)

1. **Trigger**: Push to `develop` branch
2. **Validation**: CI pipeline runs automatically
3. **Packaging**: Create deployment package
4. **Deployment**: Deploy to staging server
5. **Health Check**: Verify bot is running correctly
6. **Notification**: Send deployment status

```bash
# Trigger staging deployment
git push origin develop
```

#### Production Deployment (Manual Approval)

1. **Trigger**: Push to `main` branch or create version tag
2. **CI Validation**: Ensure all checks pass
3. **Approval Request**: Manual approval in GitHub UI
4. **Backup**: Create backup of current deployment
5. **Deployment**: Deploy new version
6. **Health Check**: Comprehensive validation
7. **Rollback**: Automatic on failure

```bash
# Trigger production deployment
git tag v1.0.0
git push origin v1.0.0

# Or push to main branch
git push origin main
```

### Manual Deployment Options

#### Using Make Commands

```bash
# Deploy to staging
make deploy-staging

# Deploy to production (with confirmation)
make deploy-production

# Dry run deployment
make deploy-dry-run
```

#### Using Deployment Scripts

```bash
# Direct deployment script
./scripts/deploy_to_server.sh --mode=paper

# Deployment with filters
./scripts/deploy_with_filters.sh --mode=live

# Quick deployment
./scripts/quick_deploy.sh
```

### Deployment Environments

#### Staging Environment
- **Server**: Staging server IP
- **Mode**: Paper trading only
- **Approval**: Not required
- **Purpose**: Testing new features safely

#### Production Environment
- **Server**: 38.242.239.150
- **Mode**: Configurable (paper/live)
- **Approval**: Required from maintainers
- **Purpose**: Live trading operations

### Health Checks

#### Automatic Health Checks

Deployments include comprehensive health checks:

1. **Process Verification**: Confirm bot process is running
2. **API Endpoints**: Test health endpoints
3. **Database Connectivity**: Verify database connections
4. **Log Analysis**: Check for errors in recent logs
5. **Performance Metrics**: Validate monitoring is working

#### Manual Health Checks

```bash
# Check bot status
make status

# View logs
make logs

# Check API health
curl http://38.242.239.150:8080/api/health

# Server health check
./scripts/server_health.sh --remote
```

### Rollback Procedure

#### Automatic Rollback
If health checks fail, the pipeline automatically:
1. Detects deployment failure
2. Restores previous version from backup
3. Restarts bot with previous version
4. Notifies team of rollback

#### Manual Rollback

```bash
# SSH to production server
ssh root@38.242.239.150

# Check available backups
ls -la /root/mojorust-backups/

# Restore from backup
sudo cp -r /root/mojorust-backups/production-backup-YYYYMMDD-HHMMSS/* /root/mojorust/

# Restart bot
cd /root/mojorust
pkill -f trading-bot || true
nohup ./target/trading-bot --mode=paper > logs/production-bot.log 2>&1 &

# Verify rollback
make status
```

## Troubleshooting

### Common Issues

#### CI Workflow Failures

**Lint Failures**
```bash
# Run linting locally
make lint

# Auto-fix formatting issues
make lint-fix

# Commit fixes
git add .
git commit -m "fix: Address linting issues"
git push
```

**Build Failures**
```bash
# Check dependencies
make install-deps

# Clean rebuild
make clean && make build

# Check for specific errors
make build 2>&1 | grep -i error
```

**Test Failures**
```bash
# Run specific failing test
mojo test tests/test_failing_test.mojo

# Run tests with verbose output
make test 2>&1 | grep -A5 -B5 "FAIL"

# Check test environment
make validate
```

**Security Scan Failures**
```bash
# Check for hardcoded secrets
make validate-secrets

# Update dependencies
cd rust-modules && cargo update

# Run security scans locally
gitleaks protect --source . --verbose
```

#### Deployment Failures

**SSH Connection Issues**
```bash
# Test SSH connection
ssh -o ConnectTimeout=10 root@38.242.239.150 "echo 'SSH OK'"

# Check SSH key permissions
chmod 600 ~/.ssh/id_rsa

# Verify host key
ssh-keyscan 38.242.239.150 >> ~/.ssh/known_hosts
```

**Health Check Failures**
```bash
# Check bot process
ssh root@38.242.239.150 "pgrep -f trading-bot"

# Check logs for errors
ssh root@38.242.239.150 "tail -n 100 logs/production-bot.log"

# Restart bot manually
ssh root@38.242.239.150 "cd /root/mojorust && pkill -f trading-bot && nohup ./target/trading-bot --mode=paper > logs/production-bot.log 2>&1 &"
```

**Configuration Issues**
```bash
# Validate configuration
make validate

# Check environment variables
ssh root@38.242.239.150 "cat /root/mojorust/.env"

# Test configuration loading
ssh root@38.242.239.150 "cd /root/mojorust && ./target/trading-bot --config-test"
```

#### Pre-commit Hook Issues

**Hook Installation**
```bash
# Reinstall hooks
pre-commit uninstall
pre-commit install

# Check hook versions
pre-commit --version

# Update hooks
pre-commit autoupdate
```

**Hook Performance**
```bash
# Run hooks on specific files only
pre-commit run --files changed_file.rs

# Skip slow hooks
SKIP=cargo-audit pre-commit run

# Debug hook execution
pre-commit run --verbose
```

### Debug Tips

#### Enable Debug Logging
```bash
# Enable GitHub Actions debug logging
ACTIONS_STEP_DEBUG=true

# Enable Rust debug output
RUST_LOG=debug

# Enable verbose output
make build VERBOSE=1
```

#### Local CI Testing
```bash
# Simulate CI pipeline
make ci

# Run specific CI stages
make ci-lint && make ci-test

# Test with specific environment
ENVIRONMENT=testing make test
```

#### Network Issues
```bash
# Test API connectivity
curl -I https://api.helius.xyz
curl -I https://your-quicknode-url.solana-mainnet.quiknode.pro/

# Test DNS resolution
nslookup api.helius.xyz
nslookup solana-mainnet.quiknode.pro
```

#### Memory and Performance
```bash
# Check system resources
free -h
df -h

# Monitor process performance
top -p $(pgrep trading-bot)

# Profile memory usage
valgrind --tool=massif ./target/trading-bot --config-test
```

### Getting Help

#### GitHub Issues
- **CI Failures**: Check workflow logs in GitHub Actions tab
- **Security Issues**: Create private issue if sensitive
- **Feature Requests**: Use discussions for planning

#### Documentation
- **API References**: Link to external API documentation
- **Troubleshooting Guides**: Specific to each component
- **Community Support**: GitHub discussions and forums

#### Monitoring and Alerting
- **Grafana Dashboards**: Performance metrics
- **Prometheus Alerts**: System health notifications
- **Telegram/Discord**: Real-time alerts

## Best Practices

### Development Practices

#### Before Committing
1. **Run tests locally**: `make test`
2. **Check linting**: `make lint`
3. **Validate configuration**: `make validate`
4. **Run CI simulation**: `make ci`

#### Code Quality
1. **Follow style guides**: Consistent formatting
2. **Write tests**: Unit and integration tests
3. **Document changes**: Update relevant documentation
4. **Small commits**: Focused, reviewable changes

#### Commit Messages
1. **Conventional format**: `type(scope): subject`
2. **Clear description**: What and why
3. **Reference issues**: Link related GitHub issues
4. **Sign-off**: Sign-off for certification requirements

### Security Practices

#### Secret Management
1. **Never commit secrets**: Use environment variables
2. **Rotate regularly**: Update credentials on schedule
3. **Least privilege**: Minimal necessary permissions
4. **Audit access**: Review who has access

#### Code Security
1. **Input validation**: Sanitize all inputs
2. **Dependency updates**: Keep dependencies current
3. **Security reviews**: Review sensitive code changes
4. **Vulnerability scanning**: Regular security assessments

#### Deployment Security
1. **Staging first**: Always test in staging
2. **Backup before deploy**: Create deployment backups
3. **Monitor after deploy**: Watch for issues
4. **Rollback plan**: Have recovery procedures

### CI/CD Best Practices

#### Workflow Design
1. **Fast feedback**: Quick feedback on changes
2. **Parallel execution**: Run independent jobs in parallel
3. **Fail fast**: Stop on critical failures
4. **Comprehensive testing**: Full test coverage

#### Resource Management
1. **Caching**: Cache dependencies and build artifacts
2. **Timeouts**: Set reasonable job timeouts
3. **Resource limits**: Concurrency limits to prevent overload
4. **Cleanup**: Remove old artifacts and workflows

#### Monitoring and Alerting
1. **Success metrics**: Track success rates
2. **Performance metrics**: Monitor execution times
3. **Failure alerts**: Notify on failures
4. **Trend analysis**: Identify patterns and improvements

### Deployment Best Practices

#### Deployment Strategy
1. **Blue-green deployment**: Zero-downtime deployments
2. **Canary releases**: Gradual rollout for critical changes
3. **Feature flags**: Toggle features without deployment
4. **Rollback testing**: Regularly test rollback procedures

#### Environment Management
1. **Configuration consistency**: Same config structure across environments
2. **Environment isolation**: Separate secrets and configurations
3. **Data separation**: Separate databases for staging/production
4. **Access control**: Different access levels per environment

#### Monitoring and Maintenance
1. **Health checks**: Comprehensive post-deployment validation
2. **Log aggregation**: Centralized log collection
3. **Performance monitoring**: Track system performance
4. **Capacity planning**: Monitor resource usage

## Appendix

### Links and Resources

#### GitHub Actions Documentation
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- [Secret Management](https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions)

#### Tool Documentation
- [Pre-commit](https://pre-commit.com/)
- [Make](https://www.gnu.org/software/make/manual/)
- [Semgrep](https://semgrep.dev/)
- [Gitleaks](https://gitleaks.io/)

#### Security Resources
- [OWASP Testing Guide](https://owasp.org/www-project-web-security-testing-guide/)
- [GitHub Security Advisories](https://docs.github.com/en/code-security/security-advisories)
- [Dependabot Documentation](https://docs.github.com/en/code-security/dependabot)

### Contact and Support

#### Getting Help
- **GitHub Issues**: Report bugs and request features
- **GitHub Discussions**: Community support and discussions
- **Security Issues**: Report security vulnerabilities privately
- **Documentation**: Improve this guide with feedback

#### Contributing
- **Code Contributions**: Follow development workflow
- **Documentation**: Help improve documentation
- **Bug Reports**: Include detailed reproduction steps
- **Feature Requests**: Provide clear requirements and use cases

---

*This guide is continuously updated. For the latest version, check the repository documentation.*