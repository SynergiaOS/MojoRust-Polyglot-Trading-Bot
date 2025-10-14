# Contributing to MojoRust Trading Bot

Thank you for your interest in contributing to MojoRust Trading Bot! We welcome contributions from the community and appreciate your help in making this project better.

**By contributing to this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).**

## Table of Contents

1. [Getting Started](#getting-started)
2. [Ways to Contribute](#ways-to-contribute)
3. [Development Setup](#development-setup)
4. [Development Workflow](#development-workflow)
5. [Code Style Guidelines](#code-style-guidelines)
6. [Commit Message Guidelines](#commit-message-guidelines)
7. [Pull Request Guidelines](#pull-request-guidelines)
8. [Testing Requirements](#testing-requirements)
9. [Documentation Requirements](#documentation-requirements)
10. [Security Considerations](#security-considerations)
11. [Performance Considerations](#performance-considerations)
12. [Financial Software Guidelines](#financial-software-guidelines)
13. [Community Guidelines](#community-guidelines)
14. [Getting Help](#getting-help)
15. [Recognition](#recognition)
16. [License](#license)

## Getting Started

### Prerequisites

Before you begin contributing, ensure you have:

- **Mojo 24.4+** installed and configured
- **Rust 1.70+** installed and up to date
- **Git** and **GitHub account** configured
- **Basic familiarity** with trading concepts (helpful but not required)
- **Patience and willingness** to learn and collaborate

### First-Time Contributors

If you're new to the project:

1. **Read this guide** thoroughly to understand our processes
2. **Familiarize yourself** with the project structure and codebase
3. **Join our community** discussions to understand current priorities
4. **Start small** with documentation, bug fixes, or good first issues
5. **Ask questions** - we're here to help you get started!

## Ways to Contribute

### Code Contributions

We welcome code contributions in areas such as:

- **Bug fixes** and error corrections
- **New features** and functionality improvements
- **Trading strategies** and algorithm improvements
- **API integrations** and data sources
- **Performance optimizations** and speed improvements
- **Testing and quality assurance**
- **Documentation and examples**

### Non-Code Contributions

You can also contribute without writing code:

- **Bug reports** and feature requests
- **Documentation improvements** and corrections
- **Community support** and answering questions
- **Testing and feedback** on new features
- **Translations** (Polish, English, other languages)
- **Sharing** the project with others
- **Providing feedback** on user experience

### Finding Opportunities

Look for issues labeled:
- `good first issue` - Beginner-friendly tasks
- `documentation` - Documentation improvements
- `help wanted` - Community help needed
- `bug` - Bug fixes (great for learning codebase)
- `enhancement` - New features and improvements

## Development Setup

### 1. Fork and Clone

```bash
# Fork the repository on GitHub, then clone your fork
git clone https://github.com/YOUR_USERNAME/MojoRust.git
cd MojoRust

# Add upstream remote for keeping up to date
git remote add upstream https://github.com/SynergiaOS/MojoRust.git
```

### 2. Setup Development Environment

```bash
# Install development dependencies and tools
make setup-dev

# Install pre-commit hooks (required)
pre-commit install

# Build the project to verify setup
make build

# Run tests to ensure everything works
make test
```

### 3. Create Development Branch

```bash
# Create a feature branch from main
git checkout -b feature/your-feature-name

# Or for bug fixes
git checkout -b fix/your-bug-fix-name
```

### 4. Verify Environment

```bash
# Check that all tools are working
make ci

# Run linting and formatting checks
make lint

# Run the full test suite
make test-all
```

## Development Workflow

### Step-by-Step Process

1. **Fork Repository** on GitHub
2. **Create Feature Branch:** `git checkout -b feature/your-feature-name`
3. **Install Development Tools:** `make setup-dev`
4. **Make Changes** following our code style guidelines
5. **Write Tests** for new functionality (70%+ coverage required)
6. **Run Tests Locally:** `make test`
7. **Run Linters:** `make lint` (auto-fix with `make lint-fix`)
8. **Run CI Checks:** `make ci` to simulate the pipeline
9. **Commit Changes** with conventional commit message
10. **Push Branch:** `git push origin feature/your-feature-name`
11. **Open Pull Request** with clear description and template
12. **Address Review Feedback** promptly and respectfully
13. **Wait for CI to Pass** (all checks must be green)
14. **Merge** after approval from maintainers

### Keeping Your Branch Updated

```bash
# Regularly sync with upstream main
git fetch upstream
git rebase upstream/main

# Or merge if you prefer
git merge upstream/main
```

### Before Submitting

```bash
# Run the full CI pipeline locally
make ci

# Check code coverage
make test-coverage-report

# Validate no secrets are committed
make validate-secrets

# Check for merge conflicts
git merge main --no-commit --no-ff
```

## Code Style Guidelines

### Mojo Code

- **Formatting:** Use `mojo format` for consistent formatting
- **Naming:** Use `snake_case` for functions and variables, `PascalCase` for structs
- **Documentation:** Add docstrings for public functions and structs
- **Function Length:** Keep functions focused and under 50 lines when possible
- **Type Hints:** Use type hints where applicable for better code clarity
- **Imports:** Organize imports at the top of files, group by type

**Example:**
```mojo
# Import standard library
from math import sqrt

# Import project modules
from core.types import MarketData, TradingSignal
from data.helius_client import HeliusClient

@value
struct MarketAnalyzer:
    var threshold: Float64

    fn analyze(self, market_data: MarketData) -> TradingSignal:
        """Analyze market data and generate trading signal.

        Args:
            market_data: Current market data including price and volume

        Returns:
            Trading signal with action and confidence score
        """
        # Implementation here
        pass
```

### Rust Code

- **Formatting:** Use `cargo fmt` for consistent formatting
- **Linting:** Use `cargo clippy` for linting (must pass with no warnings)
- **Documentation:** Add documentation comments (`///`) for public APIs
- **Performance:** Use `#[inline]` hints for hot paths
- **Safety:** Ensure thread safety (Send/Sync) for FFI types
- **Error Handling:** Use `Result<T, E>` for error handling

**Example:**
```rust
/// High-performance portfolio manager for capital allocation
pub struct PortfolioManager {
    total_capital: f64,
    allocated_capital: f64,
    strategies: HashMap<String, Strategy>,
}

impl PortfolioManager {
    /// Allocate capital to a specific strategy
    ///
    /// # Arguments
    /// * `strategy_id` - Unique identifier for the strategy
    /// * `amount` - Amount of capital to allocate
    ///
    /// # Returns
    /// * `Ok(())` if allocation succeeded
    /// * `Err(PortfolioError)` if allocation failed
    #[inline]
    pub fn allocate_capital(&mut self, strategy_id: &str, amount: f64) -> Result<(), PortfolioError> {
        // Implementation
    }
}
```

### Shell Scripts

- **Linting:** Use shellcheck for linting
- **Formatting:** Use shfmt for formatting (4-space indent)
- **Error Handling:** Add error handling (`set -euo pipefail`)
- **Documentation:** Add usage documentation in header comments
- **Portability:** Write portable shell scripts (avoid bash-specific features when possible)

**Example:**
```bash
#!/bin/bash
# Deployment script for MojoRust Trading Bot
# Usage: ./scripts/deploy.sh [environment]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Main deployment logic
main() {
    local environment="${1:-staging}"

    echo "Deploying to $environment..."

    # Implementation
}
```

## Commit Message Guidelines

### Format: Conventional Commits

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
type(scope): subject

[optional body]

[optional footer]
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, no logic change)
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `test`: Test additions or fixes
- `chore`: Build process, dependencies, tooling
- `ci`: CI/CD changes
- `security`: Security fixes

### Scopes

- `arbitrage`: Arbitrage detection and execution
- `strategy`: Trading strategies
- `risk`: Risk management
- `execution`: Trade execution
- `monitoring`: Monitoring and alerts
- `api`: API clients (Helius, QuickNode, Jupiter)
- `ffi`: Rust-Mojo FFI
- `config`: Configuration management
- `docs`: Documentation
- `tests`: Testing infrastructure
- `ci`: CI/CD pipeline

### Examples

```bash
feat(arbitrage): add triangular arbitrage detection
fix(execution): correct slippage calculation in Jupiter swaps
docs(readme): update deployment instructions
perf(ffi): optimize object pooling for 60% speedup
security(secrets): remove hardcoded API keys
test(integration): add database persistence tests
ci(github): add coverage gates and artifact uploads
refactor(config): simplify configuration loading
chore(deps): update Rust dependencies to latest versions
```

### Body and Footer

**Body (optional):**
- Use present tense ("add" not "added")
- Explain what and why, not how
- Keep paragraphs under 72 characters

**Footer (optional):**
- Reference issues: `Fixes #123` or `Closes #456`
- Breaking changes: `BREAKING CHANGE: description`
- Co-authors: `Co-authored-by: Name <email>`

**Example:**
```bash
feat(strategy): add RSI-based mean reversion strategy

Implement RSI (Relative Strength Index) strategy for detecting
overbought/oversold conditions and generating contrarian signals.

The strategy calculates 14-period RSI and generates:
- BUY signals when RSI < 30 (oversold)
- SELL signals when RSI > 70 (overbought)

Includes configurable parameters for RSI period and thresholds.

Fixes #123
Co-authored-by: Jane Doe <jane@example.com>
```

## Pull Request Guidelines

### PR Title

- Use conventional commit format
- Be descriptive and concise
- Reference issue if applicable: `feat(arbitrage): add flash loans (#123)`

### PR Description Template

```markdown
## Description
Brief description of changes made in this pull request.

## Motivation
Why is this change needed? What problem does it solve?

## Changes
- List of specific changes
- File modifications
- New dependencies (if any)

## Testing
- How was this tested?
- Test coverage added?
- Manual testing performed?
- Performance benchmarks (if applicable)

## Screenshots (if applicable)
For UI/dashboard changes or configuration updates.

## Checklist
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
- [ ] No hardcoded secrets
- [ ] CI checks pass
- [ ] Code reviewed by self
- [ ] Breaking changes documented (if applicable)

## Additional Notes
Any additional context, considerations, or follow-up items.
```

### PR Requirements

**Before Submitting:**
- All CI checks must pass (lint, security, build, test)
- At least one approval from maintainer required
- No merge conflicts
- CHANGELOG.md updated (for notable changes)
- Tests added for new features
- Documentation updated for user-facing changes
- Performance impact assessed (for optimizations)
- Security implications considered (for sensitive changes)

**Review Process:**
- Maintainers will review for code quality, functionality, and security
- Address feedback promptly and respectfully
- Additional commits may be requested
- PR may be rejected if standards are not met
- Maintain communication throughout the review process

### Merge Requirements

- All automated checks must pass
- Code coverage must not decrease (70%+ minimum)
- At least one maintainer approval
- No unresolved merge conflicts
- Documentation updated as needed
- Breaking changes clearly documented

## Testing Requirements

### Test Coverage

- **Minimum Coverage:** 70% code coverage (enforced by CI)
- **Target Coverage:** 85%+ for new code
- **Critical Paths:** 95%+ for trading logic and risk management
- **Integration Coverage:** All major integrations tested

### Test Types

**Unit Tests:**
- `tests/test_suite.mojo` - Core functionality tests
- `tests/test_engines.mojo` - Engine and strategy tests
- Rust modules: `cargo test` in `rust-modules/`

**Integration Tests:**
- `tests/integration/test_api_integration.mojo` - API client tests
- `tests/integration/test_database_integration.mojo` - Database tests
- `tests/integration/test_trading_strategies.mojo` - Strategy integration tests

**Load Tests:**
- `tests/load/api_load_test.js` - API endpoint performance
- `tests/load/trading_cycle_load_test.js` - Trading cycle performance

**Benchmarks:**
- `tests/benchmarks/ffi_performance.mojo` - FFI performance tests
- `rust-modules/benches/*.rs` - Rust module benchmarks

### Running Tests

```bash
# Run unit tests
make test

# Run integration tests
make test-integration

# Run load tests (requires k6)
make test-load

# Generate coverage report
make test-coverage-report

# Run all test types
make test-all

# Run specific test file
mojo test tests/test_suite.mojo
```

### Test Guidelines

- **Test Naming:** Use descriptive names that explain what is being tested
- **Test Structure:** Arrange-Act-Assert pattern
- **Mock Usage:** Use mocks for external dependencies (APIs, databases)
- **Edge Cases:** Test error conditions and edge cases
- **Performance:** Include performance assertions for critical paths
- **Determinism:** Tests should be deterministic and repeatable

## Documentation Requirements

### Code Documentation

- **Public APIs:** All public functions and structs must have docstrings
- **Complex Logic:** Add inline comments for complex or non-obvious code
- **Parameters:** Document all parameters with types and descriptions
- **Returns:** Document return values and possible errors
- **Examples:** Include usage examples in docstrings when helpful

**Example:**
```mojo
fn calculate_position_size(
    portfolio_value: Float64,
    risk_percentage: Float64,
    entry_price: Float64
) -> Float64:
    """Calculate optimal position size based on risk management rules.

    Args:
        portfolio_value: Total portfolio value in USD
        risk_percentage: Percentage of portfolio to risk (0.01-0.05)
        entry_price: Entry price for the position

    Returns:
        Position size in base currency units

    Raises:
        ValueError: If parameters are invalid
    """
```

### User Documentation

- **README.md:** Update for major features and breaking changes
- **Guides:** Add or update guides in `docs/` for complex features
- **Configuration:** Update configuration documentation and examples
- **Troubleshooting:** Add troubleshooting tips for common issues
- **Changelog:** Update CHANGELOG.md for all notable changes

### Documentation Standards

- **Clarity:** Write clearly and concisely
- **Accuracy:** Ensure documentation matches implementation
- **Completeness:** Document all public interfaces
- **Examples:** Provide practical examples
- **Maintenance:** Keep documentation up to date with code changes

## Security Considerations

### Before Submitting

- **Secrets Scan:** Run `make validate-secrets` to check for hardcoded secrets
- **Never Commit:** API keys, private keys, passwords, or credentials
- **Use Variables:** Use environment variables or Infisical for secrets
- **Security Review:** Report security vulnerabilities via [SECURITY.md](SECURITY.md)

### Security-Sensitive Changes

**Require Additional Review:**
- Wallet operations and cryptographic functions
- API authentication and authorization
- Network communication and data handling
- FFI boundaries and memory management
- Configuration and secrets management

**Review Process:**
- Must include security impact assessment
- May require security audit before merge
- Additional approval from security team
- Comprehensive testing required

### Security Best Practices

- **Input Validation:** Validate all external inputs
- **Error Handling:** Don't leak sensitive information in errors
- **Logging:** Don't log sensitive data (keys, passwords)
- **Dependencies:** Keep dependencies updated and vetted
- **Testing:** Include security-focused tests

## Performance Considerations

### Performance-Critical Code

- **Benchmarks:** Add benchmarks for hot paths and critical functions
- **Profiling:** Profile before optimizing (`make profile-ffi`)
- **Documentation:** Document performance impact in PR
- **Regression Testing:** Avoid performance regressions >10%

### Optimization Guidelines

- **Profile First:** Measure before optimizing
- **SIMD Usage:** Use SIMD for numerical calculations when beneficial
- **Object Pooling:** Leverage object pooling for frequent allocations
- **Batch Operations:** Batch operations to reduce FFI overhead
- **Memory Management:** Minimize allocations and copies

### Performance Testing

```bash
# Run FFI benchmarks
make bench-ffi

# Run Rust benchmarks
cd rust-modules && cargo bench

# Profile application performance
make profile-ffi
```

## Financial Software Guidelines

### Trading Logic Changes

- **Thorough Testing:** Test extensively with paper trading
- **Risk Documentation:** Document risk implications clearly
- **Backtesting:** Include backtesting results when applicable
- **Edge Cases:** Consider extreme market conditions and edge cases
- **Warnings:** Add appropriate warnings in documentation

### Risk Management

- **Conservative Defaults:** Use conservative default parameters
- **Validation:** Validate all trading parameters
- **Circuit Breakers:** Implement and test circuit breakers
- **Position Limits:** Enforce position size limits
- **Drawdown Protection:** Implement drawdown protection mechanisms

### Disclaimer Requirements

- **No Financial Advice:** Never provide financial advice
- **Educational Purpose:** Emphasize educational/research purpose
- **Risk Warnings:** Highlight risks prominently
- **User Responsibility:** Emphasize user responsibility for decisions

## Community Guidelines

### Be Respectful

- **Code of Conduct:** Follow our [Code of Conduct](CODE_OF_CONDUCT.md)
- **Professionalism:** Maintain professional and constructive communication
- **Constructive Feedback:** Provide helpful, constructive feedback
- **Patience:** Be patient with newcomers and during review process
- **Inclusivity:** Welcome contributors from all backgrounds

### Communication

- **GitHub Issues:** Use for bug reports and feature requests
- **GitHub Discussions:** Use for questions and ideas
- **Review Process:** Be responsive during code review
- **Tagging:** Tag maintainers only when necessary
- **Documentation:** Document decisions and rationale

### Help Others

- **Answer Questions:** Help newcomers in discussions and issues
- **Review Code:** Participate in code reviews when able
- **Share Knowledge:** Share what you learn with the community
- **Mentor:** Help guide new contributors through the process

## Getting Help

### Resources

- **Documentation:** `docs/` directory contains comprehensive guides
- **GitHub Issues:** Search existing issues before creating new ones
- **GitHub Discussions:** Ask questions and share ideas
- **Community Chat:** Discord/Telegram links in repository
- **Maintainers:** Contact maintainers for specific questions

### Before Asking

- **Search:** Search existing issues, discussions, and documentation
- **Read:** Read relevant documentation and guides
- **Try:** Attempt to solve the problem yourself first
- **Document:** Provide minimal reproducible example
- **Be Specific:** Include details about environment, versions, and steps

### Asking Good Questions

- **Clear Title:** Use descriptive title for issues
- **Context:** Provide context about what you're trying to accomplish
- **Steps:** List steps you've already tried
- **Error Messages:** Include complete error messages and stack traces
- **Environment:** Include OS, versions, and configuration details

## Recognition

### Contributors

- **GitHub Contributors:** All contributors listed on GitHub contributors page
- **Release Notes:** Significant contributions acknowledged in release notes
- **Security Hall of Fame:** Security researchers credited in SECURITY.md
- **Community Recognition:** Outstanding contributions highlighted in community

### Types of Recognition

- **Code Contributions:** New features, bug fixes, improvements
- **Documentation:** Documentation improvements and tutorials
- **Community:** Helping others, answering questions, organizing events
- **Security:** Responsible vulnerability disclosure
- **Performance:** Significant performance improvements

### How Recognition Works

- **Automatic:** GitHub automatically tracks code contributions
- **Manual:** Maintainers manually acknowledge other types of contributions
- **Opt-out:** Contributors can opt out of recognition if desired
- **Consent:** Always ask permission before highlighting specific individuals

## License

### License Agreement

By contributing to this project, you agree that your contributions will be licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

### No CLA Required

- We do not require a Contributor License Agreement (CLA)
- MIT License provides sufficient clarity for contributions
- Contributors retain copyright to their own work
- Project as a whole is licensed under MIT

### Developer Certificate of Origin (DCO)

While not required, we appreciate contributors who:

- Sign-off their commits indicating they have the right to contribute
- Ensure they have the legal right to contribute the code
- Understand the contribution will be licensed under MIT

---

## Thank You!

Thank you for considering contributing to MojoRust Trading Bot! Your contributions help make this project better and more valuable to the community.

### Getting Started Checklist

- [ ] Read this contributing guide
- [ ] Read the [Code of Conduct](CODE_OF_CONDUCT.md)
- [ ] Set up development environment: `make setup-dev`
- [ ] Find a good first issue or propose a new one
- [ ] Join our community discussions
- [ ] Ask questions if you need help

### We Value

- **Your Time:** We appreciate the time you invest in contributing
- **Your Ideas:** New perspectives and approaches are welcome
- **Your Skills:** Every skill level has something valuable to contribute
- **Your Feedback:** Help us improve the project and community

### Together We Can

- Build better trading software
- Create a welcoming community
- Learn from each other
- Advance financial technology
- Make trading more accessible

**Happy contributing! 🚀**