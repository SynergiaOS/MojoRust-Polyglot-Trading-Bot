//! Backtesting Module
//!
//! Comprehensive backtesting infrastructure for the MojoRust trading bot.
//! This module provides historical data collection, advanced backtesting engine
//! with all 12 trading filters, and detailed performance analytics.
//!
//! Features:
//! - Historical data collection from multiple sources
//! - 12 trading filter strategies testing
//! - Realistic market simulation with slippage and fees
//! - Advanced performance analytics and risk metrics
//! - Performance attribution and benchmark comparison
//! - Visualization and reporting capabilities

pub mod historical_data;
pub mod engine;
pub mod analytics;

// Re-export main types for easier access
pub use historical_data::{
    HistoricalDataCollector, HistoricalDataConfig, OHLCVData, PoolSnapshot,
    Timeframe, DataSource, TransactionData, TransactionType
};

pub use engine::{
    BacktestEngine, BacktestConfig, BacktestResults, TradingSignal,
    FilterType, SignalType, Trade, TradeAction, Position
};

pub use analytics::{
    PerformanceAnalytics, PerformanceMetrics, OverallMetrics, RiskMetrics,
    ReturnMetrics, TradeMetrics, MonthlyAnalysis, PerformanceAttribution
};

/// Backtesting framework entry point
pub struct BacktestingFramework {
    data_collector: Arc<HistoricalDataCollector>,
    analytics_engine: PerformanceAnalytics,
}

impl BacktestingFramework {
    /// Create new backtesting framework
    pub async fn new(
        historical_config: HistoricalDataConfig,
        db_url: &str,
        rpc_url: &str,
        risk_free_rate: f64,
    ) -> Result<Self> {
        let data_collector = Arc::new(
            HistoricalDataCollector::new(historical_config, db_url, rpc_url).await?
        );
        let analytics_engine = PerformanceAnalytics::new(risk_free_rate);

        Ok(Self {
            data_collector,
            analytics_engine,
        })
    }

    /// Run comprehensive backtesting for all filters
    pub async fn run_comprehensive_backtesting(
        &self,
        backtest_config: BacktestConfig,
    ) -> Result<Vec<PerformanceMetrics>> {
        info!("Starting comprehensive backtesting for {} filters", backtest_config.filters_to_test.len());

        let mut engine = BacktestEngine::new(backtest_config.clone(), self.data_collector.clone()).await?;
        let all_results = engine.run_all_backtests().await?;

        let mut all_metrics = Vec::new();
        for results in all_results {
            let metrics = self.analytics_engine.analyze_results(&results)?;
            all_metrics.push(metrics);
        }

        // Generate comparison
        let result_refs: Vec<&BacktestResults> = all_results.iter().collect();
        self.analytics_engine.compare_filters(&result_refs)?;

        // Generate reports for each filter
        for metrics in &all_metrics {
            let report = self.analytics_engine.generate_performance_report(metrics)?;
            info!("Performance Report for {}:\n{}", metrics.filter_type.name(), report);
        }

        Ok(all_metrics)
    }

    /// Run backtesting for a specific filter
    pub async fn run_single_filter_backtesting(
        &self,
        backtest_config: BacktestConfig,
        filter_type: FilterType,
    ) -> Result<PerformanceMetrics> {
        info!("Running backtesting for filter: {}", filter_type.name());

        let config = BacktestConfig {
            filters_to_test: vec![filter_type],
            ..backtest_config
        };

        let mut engine = BacktestEngine::new(config, self.data_collector.clone()).await?;
        let results = engine.run_backtest(filter_type).await?;
        let metrics = self.analytics_engine.analyze_results(&results)?;

        // Generate report
        let report = self.analytics_engine.generate_performance_report(&metrics)?;
        info!("Performance Report for {}:\n{}", metrics.filter_type.name(), report);

        Ok(metrics)
    }

    /// Get historical data collector
    pub fn data_collector(&self) -> &Arc<HistoricalDataCollector> {
        &self.data_collector
    }

    /// Get analytics engine
    pub fn analytics_engine(&self) -> &PerformanceAnalytics {
        &self.analytics_engine
    }
}

/// Create default backtesting configuration
pub fn create_default_backtest_config() -> BacktestConfig {
    use chrono::NaiveDate;

    BacktestConfig {
        start_date: NaiveDate::from_ymd_opt(2023, 1, 1).unwrap().and_hms_opt(0, 0, 0).unwrap(),
        end_date: NaiveDate::from_ymd_opt(2023, 12, 31).unwrap().and_hms_opt(23, 59, 59).unwrap(),
        initial_capital: 100000.0,
        max_position_size: 10000.0,
        commission_rate: 0.001,
        slippage_rate: 0.0005,
        filters_to_test: FilterType::all_filters(),
        timeframe: Timeframe::OneHour,
        symbols: vec![
            "So11111111111111111111111111111111111111112".to_string(), // SOL
            "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v".to_string(), // USDC
            "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB".to_string(), // USDT
            "3NZ9JMVBmGAqocybic2KjQTYjwrLJSZGW3G4XvmaB8im".to_string(), // WBTC
            "Cwe8jPTkAirWEuiSHDgr7EBsl5S71TB3B9Dhnrx7cwnA".to_string(), // LINK
            "5qKyBumD1kcngvZE3Qp6UknYnojx7aPAJNdLMFjUtwg5".to_string(), // USDE
            "USDSes911MNNu1xA68HKmNafBvn1i9qEse7YhKqwDgHq".to_string(), // USDS
            "9n4nbM75fEuUiS8GWQhE4DqPyyGtRwNUJmrM3DHUyDy8".to_string(), // CBBTC
            "8hFgUeVwB6xFq7dUa8JW4sBQwJY9iHqKv9XGvKx9qZq".to_string(), // SUSDE
            "7vfCXTVGxZ5pZvKqzZTqFpMqHvqJvN5SLgXaR9Jv9JvK".to_string(), // WLFI
        ],
        enable_compounding: true,
        risk_free_rate: 0.02,
        benchmark_return: 0.10,
    }
}

/// Create default historical data configuration
pub fn create_default_historical_config() -> HistoricalDataConfig {
    use chrono::NaiveDate;

    HistoricalDataConfig {
        data_sources: vec![
            DataSource {
                name: "Helius".to_string(),
                endpoint_url: "https://api.helius.xyz".to_string(),
                api_key: Some("your_api_key".to_string()),
                rate_limit_per_second: 10,
                supported_tokens: vec![
                    "So11111111111111111111111111111111111111112".to_string(),
                    "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v".to_string(),
                    "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB".to_string(),
                    "3NZ9JMVBmGAqocybic2KjQTYjwrLJSZGW3G4XvmaB8im".to_string(),
                    "Cwe8jPTkAirWEuiSHDgr7EBsl5S71TB3B9Dhnrx7cwnA".to_string(),
                    "5qKyBumD1kcngvZE3Qp6UknYnojx7aPAJNdLMFjUtwg5".to_string(),
                    "USDSes911MNNu1xA68HKmNafBvn1i9qEse7YhKqwDgHq".to_string(),
                    "9n4nbM75fEuUiS8GWQhE4DqPyyGtRwNUJmrM3DHUyDy8".to_string(),
                    "8hFgUeVwB6xFq7dUa8JW4sBQwJY9iHqKv9XGvKx9qZq".to_string(),
                    "7vfCXTVGxZ5pZvKqzZTqFpMqHvqJvN5SLgXaR9Jv9JvK".to_string(),
                ],
                supported_dexes: vec![
                    "Orca".to_string(),
                    "Raydium".to_string(),
                    "Serum".to_string(),
                    "Jupiter".to_string(),
                ],
            },
        ],
        timeframes: vec![
            Timeframe::OneMinute,
            Timeframe::FiveMinutes,
            Timeframe::FifteenMinutes,
            Timeframe::OneHour,
            Timeframe::FourHours,
            Timeframe::OneDay,
        ],
        start_date: NaiveDate::from_ymd_opt(2023, 1, 1).unwrap().and_hms_opt(0, 0, 0).unwrap(),
        end_date: None, // Collect up to current date
        batch_size: 1000,
        max_concurrent_requests: 5,
        data_retention_days: 365,
        compression_enabled: true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_default_configs() {
        let backtest_config = create_default_backtest_config();
        assert_eq!(backtest_config.initial_capital, 100000.0);
        assert_eq!(backtest_config.filters_to_test.len(), 12);

        let historical_config = create_default_historical_config();
        assert_eq!(historical_config.timeframes.len(), 6);
        assert_eq!(historical_config.data_sources.len(), 1);
    }

    #[test]
    fn test_filter_types() {
        let filters = FilterType::all_filters();
        assert_eq!(filters.len(), 12);
        assert!(filters.contains(&FilterType::MovingAverageCrossover));
        assert!(filters.contains(&FilterType::SupportResistance));

        for filter in &filters {
            assert!(!filter.name().is_empty());
        }
    }
}