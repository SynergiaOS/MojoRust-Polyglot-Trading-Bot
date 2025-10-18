use anyhow::Result;
use clap::{Arg, Command};
use log::{error, info, warn};
use std::env;
use std::time::Duration;

mod test_complete_trading_flow;
mod test_integration_scenarios;

use mojorust_e2e_tests::*;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    env_logger::init();

    // Parse command line arguments
    let matches = Command::new("MojoRust E2E Test Runner")
        .version("1.0.0")
        .about("End-to-end test suite for MojoRust trading bot")
        .arg(
            Arg::new("mode")
                .short('m')
                .long("mode")
                .value_name("MODE")
                .help("Test mode: simulation, paper-trading, live-trading")
                .default_value("simulation")
                .possible_values(["simulation", "paper-trading", "live-trading"]),
        )
        .arg(
            Arg::new("test")
                .short('t')
                .long("test")
                .value_name("TEST")
                .help("Specific test to run (or 'all')")
                .default_value("all")
                .possible_values([
                    "all",
                    "trading_flow",
                    "helius_laserstream",
                    "quicknode_liljit",
                    "arbitrage",
                    "monitoring",
                    "risk_management",
                    "webhook_system",
                    "market_volatility",
                    "flash_loan_stress",
                    "multi_dex_liquidity",
                    "risk_emergency",
                    "network_congestion",
                    "data_pipeline_integrity",
                ]),
        )
        .arg(
            Arg::new("timeout")
                .short('T')
                .long("timeout")
                .value_name("SECONDS")
                .help("Maximum test duration in seconds")
                .default_value("600"),
        )
        .arg(
            Arg::new("parallel")
                .short('p')
                .long("parallel")
                .help("Run tests in parallel where possible")
                .action(clap::ArgAction::SetTrue),
        )
        .arg(
            Arg::new("verbose")
                .short('v')
                .long("verbose")
                .help("Verbose output")
                .action(clap::ArgAction::SetTrue),
        )
        .get_matches();

    // Validate environment
    validate_environment(&matches).await?;

    // Set test mode
    let test_mode = matches.get_one::<String>("mode").unwrap();
    env::set_var("TEST_MODE", test_mode);

    // Show warning for live trading
    if test_mode == "live-trading" {
        warn!("⚠️  WARNING: LIVE TRADING MODE ENABLED!");
        warn!("⚠️  This will execute REAL transactions with REAL funds!");
        warn!("⚠️  Please confirm you understand the risks!");

        // Ask for confirmation
        if !confirm_live_trading()? {
            error!("Live trading test cancelled by user");
            std::process::exit(1);
        }
    }

    info!("🚀 Starting MojoRust E2E Test Suite");
    info!("📊 Test Mode: {}", test_mode);
    info!("⏱️ Timeout: {} seconds", matches.get_one::<String>("timeout").unwrap());

    // Load environment variables
    dotenvy::dotenv().ok();

    // Run tests based on selection
    let test_to_run = matches.get_one::<String>("test").unwrap();
    let timeout_duration = Duration::from_secs(
        matches.get_one::<String>("timeout")
            .unwrap()
            .parse::<u64>()
            .unwrap_or(600),
    );

    let results = match test_to_run.as_str() {
        "all" => run_all_tests(timeout_duration).await,
        "trading_flow" => run_test("Complete Trading Flow", test_complete_trading_flow::test_complete_trading_flow_e2e, timeout_duration).await,
        "helius_laserstream" => run_test("Helius LaserStream Integration", test_complete_trading_flow::test_helius_laserstream_integration_e2e, timeout_duration).await,
        "quicknode_liljit" => run_test("QuickNode Lil' JIT Integration", test_complete_trading_flow::test_quicknode_liljit_e2e, timeout_duration).await,
        "arbitrage" => run_test("Arbitrage Flow", test_complete_trading_flow::test_arbitrage_flow_e2e, timeout_duration).await,
        "monitoring" => run_test("Monitoring Stack", test_complete_trading_flow::test_monitoring_stack_e2e, timeout_duration).await,
        "risk_management" => run_test("Risk Management", test_complete_trading_flow::test_risk_management_e2e, timeout_duration).await,
        "webhook_system" => run_test("Webhook System", test_complete_trading_flow::test_webhook_system_e2e, timeout_duration).await,
        "market_volatility" => run_test("Market Volatility Scenario", test_integration_scenarios::test_market_volatility_scenario, timeout_duration).await,
        "flash_loan_stress" => run_test("Flash Loan Stress Test", test_integration_scenarios::test_flash_loan_stress_test, timeout_duration).await,
        "multi_dex_liquidity" => run_test("Multi-DEX Liquidity Scenario", test_integration_scenarios::test_multi_dex_liquidity_scenario, timeout_duration).await,
        "risk_emergency" => run_test("Risk Emergency Scenario", test_integration_scenarios::test_risk_emergency_scenario, timeout_duration).await,
        "network_congestion" => run_test("Network Congestion Scenario", test_integration_scenarios::test_network_congestion_scenario, timeout_duration).await,
        "data_pipeline_integrity" => run_test("Data Pipeline Integrity Scenario", test_integration_scenarios::test_data_pipeline_integrity_scenario, timeout_duration).await,
        _ => {
            error!("Unknown test: {}", test_to_run);
            std::process::exit(1);
        }
    };

    // Display results
    display_test_results(&results);

    // Exit with appropriate code
    if results.all_passed() {
        info!("✅ All tests passed!");
        std::process::exit(0);
    } else {
        error!("❌ Some tests failed!");
        std::process::exit(1);
    }
}

async fn validate_environment(matches: &clap::ArgMatches) -> Result<()> {
    info!("🔍 Validating test environment...");

    // Verify environment variables
    verify_environment_variables().await?;

    // Check Docker environment if available
    if let Err(e) = setup_test_docker_environment().await {
        warn!("Docker environment check failed: {}", e);
        warn!("Some tests may fail without Docker services running");
    }

    // Validate test configuration
    let config = TestConfig::from_env()?;
    let validator = TestValidator::new(config);
    validator.validate_test_environment()?;

    info!("✅ Environment validation completed");
    Ok(())
}

async fn run_all_tests(timeout_duration: Duration) -> TestSuiteResults {
    info!("🧪 Running all E2E tests...");

    let mut results = TestSuiteResults::new();

    // Core integration tests
    results.add_result("Complete Trading Flow",
        run_test_with_timeout(test_complete_trading_flow::test_complete_trading_flow_e2e, timeout_duration).await);

    results.add_result("Helius LaserStream Integration",
        run_test_with_timeout(test_complete_trading_flow::test_helius_laserstream_integration_e2e, timeout_duration).await);

    results.add_result("QuickNode Lil' JIT Integration",
        run_test_with_timeout(test_complete_trading_flow::test_quicknode_liljit_e2e, timeout_duration).await);

    results.add_result("Arbitrage Flow",
        run_test_with_timeout(test_complete_trading_flow::test_arbitrage_flow_e2e, timeout_duration).await);

    results.add_result("Monitoring Stack",
        run_test_with_timeout(test_complete_trading_flow::test_monitoring_stack_e2e, timeout_duration).await);

    results.add_result("Risk Management",
        run_test_with_timeout(test_complete_trading_flow::test_risk_management_e2e, timeout_duration).await);

    results.add_result("Webhook System",
        run_test_with_timeout(test_complete_trading_flow::test_webhook_system_e2e, timeout_duration).await);

    // Scenario tests
    results.add_result("Market Volatility Scenario",
        run_test_with_timeout(test_integration_scenarios::test_market_volatility_scenario, timeout_duration).await);

    results.add_result("Flash Loan Stress Test",
        run_test_with_timeout(test_integration_scenarios::test_flash_loan_stress_test, timeout_duration).await);

    results.add_result("Multi-DEX Liquidity Scenario",
        run_test_with_timeout(test_integration_scenarios::test_multi_dex_liquidity_scenario, timeout_duration).await);

    results.add_result("Risk Emergency Scenario",
        run_test_with_timeout(test_integration_scenarios::test_risk_emergency_scenario, timeout_duration).await);

    results.add_result("Network Congestion Scenario",
        run_test_with_timeout(test_integration_scenarios::test_network_congestion_scenario, timeout_duration).await);

    results.add_result("Data Pipeline Integrity Scenario",
        run_test_with_timeout(test_integration_scenarios::test_data_pipeline_integrity_scenario, timeout_duration).await);

    results
}

async fn run_test(
    test_name: &str,
    test_fn: impl std::future::Future<Output = Result<()>>,
    timeout_duration: Duration,
) -> TestResult {
    run_test_with_timeout(test_fn, timeout_duration).await.with_test_name(test_name.to_string())
}

async fn run_test_with_timeout(
    test_fn: impl std::future::Future<Output = Result<()>>,
    timeout_duration: Duration,
) -> TestResult {
    let start_time = std::time::Instant::now();

    match tokio::time::timeout(timeout_duration, test_fn).await {
        Ok(Ok(())) => {
            TestResult {
                name: "test".to_string(), // Will be set by caller
                status: TestStatus::Passed,
                duration: start_time.elapsed(),
                error: None,
            }
        }
        Ok(Err(e)) => {
            TestResult {
                name: "test".to_string(), // Will be set by caller
                status: TestStatus::Failed,
                duration: start_time.elapsed(),
                error: Some(format!("Test failed: {}", e)),
            }
        }
        Err(_) => {
            TestResult {
                name: "test".to_string(), // Will be set by caller
                status: TestStatus::Timeout,
                duration: start_time.elapsed(),
                error: Some(format!("Test timed out after {:?}", timeout_duration)),
            }
        }
    }
}

fn confirm_live_trading() -> Result<bool> {
    print!("Are you absolutely sure you want to run LIVE TRADING tests? (yes/no): ");
    std::io::Write::flush(&mut std::io::stdout())?;

    let mut input = String::new();
    std::io::stdin().read_line(&mut input)?;

    let confirmation = input.trim().to_lowercase();
    match confirmation.as_str() {
        "yes" | "y" => Ok(true),
        "no" | "n" => Ok(false),
        _ => {
            println!("Invalid input. Please enter 'yes' or 'no'.");
            confirm_live_trading()
        }
    }
}

#[derive(Debug, Clone)]
struct TestSuiteResults {
    results: Vec<TestResult>,
}

impl TestSuiteResults {
    fn new() -> Self {
        Self {
            results: Vec::new(),
        }
    }

    fn add_result(&mut self, test_name: &str, result: TestResult) {
        let mut result = result;
        result.name = test_name.to_string();
        self.results.push(result);
    }

    fn all_passed(&self) -> bool {
        self.results.iter().all(|r| matches!(r.status, TestStatus::Passed))
    }

    fn passed_count(&self) -> usize {
        self.results.iter().filter(|r| matches!(r.status, TestStatus::Passed)).count()
    }

    fn failed_count(&self) -> usize {
        self.results.iter().filter(|r| matches!(r.status, TestStatus::Failed)).count()
    }

    fn timeout_count(&self) -> usize {
        self.results.iter().filter(|r| matches!(r.status, TestStatus::Timeout)).count()
    }

    fn total_duration(&self) -> Duration {
        self.results.iter().map(|r| r.duration).sum()
    }
}

#[derive(Debug, Clone)]
struct TestResult {
    name: String,
    status: TestStatus,
    duration: Duration,
    error: Option<String>,
}

impl TestResult {
    fn with_test_name(mut self, name: String) -> Self {
        self.name = name;
        self
    }
}

fn display_test_results(results: &TestSuiteResults) {
    println!("\n" + "=".repeat(80).as_str());
    println!("🧪 MOJORUST E2E TEST RESULTS");
    println!("=".repeat(80));

    for result in &results.results {
        let status_icon = match result.status {
            TestStatus::Passed => "✅",
            TestStatus::Failed => "❌",
            TestStatus::Timeout => "⏰",
            TestStatus::Skipped => "⏭️",
        };

        println!(
            "{} {} - {:?} ({})",
            status_icon,
            result.name,
            result.status,
            format_duration(result.duration)
        );

        if let Some(error) = &result.error {
            println!("    Error: {}", error);
        }
    }

    println!("\n" + "-".repeat(80).as_str());
    println!("📊 SUMMARY:");
    println!("  Total Tests: {}", results.results.len());
    println!("  Passed: {} ({:.1}%)", results.passed_count(),
        results.passed_count() as f64 / results.results.len() as f64 * 100.0);
    println!("  Failed: {} ({:.1}%)", results.failed_count(),
        results.failed_count() as f64 / results.results.len() as f64 * 100.0);
    println!("  Timeout: {} ({:.1}%)", results.timeout_count(),
        results.timeout_count() as f64 / results.results.len() as f64 * 100.0);
    println!("  Total Duration: {}", format_duration(results.total_duration()));
    println!("-".repeat(80));

    if results.all_passed() {
        println!("🎉 All tests completed successfully!");
    } else {
        println!("⚠️ Some tests failed. Please review the errors above.");
    }
}

fn format_duration(duration: Duration) -> String {
    let total_seconds = duration.as_secs();
    let minutes = total_seconds / 60;
    let seconds = total_seconds % 60;
    let milliseconds = duration.subsec_millis();

    if minutes > 0 {
        format!("{}m {}s {}ms", minutes, seconds, milliseconds)
    } else if seconds > 0 {
        format!("{}s {}ms", seconds, milliseconds)
    } else {
        format!("{}ms", milliseconds)
    }
}