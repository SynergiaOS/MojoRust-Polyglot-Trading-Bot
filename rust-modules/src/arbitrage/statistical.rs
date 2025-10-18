//! Advanced Statistical Arbitrage Detection
//!
//! This module provides comprehensive statistical arbitrage detection capabilities
//! including pairs trading, cointegration testing, z-score calculations, and
//! mean reversion strategies optimized for Solana meme token markets.

use crate::arbitrage::{ArbitrageOpportunity, ArbitrageConfig};
use anyhow::{Result, anyhow};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tokio::time::{Duration, Instant};
use log::{debug, info, warn, error};

/// Trading pair for statistical arbitrage
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TradingPair {
    pub token_a: String,
    pub token_b: String,
    pub symbol_a: String,
    pub symbol_b: String,
    pub correlation: f64,
    pub hedge_ratio: f64,
    pub cointegration_p_value: f64,
    pub is_cointegrated: bool,
    pub last_updated: u64,
}

/// Price history data for statistical analysis
#[derive(Debug, Clone)]
pub struct PriceHistory {
    pub timestamps: Vec<u64>,
    pub prices_a: Vec<f64>,
    pub prices_b: Vec<f64>,
    pub returns_a: Vec<f64>,
    pub returns_b: Vec<f64>,
    pub spread: Vec<f64>,
    pub z_scores: Vec<f64>,
}

/// Statistical arbitrage opportunity with enhanced metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StatisticalOpportunity {
    pub pair: TradingPair,
    pub current_price_a: f64,
    pub current_price_b: f64,
    pub current_spread: f64,
    pub current_z_score: f64,
    pub expected_spread_mean: f64,
    pub spread_std_dev: f64,
    pub deviation_percentage: f64,
    pub confidence_score: f64,
    pub signal_type: ArbitrageSignal,  // LONG_A_SHORT_B, SHORT_A_LONG_B, CLOSE
    pub holding_period_secs: u64,
    pub expected_return: f64,
    pub risk_score: f64,
    pub entry_threshold: f64,
    pub exit_threshold: f64,
    pub stop_loss_threshold: f64,
    pub half_life: f64,  // Mean reversion half-life
    pub hurst_exponent: f64,  // Mean reversion vs momentum indicator
}

/// Arbitrage signal types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ArbitrageSignal {
    LongAShortB,   // Long token A, Short token B (spread too wide)
    ShortALongB,   // Short token A, Long token B (spread too narrow)
    ClosePosition, // Close existing position
    NoSignal,      // No trading signal
}

/// Statistical arbitrage configuration
#[derive(Debug, Clone)]
pub struct StatisticalConfig {
    pub min_correlation: f64,
    pub max_correlation: f64,
    pub cointegration_significance: f64,
    pub entry_z_threshold: f64,
    pub exit_z_threshold: f64,
    pub stop_loss_z_threshold: f64,
    pub min_history_points: usize,
    pub max_history_points: usize,
    pub update_interval_secs: u64,
    pub half_life_window: usize,
    pub min_profit_bps: i32,
    pub max_position_size_usd: f64,
}

impl Default for StatisticalConfig {
    fn default() -> Self {
        Self {
            min_correlation: 0.3,
            max_correlation: 0.95,
            cointegration_significance: 0.05,
            entry_z_threshold: 2.0,
            exit_z_threshold: 0.5,
            stop_loss_z_threshold: 4.0,
            min_history_points: 100,
            max_history_points: 1000,
            update_interval_secs: 60,
            half_life_window: 50,
            min_profit_bps: 25,  // 0.25%
            max_position_size_usd: 5000.0,
        }
    }
}

/// Advanced statistical arbitrage detector
pub struct StatisticalDetector {
    config: ArbitrageConfig,
    stat_config: StatisticalConfig,
    price_histories: HashMap<String, PriceHistory>,
    trading_pairs: HashMap<String, TradingPair>,
    last_update: Instant,
    opportunities: Vec<StatisticalOpportunity>,
}

impl StatisticalDetector {
    pub fn new(config: ArbitrageConfig) -> Self {
        let stat_config = StatisticalConfig::default();

        Self {
            config,
            stat_config,
            price_histories: HashMap::new(),
            trading_pairs: HashMap::new(),
            last_update: Instant::now(),
            opportunities: Vec::new(),
        }
    }

    pub fn with_stat_config(mut self, stat_config: StatisticalConfig) -> Self {
        self.stat_config = stat_config;
        self
    }

    /// Detect statistical arbitrage opportunities across all monitored pairs
    pub async fn detect_opportunities(&mut self) -> Result<Vec<StatisticalOpportunity>> {
        debug!("Starting statistical arbitrage detection");

        // Update price histories
        self.update_price_histories().await?;

        // Analyze all trading pairs
        let mut new_opportunities = Vec::new();

        for (pair_key, pair) in &self.trading_pairs.clone() {
            if let Some(history) = self.price_histories.get(pair_key) {
                // Analyze pair for opportunities
                if let Some(opportunity) = self.analyze_pair(pair, history).await? {
                    new_opportunities.push(opportunity);
                }
            }
        }

        self.opportunities = new_opportunities.clone();
        self.last_update = Instant::now();

        info!("Detected {} statistical arbitrage opportunities", new_opportunities.len());
        Ok(new_opportunities)
    }

    /// Update price histories for all tokens
    async fn update_price_histories(&mut self) -> Result<()> {
        // This would integrate with Jupiter Price API or other price sources
        // For now, simulate price updates

        for token in &self.config.monitored_tokens {
            self.update_token_price_history(token).await?;
        }

        Ok(())
    }

    /// Update price history for a specific token
    async fn update_token_price_history(&mut self, token: &str) -> Result<()> {
        // In production, this would fetch real prices from Jupiter API
        let current_price = self.fetch_token_price(token).await?;
        let current_time = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs();

        // Initialize or update history
        let history = self.price_histories.entry(token.to_string()).or_insert_with(|| {
            PriceHistory {
                timestamps: Vec::new(),
                prices_a: Vec::new(),
                prices_b: Vec::new(),
                returns_a: Vec::new(),
                returns_b: Vec::new(),
                spread: Vec::new(),
                z_scores: Vec::new(),
            }
        });

        // Add new price point
        history.timestamps.push(current_time);

        // Update histories for all pairs involving this token
        for other_token in &self.config.monitored_tokens {
            if other_token != token {
                let pair_key = format!("{}-{}", token, other_token);
                let other_price = self.fetch_token_price(other_token).await?;

                // Update pair-specific history
                self.update_pair_history(&pair_key, token, other_token, current_price, other_price).await?;
            }
        }

        Ok(())
    }

    /// Update history for a specific trading pair
    async fn update_pair_history(&mut self, pair_key: &str, token_a: &str, token_b: &str, price_a: f64, price_b: f64) -> Result<()> {
        let history = self.price_histories.entry(pair_key.to_string()).or_insert_with(|| {
            PriceHistory {
                timestamps: Vec::new(),
                prices_a: Vec::new(),
                prices_b: Vec::new(),
                returns_a: Vec::new(),
                returns_b: Vec::new(),
                spread: Vec::new(),
                z_scores: Vec::new(),
            }
        });

        // Add price data
        history.prices_a.push(price_a);
        history.prices_b.push(price_b);

        // Calculate returns
        if history.prices_a.len() > 1 {
            let return_a = (price_a / history.prices_a[history.prices_a.len() - 2]) - 1.0;
            let return_b = (price_b / history.prices_b[history.prices_b.len() - 2]) - 1.0;
            history.returns_a.push(return_a);
            history.returns_b.push(return_b);
        }

        // Update trading pair analysis if we have enough data
        if history.prices_a.len() >= self.stat_config.min_history_points {
            self.update_trading_pair(pair_key, token_a, token_b, history).await?;
        }

        // Limit history size
        if history.prices_a.len() > self.stat_config.max_history_points {
            let remove_count = history.prices_a.len() - self.stat_config.max_history_points;
            history.timestamps.drain(0..remove_count);
            history.prices_a.drain(0..remove_count);
            history.prices_b.drain(0..remove_count);
            history.returns_a.drain(0..remove_count);
            history.returns_b.drain(0..remove_count);
            history.spread.drain(0..remove_count);
            history.z_scores.drain(0..remove_count);
        }

        Ok(())
    }

    /// Update trading pair statistics
    async fn update_trading_pair(&mut self, pair_key: &str, token_a: &str, token_b: &str, history: &PriceHistory) -> Result<()> {
        // Calculate correlation
        let correlation = self.calculate_correlation(&history.returns_a, &history.returns_b)?;

        // Test for cointegration
        let (hedge_ratio, cointegration_p_value) = self.test_cointegration(&history.prices_a, &history.prices_b)?;

        // Calculate spread using hedge ratio
        let mut spread = Vec::new();
        for (price_a, price_b) in history.prices_a.iter().zip(history.prices_b.iter()) {
            spread.push(price_a - hedge_ratio * price_b);
        }

        // Calculate z-scores for spread
        let spread_mean = self.calculate_mean(&spread);
        let spread_std = self.calculate_std(&spread, spread_mean);
        let z_scores: Vec<f64> = spread.iter().map(|s| (s - spread_mean) / spread_std).collect();

        // Calculate Hurst exponent for mean reversion
        let hurst_exponent = self.calculate_hurst_exponent(&spread)?;

        // Calculate half-life of mean reversion
        let half_life = self.calculate_half_life(&spread)?;

        // Update or create trading pair
        let pair = TradingPair {
            token_a: token_a.to_string(),
            token_b: token_b.to_string(),
            symbol_a: self.get_token_symbol(token_a),
            symbol_b: self.get_token_symbol(token_b),
            correlation,
            hedge_ratio,
            cointegration_p_value,
            is_cointegrated: cointegration_p_value < self.stat_config.cointegration_significance,
            last_updated: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)?
                .as_secs(),
        };

        self.trading_pairs.insert(pair_key.to_string(), pair);

        // Update history with calculated values
        if let Some(h) = self.price_histories.get_mut(pair_key) {
            h.spread = spread;
            h.z_scores = z_scores;
        }

        Ok(())
    }

    /// Analyze a specific pair for arbitrage opportunities
    async fn analyze_pair(&self, pair: &TradingPair, history: &PriceHistory) -> Result<Option<StatisticalOpportunity>> {
        // Skip if not enough data or not cointegrated
        if history.prices_a.len() < self.stat_config.min_history_points || !pair.is_cointegrated {
            return Ok(None);
        }

        // Skip if correlation is too high or too low
        if pair.correlation < self.stat_config.min_correlation || pair.correlation > self.stat_config.max_correlation {
            return Ok(None);
        }

        let current_z_score = if let Some(last_z) = history.z_scores.last() {
            *last_z
        } else {
            return Ok(None);
        };

        let current_spread = if let Some(last_spread) = history.spread.last() {
            *last_spread
        } else {
            return Ok(None);
        };

        let spread_mean = self.calculate_mean(&history.spread);
        let spread_std = self.calculate_std(&history.spread, spread_mean);

        // Determine signal based on z-score
        let signal_type = if current_z_score > self.stat_config.entry_z_threshold {
            ArbitrageSignal::ShortALongB  // Spread too wide, short A long B
        } else if current_z_score < -self.stat_config.entry_z_threshold {
            ArbitrageSignal::LongAShortB  // Spread too narrow, long A short B
        } else if current_z_score.abs() < self.stat_config.exit_z_threshold {
            ArbitrageSignal::ClosePosition  # Mean reversion achieved, close position
        } else {
            ArbitrageSignal::NoSignal
        };

        // Skip if no signal
        if matches!(signal_type, ArbitrageSignal::NoSignal) {
            return Ok(None);
        }

        // Calculate expected return and confidence
        let expected_return = self.calculate_expected_return(current_z_score, spread_std, &signal_type)?;
        let confidence_score = self.calculate_confidence_score(
            current_z_score,
            pair.correlation,
            pair.cointegration_p_value,
            pair.hurst_exponent
        );

        // Calculate risk score
        let risk_score = self.calculate_risk_score(
            current_z_score,
            spread_std,
            pair.hurst_exponent,
            pair.correlation
        );

        // Only proceed if minimum confidence and profit thresholds are met
        if confidence_score < 0.3 || expected_return < (self.stat_config.min_profit_bps as f64 / 10000.0) {
            return Ok(None);
        }

        // Calculate holding period based on half-life
        let holding_period_secs = (pair.half_life * 3600.0) as u64;  // Convert hours to seconds

        let opportunity = StatisticalOpportunity {
            pair: pair.clone(),
            current_price_a: history.prices_a[history.prices_a.len() - 1],
            current_price_b: history.prices_b[history.prices_b.len() - 1],
            current_spread,
            current_z_score,
            expected_spread_mean: spread_mean,
            spread_std,
            deviation_percentage: (current_spread - spread_mean).abs() / spread_mean * 100.0,
            confidence_score,
            signal_type,
            holding_period_secs,
            expected_return,
            risk_score,
            entry_threshold: self.stat_config.entry_z_threshold,
            exit_threshold: self.stat_config.exit_z_threshold,
            stop_loss_threshold: self.stat_config.stop_loss_z_threshold,
            half_life: pair.half_life,
            hurst_exponent: pair.hurst_exponent,
        };

        Ok(Some(opportunity))
    }

    /// Calculate Pearson correlation coefficient
    fn calculate_correlation(&self, x: &[f64], y: &[f64]) -> Result<f64> {
        if x.len() != y.len() || x.len() < 2 {
            return Ok(0.0);
        }

        let n = x.len() as f64;
        let mean_x = self.calculate_mean(x);
        let mean_y = self.calculate_mean(y);

        let mut numerator = 0.0;
        let mut sum_sq_x = 0.0;
        let mut sum_sq_y = 0.0;

        for (xi, yi) in x.iter().zip(y.iter()) {
            let dx = xi - mean_x;
            let dy = yi - mean_y;
            numerator += dx * dy;
            sum_sq_x += dx * dx;
            sum_sq_y += dy * dy;
        }

        let denominator = (sum_sq_x * sum_sq_y).sqrt();

        if denominator == 0.0 {
            return Ok(0.0);
        }

        Ok(numerator / denominator)
    }

    /// Test for cointegration using Engle-Granger two-step method
    pub fn test_cointegration(&self, x: &[f64], y: &[f64]) -> Result<(f64, f64)> {
        // Step 1: Run regression to find hedge ratio
        let (hedge_ratio, residuals) = self.linear_regression(x, y)?;

        // Step 2: Run ADF test on residuals
        let p_value = self.adf_test(&residuals)?;

        Ok((hedge_ratio, p_value))
    }

    /// Simple linear regression (y = alpha + beta * x)
    pub fn linear_regression(&self, x: &[f64], y: &[f64]) -> Result<(f64, Vec<f64>)> {
        if x.len() != y.len() || x.len() < 2 {
            return Ok((1.0, Vec::new()));
        }

        let n = x.len() as f64;
        let sum_x = x.iter().sum::<f64>();
        let sum_y = y.iter().sum::<f64>();
        let sum_xy = x.iter().zip(y.iter()).map(|(xi, yi)| xi * yi).sum::<f64>();
        let sum_x2 = x.iter().map(|xi| xi * xi).sum::<f64>();

        let beta = (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x);
        let alpha = (sum_y - beta * sum_x) / n;

        // Calculate residuals
        let residuals: Vec<f64> = y.iter().zip(x.iter())
            .map(|(yi, xi)| yi - (alpha + beta * xi))
            .collect();

        Ok((beta, residuals))
    }

    /// Augmented Dickey-Fuller test (simplified implementation)
    pub fn adf_test(&self, series: &[f64]) -> Result<f64> {
        // This is a simplified ADF test implementation
        // In production, use a proper statistical library

        if series.len() < 10 {
            return Ok(1.0);  // Not enough data
        }

        // Calculate first differences
        let mut differences = Vec::new();
        for i in 1..series.len() {
            differences.push(series[i] - series[i - 1]);
        }

        // Simple test statistic (would be more sophisticated in real implementation)
        let mean_diff = self.calculate_mean(&differences);
        let std_diff = self.calculate_std(&differences, mean_diff);

        // Approximate p-value based on test statistic
        let test_statistic = if std_diff > 0.0 { mean_diff / std_diff } else { 0.0 };

        // Simplified p-value calculation
        let p_value = if test_statistic < -3.0 {
            0.01
        } else if test_statistic < -2.5 {
            0.05
        } else if test_statistic < -2.0 {
            0.10
        } else {
            0.50
        };

        Ok(p_value)
    }

    /// Calculate mean of a series
    fn calculate_mean(&self, series: &[f64]) -> f64 {
        if series.is_empty() {
            return 0.0;
        }
        series.iter().sum::<f64>() / series.len() as f64
    }

    /// Calculate standard deviation
    fn calculate_std(&self, series: &[f64], mean: f64) -> f64 {
        if series.len() < 2 {
            return 0.0;
        }

        let variance = series.iter()
            .map(|x| (x - mean).powi(2))
            .sum::<f64>() / (series.len() - 1) as f64;

        variance.sqrt()
    }

    /// Calculate Hurst exponent (0-0.5: mean reversion, 0.5-1: trending)
    pub fn calculate_hurst_exponent(&self, series: &[f64]) -> Result<f64> {
        // Simplified Hurst exponent calculation
        if series.len() < 20 {
            return Ok(0.5);  // Random walk
        }

        let mean = self.calculate_mean(series);
        let std = self.calculate_std(series, mean);

        if std == 0.0 {
            return Ok(0.5);
        }

        // Calculate rescaled range for different window sizes
        let window_sizes = vec![10, 20, series.len() / 4];
        let mut log_rs = Vec::new();
        let mut log_n = Vec::new();

        for &window_size in &window_sizes {
            if window_size >= series.len() {
                continue;
            }

            let mut rs_values = Vec::new();

            for i in 0..=(series.len() - window_size) {
                let window: Vec<f64> = series[i..i + window_size].to_vec();
                let window_mean = self.calculate_mean(&window);
                let window_std = self.calculate_std(&window, window_mean);

                if window_std > 0.0 {
                    // Calculate cumulative deviation
                    let mut cumulative_dev = 0.0;
                    let mut max_dev = 0.0;
                    let mut min_dev = 0.0;

                    for value in &window {
                        cumulative_dev += value - window_mean;
                        max_dev = max_dev.max(cumulative_dev);
                        min_dev = min_dev.min(cumulative_dev);
                    }

                    let range = max_dev - min_dev;
                    let rs = range / window_std;
                    rs_values.push(rs);
                }
            }

            if !rs_values.is_empty() {
                let avg_rs = self.calculate_mean(&rs_values);
                log_rs.push(avg_rs.ln());
                log_n.push((window_size as f64).ln());
            }
        }

        // Calculate Hurst exponent as slope of log(R/S) vs log(n)
        if log_rs.len() >= 2 {
            let n = log_rs.len() as f64;
            let sum_log_n = log_n.iter().sum::<f64>();
            let sum_log_rs = log_rs.iter().sum::<f64>();
            let sum_log_n_log_rs = log_n.iter().zip(log_rs.iter())
                .map(|(ln, lrs)| ln * lrs)
                .sum::<f64>();
            let sum_log_n2 = log_n.iter().map(|ln| ln * ln).sum::<f64>();

            let slope = (n * sum_log_n_log_rs - sum_log_n * sum_log_rs) /
                       (n * sum_log_n2 - sum_log_n * sum_log_n);

            Ok(slope.clamp(0.0, 1.0))
        } else {
            Ok(0.5)  // Default to random walk
        }
    }

    /// Calculate half-life of mean reversion
    pub fn calculate_half_life(&self, spread: &[f64]) -> Result<f64> {
        if spread.len() < 10 {
            return Ok(24.0);  // Default 24 hours
        }

        // Calculate changes in spread
        let mut delta_spread = Vec::new();
        let mut lagged_spread = Vec::new();

        for i in 1..spread.len() {
            delta_spread.push(spread[i] - spread[i - 1]);
            lagged_spread.push(spread[i - 1]);
        }

        // Run regression: delta_spread = alpha + beta * lagged_spread
        let (beta, _) = self.linear_regression(&lagged_spread, &delta_spread)?;

        // Half-life = -ln(2) / beta
        if beta <= 0.0 {
            return Ok(24.0);  // Default if not mean reverting
        }

        let half_life = -0.693147 / beta;  // -ln(2) / beta
        Ok(half_life.clamp(1.0, 168.0))  # Clamp between 1 hour and 1 week
    }

    /// Calculate expected return based on z-score and signal
    fn calculate_expected_return(&self, z_score: f64, spread_std: f64, signal: &ArbitrageSignal) -> Result<f64> {
        let expected_z_reversion = match signal {
            ArbitrageSignal::LongAShortB => -z_score.abs(),  # Expect negative z-score to revert to 0
            ArbitrageSignal::ShortALongB => z_score.abs(),   # Expect positive z-score to revert to 0
            ArbitrageSignal::ClosePosition => 0.0,
            ArbitrageSignal::NoSignal => 0.0,
        };

        // Expected return = expected z-reversion * spread standard deviation
        let expected_return = expected_z_reversion * spread_std;

        Ok(expected_return)
    }

    /// Calculate confidence score for the opportunity
    fn calculate_confidence_score(&self, z_score: f64, correlation: f64, cointegration_p: f64, hurst: f64) -> f64 {
        let z_confidence = (z_score.abs() / 3.0).min(1.0);  # Higher z-score = higher confidence
        let correlation_confidence = if correlation > 0.5 && correlation < 0.9 {
            1.0 - (correlation - 0.7).abs() / 0.2  # Optimal correlation around 0.7
        } else {
            0.3
        };
        let cointegration_confidence = 1.0 - cointegration_p;  # Lower p-value = higher confidence
        let mean_reversion_confidence = if hurst < 0.5 { 1.0 - (hurst * 2.0) } else { 0.1 };

        // Weighted average of confidence factors
        (z_confidence * 0.3 +
         correlation_confidence * 0.2 +
         cointegration_confidence * 0.3 +
         mean_reversion_confidence * 0.2).clamp(0.0, 1.0)
    }

    /// Calculate risk score for the opportunity
    fn calculate_risk_score(&self, z_score: f64, spread_std: f64, hurst: f64, correlation: f64) -> f64 {
        let volatility_risk = (spread_std / 100.0).min(1.0);  # Higher spread std = higher risk
        let momentum_risk = if hurst > 0.5 { hurst - 0.5 } else { 0.0 };  # Trending = higher risk
        let correlation_risk = if correlation > 0.9 { correlation - 0.9 } else { 0.0 };  # Very high correlation = risk
        let extreme_z_risk = if z_score.abs() > 3.0 { (z_score.abs() - 3.0) / 2.0 } else { 0.0 };

        // Combined risk score (0 = low risk, 1 = high risk)
        (volatility_risk * 0.3 +
         momentum_risk * 0.3 +
         correlation_risk * 0.2 +
         extreme_z_risk * 0.2).clamp(0.0, 1.0)
    }

    /// Fetch current token price (placeholder - would integrate with Jupiter API)
    async fn fetch_token_price(&self, token: &str) -> Result<f64> {
        // In production, this would call Jupiter Price API V3
        // For now, return mock prices

        let base_prices = HashMap::from([
            ("So11111111111111111111111111111111111111112", 100.0),  // SOL
            ("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", 1.0),    // USDC
            ("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNY", 1.0),     // USDT
            ("9n4nbM75f5Ui33ZbPYXn59JwjuGzs3gT9p5dYjFrUsU4", 50000.0), // WBTC
        ]);

        let base_price = base_prices.get(token).unwrap_or(&1.0);

        // Add some random variation
        let variation = (rand::random::<f64>() - 0.5) * 0.02;  // ±1% variation
        Ok(base_price * (1.0 + variation))
    }

    /// Get token symbol from mint address
    fn get_token_symbol(&self, token: &str) -> String {
        let symbols = HashMap::from([
            ("So11111111111111111111111111111111111111112", "SOL"),
            ("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", "USDC"),
            ("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNY", "USDT"),
            ("9n4nbM75f5Ui33ZbPYXn59JwjuGzs3gT9p5dYjFrUsU4", "WBTC"),
        ]);

        symbols.get(token).unwrap_or(token).to_string()
    }

    /// Get current opportunities
    pub fn get_opportunities(&self) -> &[StatisticalOpportunity] {
        &self.opportunities
    }

    /// Get trading pairs
    pub fn get_trading_pairs(&self) -> &HashMap<String, TradingPair> {
        &self.trading_pairs
    }

    /// Get detector statistics
    pub fn get_statistics(&self) -> HashMap<String, serde_json::Value> {
        let mut stats = HashMap::new();

        stats.insert("monitored_tokens".to_string(),
                    serde_json::Value::Number(self.config.monitored_tokens.len().into()));
        stats.insert("active_pairs".to_string(),
                    serde_json::Value::Number(self.trading_pairs.len().into()));
        stats.insert("cointegrated_pairs".to_string(),
                    serde_json::Value::Number(
                        self.trading_pairs.values()
                            .filter(|p| p.is_cointegrated)
                            .count()
                            .into()
                    ));
        stats.insert("current_opportunities".to_string(),
                    serde_json::Value::Number(self.opportunities.len().into()));
        stats.insert("last_update_seconds_ago".to_string(),
                    serde_json::Value::Number(self.last_update.elapsed().as_secs().into()));

        // Calculate average statistics
        if !self.trading_pairs.is_empty() {
            let avg_correlation: f64 = self.trading_pairs.values()
                .map(|p| p.correlation)
                .sum::<f64>() / self.trading_pairs.len() as f64;

            let avg_cointegration_p: f64 = self.trading_pairs.values()
                .map(|p| p.cointegration_p_value)
                .sum::<f64>() / self.trading_pairs.len() as f64;

            stats.insert("average_correlation".to_string(),
                        serde_json::Value::Number(avg_correlation.into()));
            stats.insert("average_cointegration_p_value".to_string(),
                        serde_json::Value::Number(avg_cointegration_p.into()));
        }

        stats
    }
}

// =============================================================================
// Standalone Statistical Functions for FFI Integration
// =============================================================================

/// Standalone cointegration testing using Engle-Granger method
pub fn test_cointegration(x: &[f64], y: &[f64]) -> Result<(f64, f64)> {
    // Create a temporary detector instance to use its methods
    let temp_detector = StatisticalDetector::new(
        crate::arbitrage::ArbitrageConfig::default()
    );
    temp_detector.test_cointegration(x, y)
}

/// Standalone linear regression
pub fn linear_regression(x: &[f64], y: &[f64]) -> Result<(f64, Vec<f64>)> {
    if x.len() != y.len() || x.len() < 2 {
        return Ok((1.0, Vec::new()));
    }

    let n = x.len() as f64;
    let sum_x = x.iter().sum::<f64>();
    let sum_y = y.iter().sum::<f64>();
    let sum_xy = x.iter().zip(y.iter()).map(|(xi, yi)| xi * yi).sum::<f64>();
    let sum_x2 = x.iter().map(|xi| xi * xi).sum::<f64>();

    let beta = (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x);
    let alpha = (sum_y - beta * sum_x) / n;

    // Calculate residuals
    let residuals: Vec<f64> = y.iter().zip(x.iter())
        .map(|(yi, xi)| yi - (alpha + beta * xi))
        .collect();

    Ok((beta, residuals))
}

/// Standalone Augmented Dickey-Fuller test (simplified implementation)
pub fn adf_test(series: &[f64]) -> Result<f64> {
    // This is a simplified ADF test implementation
    // In production, use a proper statistical library

    if series.len() < 10 {
        return Ok(1.0);  // Not enough data
    }

    // Calculate first differences
    let mut differences = Vec::new();
    for i in 1..series.len() {
        differences.push(series[i] - series[i - 1]);
    }

    // Simple ADF test - check if series is more stationary than its differences
    let series_var = calculate_variance(series);
    let diff_var = calculate_variance(&differences);

    // If differences have much lower variance, series is likely non-stationary
    let stationarity_score = if series_var > 0.0 {
        1.0 - (diff_var / series_var).min(1.0)
    } else {
        0.5  // Degenerate case
    };

    // Convert to pseudo p-value (lower = more likely stationary)
    let p_value = 1.0 - stationarity_score;
    Ok(p_value)
}

/// Calculate variance of a series
fn calculate_variance(series: &[f64]) -> f64 {
    if series.is_empty() {
        return 0.0;
    }

    let mean = series.iter().sum::<f64>() / series.len() as f64;
    let variance = series.iter()
        .map(|x| (x - mean).powi(2))
        .sum::<f64>() / series.len() as f64;

    variance
}

/// Standalone Hurst exponent calculation
pub fn calculate_hurst_exponent(series: &[f64]) -> Result<f64> {
    if series.len() < 20 {
        return Ok(0.5);  // Default to random walk for short series
    }

    // Create a temporary detector instance
    let temp_detector = StatisticalDetector::new(
        crate::arbitrage::ArbitrageConfig::default()
    );
    temp_detector.calculate_hurst_exponent(series)
}

/// Standalone half-life calculation
pub fn calculate_half_life(spread: &[f64]) -> Result<f64> {
    if spread.len() < 10 {
        return Ok(10.0);  // Default value for short series
    }

    // Create a temporary detector instance
    let temp_detector = StatisticalDetector::new(
        crate::arbitrage::ArbitrageConfig::default()
    );
    temp_detector.calculate_half_life(spread)
}

// Add random number generator for mock prices
mod rand {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    use std::time::{SystemTime, UNIX_EPOCH};

    pub fn random<T>() -> T
    where
        T: From<f64>,
    {
        let mut hasher = DefaultHasher::new();
        SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos().hash(&mut hasher);
        let hash = hasher.finish();

        // Simple hash to float conversion
        let float = (hash as f64) / (u64::MAX as f64);
        T::from(float)
    }
}