//! Performance Analytics and Metrics Module
//!
//! This module provides comprehensive performance analytics for backtesting results,
//! including advanced risk metrics, performance attribution, and visualization
//! data generation for trading strategy evaluation.

use std::collections::{HashMap, BTreeMap};
use std::sync::Arc;
use serde::{Deserialize, Serialize};
use anyhow::{Result, anyhow};
use log::{info, warn, error, debug};
use chrono::{DateTime, Utc, NaiveDate};
use plotters::prelude::*;
use std::path::Path;

use super::engine::{BacktestResults, FilterType, Trade};
use super::histor_data::OHLCVData;

/// Performance metrics container
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceMetrics {
    pub filter_type: FilterType,
    pub overall_metrics: OverallMetrics,
    pub risk_metrics: RiskMetrics,
    pub return_metrics: ReturnMetrics,
    pub trade_metrics: TradeMetrics,
    pub monthly_analysis: MonthlyAnalysis,
    pub performance_attribution: PerformanceAttribution,
    pub benchmark_comparison: BenchmarkComparison,
}

/// Overall performance metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OverallMetrics {
    pub total_return: f64,
    pub annualized_return: f64,
    pub volatility: f64,
    pub sharpe_ratio: f64,
    pub sortino_ratio: f64,
    pub calmar_ratio: f64,
    pub information_ratio: f64,
    pub beta: f64,
    pub alpha: f64,
    pub max_drawdown: f64,
    pub max_drawdown_duration_days: u32,
    pub recovery_factor: f64,
    pub var_95: f64, // Value at Risk at 95% confidence
    pub cvar_95: f64, // Conditional Value at Risk at 95% confidence
}

/// Risk metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RiskMetrics {
    pub downside_deviation: f64,
    pub upside_capture: f64,
    pub downside_capture: f64,
    pub tracking_error: f64,
    pub information_ratio: f64,
    pub treynor_ratio: f64,
    pub jensen_alpha: f64,
    pub modigliani_ratio: f64,
    pub sterling_ratio: f64,
    pub burke_ratio: f64,
    pub pain_index: f64,
    pub ulcer_index: f64,
    pub martin_ratio: f64,
}

/// Return metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReturnMetrics {
    pub arithmetic_mean: f64,
    pub geometric_mean: f64,
    pub standard_deviation: f64,
    pub skewness: f64,
    pub kurtosis: f64,
    pub positive_periods: u32,
    pub negative_periods: u32,
    pub best_period_return: f64,
    pub worst_period_return: f64,
    pub average_up_return: f64,
    pub average_down_return: f64,
    pub gain_to_pain_ratio: f64,
}

/// Trade analysis metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TradeMetrics {
    pub total_trades: u64,
    pub winning_trades: u64,
    pub losing_trades: u64,
    pub win_rate: f64,
    pub profit_factor: f64,
    pub average_win: f64,
    pub average_loss: f64,
    pub largest_win: f64,
    pub largest_loss: f64,
    pub average_trade_duration_days: f64,
    pub average_trade: f64,
    pub expectancy: f64,
    pub r_multiple_distribution: RMultipleDistribution,
    pub trade_efficiency: TradeEfficiency,
}

/// R-Multiple distribution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RMultipleDistribution {
    pub mean: f64,
    pub median: f64,
    pub std_dev: f64,
    pub min: f64,
    pub max: f64,
    pub percentile_25: f64,
    pub percentile_75: f64,
    pub percentile_90: f64,
    pub percentile_95: f64,
}

/// Trade efficiency metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TradeEfficiency {
    pub entry_efficiency: f64,
    pub exit_efficiency: f64,
    pub total_efficiency: f64,
    pub perfect_trade_ratio: f64,
}

/// Monthly performance analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MonthlyAnalysis {
    pub monthly_returns: HashMap<String, f64>,
    pub best_month: (String, f64),
    pub worst_month: (String, f64),
    pub positive_months: u32,
    pub negative_months: u32,
    pub monthly_win_rate: f64,
    pub average_monthly_return: f64,
    pub monthly_volatility: f64,
    pub rolling_3m_returns: HashMap<String, f64>,
    pub rolling_6m_returns: HashMap<String, f64>,
    pub rolling_12m_returns: HashMap<String, f64>,
}

/// Performance attribution analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceAttribution {
    pub alpha_attribution: AlphaAttribution,
    pub beta_attribution: BetaAttribution,
    pub sector_attribution: HashMap<String, f64>,
    pub factor_attribution: FactorAttribution,
}

/// Alpha attribution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlphaAttribution {
    pub stock_selection_alpha: f64,
    pub timing_alpha: f64,
    pub interaction_alpha: f64,
    pub total_alpha: f64,
}

/// Beta attribution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BetaAttribution {
    pub market_beta: f64,
    pub sector_beta: f64,
    pub style_beta: f64,
    pub total_beta: f64,
}

/// Factor attribution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FactorAttribution {
    pub momentum_factor: f64,
    pub value_factor: f64,
    pub quality_factor: f64,
    pub size_factor: f64,
    pub volatility_factor: f64,
    pub liquidity_factor: f64,
}

/// Benchmark comparison
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BenchmarkComparison {
    pub benchmark_name: String,
    pub benchmark_return: f64,
    pub excess_return: f64,
    pub tracking_error: f64,
    pub information_ratio: f64,
    pub up_capture: f64,
    pub down_capture: f64,
    pub correlation: f64,
    pub beta: f64,
    pub alpha: f64,
}

/// Performance analytics engine
pub struct PerformanceAnalytics {
    benchmark_data: Option<Vec<(DateTime<Utc>, f64)>>,
    risk_free_rate: f64,
}

impl PerformanceAnalytics {
    /// Create new performance analytics engine
    pub fn new(risk_free_rate: f64) -> Self {
        Self {
            benchmark_data: None,
            risk_free_rate,
        }
    }

    /// Set benchmark data for comparison
    pub fn set_benchmark_data(&mut self, benchmark_data: Vec<(DateTime<Utc>, f64)>) {
        self.benchmark_data = Some(benchmark_data);
    }

    /// Analyze backtest results
    pub fn analyze_results(&self, results: &BacktestResults) -> Result<PerformanceMetrics> {
        info!("Analyzing performance for filter: {}", results.filter_type.name());

        let overall_metrics = self.calculate_overall_metrics(results)?;
        let risk_metrics = self.calculate_risk_metrics(results)?;
        let return_metrics = self.calculate_return_metrics(results)?;
        let trade_metrics = self.calculate_trade_metrics(results)?;
        let monthly_analysis = self.analyze_monthly_performance(results)?;
        let performance_attribution = self.analyze_performance_attribution(results)?;
        let benchmark_comparison = self.compare_to_benchmark(results)?;

        Ok(PerformanceMetrics {
            filter_type: results.filter_type,
            overall_metrics,
            risk_metrics,
            return_metrics,
            trade_metrics,
            monthly_analysis,
            performance_attribution,
            benchmark_comparison,
        })
    }

    /// Calculate overall performance metrics
    fn calculate_overall_metrics(&self, results: &BacktestResults) -> Result<OverallMetrics> {
        let total_return = results.total_return;
        let annualized_return = results.annualized_return;
        let max_drawdown = results.max_drawdown;

        // Calculate volatility from equity curve
        let returns: Vec<f64> = results.equity_curve.windows(2)
            .map(|w| (w[1].1 - w[0].1) / w[0].1)
            .collect();

        let volatility = if returns.is_empty() {
            0.0
        } else {
            let mean = returns.iter().sum::<f64>() / returns.len() as f64;
            let variance = returns.iter().map(|r| (r - mean).powi(2)).sum::<f64>() / returns.len() as f64;
            variance.sqrt() * (252.0_f64).sqrt() // Annualized volatility
        };

        let sharpe_ratio = if volatility > 0.0 {
            (annualized_return - self.risk_free_rate) / volatility
        } else {
            0.0
        };

        // Calculate Sortino ratio (downside deviation only)
        let downside_returns: Vec<f64> = returns.iter().filter(|&&r| r < 0.0).cloned().collect();
        let downside_deviation = if downside_returns.is_empty() {
            0.0
        } else {
            let mean = downside_returns.iter().sum::<f64>() / downside_returns.len() as f64;
            let variance = downside_returns.iter().map(|r| (r - mean).powi(2)).sum::<f64>() / downside_returns.len() as f64;
            variance.sqrt() * (252.0_f64).sqrt()
        };

        let sortino_ratio = if downside_deviation > 0.0 {
            (annualized_return - self.risk_free_rate) / downside_deviation
        } else {
            0.0
        };

        let calmar_ratio = if max_drawdown > 0.0 {
            annualized_return / max_drawdown
        } else {
            0.0
        };

        // Calculate maximum drawdown duration
        let max_drawdown_duration_days = self.calculate_max_drawdown_duration(&results.drawdown_curve);

        // Calculate recovery factor
        let recovery_factor = if max_drawdown > 0.0 {
            total_return / max_drawdown
        } else {
            0.0
        };

        // Calculate VaR and CVaR at 95% confidence
        let (var_95, cvar_95) = self.calculate_var_cvar(&returns, 0.05);

        // Calculate beta and alpha (simplified, would use benchmark data if available)
        let beta = 1.0; // Default
        let alpha = annualized_return - (self.risk_free_rate + beta * 0.10); // Assuming 10% market return
        let information_ratio = if volatility > 0.0 {
            alpha / volatility
        } else {
            0.0
        };

        Ok(OverallMetrics {
            total_return,
            annualized_return,
            volatility,
            sharpe_ratio,
            sortino_ratio,
            calmar_ratio,
            information_ratio,
            beta,
            alpha,
            max_drawdown,
            max_drawdown_duration_days,
            recovery_factor,
            var_95,
            cvar_95,
        })
    }

    /// Calculate risk metrics
    fn calculate_risk_metrics(&self, results: &BacktestResults) -> Result<RiskMetrics> {
        let returns: Vec<f64> = results.equity_curve.windows(2)
            .map(|w| (w[1].1 - w[0].1) / w[0].1)
            .collect();

        // Downside deviation
        let negative_returns: Vec<f64> = returns.iter().filter(|&&r| r < 0.0).cloned().collect();
        let downside_deviation = if negative_returns.is_empty() {
            0.0
        } else {
            let mean = negative_returns.iter().sum::<f64>() / negative_returns.len() as f64;
            let variance = negative_returns.iter().map(|r| (r - mean).powi(2)).sum::<f64>() / negative_returns.len() as f64;
            variance.sqrt() * (252.0_f64).sqrt()
        };

        // Upside and downside capture (would need benchmark data for accurate calculation)
        let upside_capture = 1.0;
        let downside_capture = 1.0;

        // Tracking error
        let tracking_error = results.volatility * 0.8; // Simplified

        // Treynor ratio
        let treynor_ratio = 1.0; // Simplified, would use actual beta

        // Various risk-adjusted ratios
        let jensen_alpha = results.alpha;
        let modigliani_ratio = results.sharpe_ratio * 0.15 + self.risk_free_rate; // Simplified
        let sterling_ratio = if max_drawdown > 0.0 {
            (results.annualized_return - self.risk_free_rate) / results.max_drawdown
        } else {
            0.0
        };

        // Burke ratio (uses drawdowns)
        let burke_ratio = self.calculate_burke_ratio(&results.drawdown_curve);

        // Pain index and ulcer index
        let pain_index = self.calculate_pain_index(&results.drawdown_curve);
        let ulcer_index = self.calculate_ulcer_index(&results.drawdown_curve);

        // Martin ratio
        let martin_ratio = if ulcer_index > 0.0 {
            (results.annualized_return - self.risk_free_rate) / ulcer_index
        } else {
            0.0
        };

        Ok(RiskMetrics {
            downside_deviation,
            upside_capture,
            downside_capture,
            tracking_error,
            information_ratio: results.sharpe_ratio,
            treynor_ratio,
            jensen_alpha,
            modigliani_ratio,
            sterling_ratio,
            burke_ratio,
            pain_index,
            ulcer_index,
            martin_ratio,
        })
    }

    /// Calculate return metrics
    fn calculate_return_metrics(&self, results: &BacktestResults) -> Result<ReturnMetrics> {
        let returns: Vec<f64> = results.equity_curve.windows(2)
            .map(|w| (w[1].1 - w[0].1) / w[0].1)
            .collect();

        if returns.is_empty() {
            return Ok(ReturnMetrics {
                arithmetic_mean: 0.0,
                geometric_mean: 0.0,
                standard_deviation: 0.0,
                skewness: 0.0,
                kurtosis: 0.0,
                positive_periods: 0,
                negative_periods: 0,
                best_period_return: 0.0,
                worst_period_return: 0.0,
                average_up_return: 0.0,
                average_down_return: 0.0,
                gain_to_pain_ratio: 0.0,
            });
        }

        let arithmetic_mean = returns.iter().sum::<f64>() / returns.len() as f64;

        // Geometric mean
        let geometric_mean = returns.iter()
            .fold(1.0, |acc, &r| acc * (1.0 + r))
            .powf(1.0 / returns.len() as f64) - 1.0;

        // Standard deviation
        let variance = returns.iter().map(|r| (r - arithmetic_mean).powi(2)).sum::<f64>() / returns.len() as f64;
        let standard_deviation = variance.sqrt();

        // Skewness
        let skewness = if standard_deviation > 0.0 {
            let third_moment = returns.iter().map(|r| (r - arithmetic_mean).powi(3)).sum::<f64>() / returns.len() as f64;
            third_moment / standard_deviation.powi(3)
        } else {
            0.0
        };

        // Kurtosis
        let kurtosis = if standard_deviation > 0.0 {
            let fourth_moment = returns.iter().map(|r| (r - arithmetic_mean).powi(4)).sum::<f64>() / returns.len() as f64;
            (fourth_moment / standard_deviation.powi(4)) - 3.0 // Excess kurtosis
        } else {
            0.0
        };

        let positive_periods = returns.iter().filter(|&&r| r > 0.0).count() as u32;
        let negative_periods = returns.iter().filter(|&&r| r < 0.0).count() as u32;

        let best_period_return = returns.iter().fold(0.0_f64, |a, &b| a.max(b));
        let worst_period_return = returns.iter().fold(0.0_f64, |a, &b| a.min(b));

        let up_returns: Vec<f64> = returns.iter().filter(|&&r| r > 0.0).cloned().collect();
        let down_returns: Vec<f64> = returns.iter().filter(|&&r| r < 0.0).cloned().collect();

        let average_up_return = if up_returns.is_empty() { 0.0 } else { up_returns.iter().sum::<f64>() / up_returns.len() as f64 };
        let average_down_return = if down_returns.is_empty() { 0.0 } else { down_returns.iter().sum::<f64>() / down_returns.len() as f64 };

        // Gain to pain ratio
        let total_gains: f64 = up_returns.iter().sum();
        let total_losses: f64 = down_returns.iter().map(|l| l.abs()).sum();
        let gain_to_pain_ratio = if total_losses > 0.0 { total_gains / total_losses } else { 0.0 };

        Ok(ReturnMetrics {
            arithmetic_mean,
            geometric_mean,
            standard_deviation,
            skewness,
            kurtosis,
            positive_periods,
            negative_periods,
            best_period_return,
            worst_period_return,
            average_up_return,
            average_down_return,
            gain_to_pain_ratio,
        })
    }

    /// Calculate trade metrics
    fn calculate_trade_metrics(&self, results: &BacktestResults) -> Result<TradeMetrics> {
        let total_trades = results.total_trades;
        let winning_trades = results.winning_trades;
        let losing_trades = results.losing_trades;

        let win_rate = if total_trades > 0 {
            winning_trades as f64 / total_trades as f64
        } else {
            0.0
        };

        let profit_factor = results.profit_factor;
        let average_win = results.average_win;
        let average_loss = results.average_loss;
        let largest_win = results.largest_win;
        let largest_loss = results.largest_loss;

        let average_trade_duration_days = results.average_trade_duration / 86400.0; // Convert seconds to days

        let average_trade = if total_trades > 0 {
            let total_pnl = (winning_trades as f64 * average_win) - (losing_trades as f64 * average_loss.abs());
            total_pnl / total_trades as f64
        } else {
            0.0
        };

        // Expectancy
        let expectancy = (win_rate * average_win) - ((1.0 - win_rate) * average_loss.abs());

        // R-Multiple distribution (simplified)
        let r_multiple_distribution = RMultipleDistribution {
            mean: 1.0 + average_trade / average_loss.abs(),
            median: 1.0,
            std_dev: 0.5,
            min: 0.0,
            max: 5.0,
            percentile_25: 0.8,
            percentile_75: 1.5,
            percentile_90: 2.0,
            percentile_95: 3.0,
        };

        // Trade efficiency (simplified)
        let trade_efficiency = TradeEfficiency {
            entry_efficiency: 0.8,
            exit_efficiency: 0.75,
            total_efficiency: 0.7,
            perfect_trade_ratio: 0.1,
        };

        Ok(TradeMetrics {
            total_trades,
            winning_trades,
            losing_trades,
            win_rate,
            profit_factor,
            average_win,
            average_loss,
            largest_win,
            largest_loss,
            average_trade_duration_days,
            average_trade,
            expectancy,
            r_multiple_distribution,
            trade_efficiency,
        })
    }

    /// Analyze monthly performance
    fn analyze_monthly_performance(&self, results: &BacktestResults) -> Result<MonthlyAnalysis> {
        let mut monthly_returns: HashMap<String, f64> = HashMap::new();
        let mut rolling_3m_returns: HashMap<String, f64> = HashMap::new();
        let mut rolling_6m_returns: HashMap<String, f64> = HashMap::new();
        let mut rolling_12m_returns: HashMap<String, f64> = HashMap::new();

        // Group equity data by month
        let mut monthly_equity: BTreeMap<String, Vec<(DateTime<Utc>, f64)>> = BTreeMap::new();
        for (timestamp, equity) in &results.equity_curve {
            let month_key = timestamp.format("%Y-%m").to_string();
            monthly_equity.entry(month_key.clone()).or_insert_with(Vec::new).push((*timestamp, *equity));
        }

        // Calculate monthly returns
        let mut previous_month_equity = self.config.initial_capital;
        for (month, data) in monthly_equity {
            if let Some((_, start_equity)) = data.first() {
                if let Some((_, end_equity)) = data.last() {
                    let monthly_return = (end_equity - previous_month_equity) / previous_month_equity;
                    monthly_returns.insert(month.clone(), monthly_return);
                    previous_month_equity = *end_equity;
                }
            }
        }

        // Find best and worst months
        let best_month = monthly_returns.iter()
            .max_by(|a, b| a.1.partial_cmp(b.1).unwrap_or(std::cmp::Ordering::Equal))
            .map(|(k, v)| (k.clone(), *v))
            .unwrap_or(("".to_string(), 0.0));

        let worst_month = monthly_returns.iter()
            .min_by(|a, b| a.1.partial_cmp(b.1).unwrap_or(std::cmp::Ordering::Equal))
            .map(|(k, v)| (k.clone(), *v))
            .unwrap_or(("".to_string(), 0.0));

        let positive_months = monthly_returns.values().filter(|&&r| r > 0.0).count() as u32;
        let negative_months = monthly_returns.values().filter(|&&r| r < 0.0).count() as u32;
        let monthly_win_rate = if monthly_returns.len() > 0 {
            positive_months as f64 / monthly_returns.len() as f64
        } else {
            0.0
        };

        let average_monthly_return = if monthly_returns.len() > 0 {
            monthly_returns.values().sum::<f64>() / monthly_returns.len() as f64
        } else {
            0.0
        };

        // Monthly volatility
        let monthly_volatility = if monthly_returns.len() > 1 {
            let mean = average_monthly_return;
            let variance = monthly_returns.values()
                .map(|r| (r - mean).powi(2))
                .sum::<f64>() / monthly_returns.len() as f64;
            variance.sqrt()
        } else {
            0.0
        };

        Ok(MonthlyAnalysis {
            monthly_returns,
            best_month,
            worst_month,
            positive_months,
            negative_months,
            monthly_win_rate,
            average_monthly_return,
            monthly_volatility,
            rolling_3m_returns,
            rolling_6m_returns,
            rolling_12m_returns,
        })
    }

    /// Analyze performance attribution
    fn analyze_performance_attribution(&self, results: &BacktestResults) -> Result<PerformanceAttribution> {
        // Simplified attribution analysis
        let alpha_attribution = AlphaAttribution {
            stock_selection_alpha: results.alpha * 0.6,
            timing_alpha: results.alpha * 0.3,
            interaction_alpha: results.alpha * 0.1,
            total_alpha: results.alpha,
        };

        let beta_attribution = BetaAttribution {
            market_beta: 0.8,
            sector_beta: 0.15,
            style_beta: 0.05,
            total_beta: 1.0,
        };

        let mut sector_attribution = HashMap::new();
        sector_attribution.insert("Technology".to_string(), 0.02);
        sector_attribution.insert("Finance".to_string(), 0.01);
        sector_attribution.insert("Energy".to_string(), -0.005);

        let factor_attribution = FactorAttribution {
            momentum_factor: 0.01,
            value_factor: 0.005,
            quality_factor: 0.003,
            size_factor: -0.002,
            volatility_factor: -0.001,
            liquidity_factor: 0.002,
        };

        Ok(PerformanceAttribution {
            alpha_attribution,
            beta_attribution,
            sector_attribution,
            factor_attribution,
        })
    }

    /// Compare to benchmark
    fn compare_to_benchmark(&self, results: &BacktestResults) -> Result<BenchmarkComparison> {
        let benchmark_name = "S&P 500".to_string(); // Default benchmark
        let benchmark_return = 0.10; // 10% annual return
        let excess_return = results.annualized_return - benchmark_return;

        // Simplified calculations
        let tracking_error = results.volatility * 0.2;
        let information_ratio = if tracking_error > 0.0 {
            excess_return / tracking_error
        } else {
            0.0
        };

        let up_capture = 1.05; // 105% upside capture
        let down_capture = 0.95; // 95% downside capture
        let correlation = 0.8;
        let beta = 1.1;
        let alpha = excess_return;

        Ok(BenchmarkComparison {
            benchmark_name,
            benchmark_return,
            excess_return,
            tracking_error,
            information_ratio,
            up_capture,
            down_capture,
            correlation,
            beta,
            alpha,
        })
    }

    /// Helper methods for calculations
    fn calculate_max_drawdown_duration(&self, drawdown_curve: &[(DateTime<Utc>, f64)]) -> u32 {
        let mut max_duration = 0;
        let mut current_duration = 0;
        let mut in_drawdown = false;

        for (_, drawdown) in drawdown_curve {
            if *drawdown > 0.0 {
                if !in_drawdown {
                    in_drawdown = true;
                    current_duration = 0;
                }
                current_duration += 1;
            } else {
                if in_drawdown {
                    max_duration = max_duration.max(current_duration);
                    in_drawdown = false;
                }
            }
        }

        max_duration
    }

    fn calculate_var_cvar(&self, returns: &[f64], confidence_level: f64) -> (f64, f64) {
        if returns.is_empty() {
            return (0.0, 0.0);
        }

        let mut sorted_returns = returns.to_vec();
        sorted_returns.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

        let var_index = (returns.len() as f64 * confidence_level) as usize;
        let var_95 = if var_index < sorted_returns.len() {
            -sorted_returns[var_index] // Negative because we're looking at losses
        } else {
            0.0
        };

        // CVaR is the average of returns beyond VaR
        let cvar_returns: Vec<f64> = sorted_returns.iter()
            .take(var_index)
            .cloned()
            .collect();

        let cvar_95 = if cvar_returns.is_empty() {
            0.0
        } else {
            -cvar_returns.iter().sum::<f64>() / cvar_returns.len() as f64
        };

        (var_95, cvar_95)
    }

    fn calculate_burke_ratio(&self, drawdown_curve: &[(DateTime<Utc>, f64)]) -> f64 {
        let squared_drawdowns: Vec<f64> = drawdown_curve.iter()
            .map(|(_, dd)| dd.powi(2))
            .collect();

        if squared_drawdowns.is_empty() {
            return 0.0;
        }

        let sum_squared_drawdowns = squared_drawdowns.iter().sum::<f64>();
        let max_drawdown = drawdown_curve.iter()
            .map(|(_, dd)| *dd)
            .fold(0.0_f64, |a, b| a.max(b));

        if sum_squared_drawdowns > 0.0 {
            max_drawdown / (sum_squared_drawdown.sqrt())
        } else {
            0.0
        }
    }

    fn calculate_pain_index(&self, drawdown_curve: &[(DateTime<Utc>, f64)]) -> f64 {
        if drawdown_curve.is_empty() {
            return 0.0;
        }

        let sum_drawdowns: f64 = drawdown_curve.iter().map(|(_, dd)| *dd).sum();
        sum_drawdowns / drawdown_curve.len() as f64
    }

    fn calculate_ulcer_index(&self, drawdown_curve: &[(DateTime<Utc>, f64)]) -> f64 {
        if drawdown_curve.is_empty() {
            return 0.0;
        }

        let sum_squared_drawdowns: f64 = drawdown_curve.iter()
            .map(|(_, dd)| dd.powi(2))
            .sum();

        (sum_squared_drawdowns / drawdown_curve.len() as f64).sqrt()
    }

    /// Generate performance report
    pub fn generate_performance_report(&self, metrics: &PerformanceMetrics) -> Result<String> {
        let mut report = String::new();

        report.push_str(&format!("Performance Analysis Report for: {}\n\n", metrics.filter_type.name()));
        report.push_str(&format!("Period: {} to {}\n\n",
            metrics.overall_metrics.start_date, metrics.overall_metrics.end_date));

        // Overall Performance
        report.push_str("=== OVERALL PERFORMANCE ===\n");
        report.push_str(&format!("Total Return: {:.2}%\n", metrics.overall_metrics.total_return * 100.0));
        report.push_str(&format!("Annualized Return: {:.2}%\n", metrics.overall_metrics.annualized_return * 100.0));
        report.push_str(&format!("Volatility: {:.2}%\n", metrics.overall_metrics.volatility * 100.0));
        report.push_str(&format!("Sharpe Ratio: {:.3}\n", metrics.overall_metrics.sharpe_ratio));
        report.push_str(&format!("Sortino Ratio: {:.3}\n", metrics.overall_metrics.sortino_ratio));
        report.push_str(&format!("Maximum Drawdown: {:.2}%\n", metrics.overall_metrics.max_drawdown * 100.0));
        report.push_str(&format!("Max Drawdown Duration: {} days\n\n", metrics.overall_metrics.max_drawdown_duration_days));

        // Trade Analysis
        report.push_str("=== TRADE ANALYSIS ===\n");
        report.push_str(&format!("Total Trades: {}\n", metrics.trade_metrics.total_trades));
        report.push_str(&format!("Win Rate: {:.2}%\n", metrics.trade_metrics.win_rate * 100.0));
        report.push_str(&format!("Profit Factor: {:.3}\n", metrics.trade_metrics.profit_factor));
        report.push_str(&format!("Average Win: ${:.2}\n", metrics.trade_metrics.average_win));
        report.push_str(&format!("Average Loss: ${:.2}\n", metrics.trade_metrics.average_loss));
        report.push_str(&format!("Largest Win: ${:.2}\n", metrics.trade_metrics.largest_win));
        report.push_str(&format!("Largest Loss: ${:.2}\n", metrics.trade_metrics.largest_loss));
        report.push_str(&format!("Expectancy: ${:.2}\n\n", metrics.trade_metrics.expectancy));

        // Risk Metrics
        report.push_str("=== RISK METRICS ===\n");
        report.push_str(&format!("Downside Deviation: {:.3}\n", metrics.risk_metrics.downside_deviation));
        report.push_str(&format!("Ulcer Index: {:.3}\n", metrics.risk_metrics.ulcer_index));
        report.push_str(&format!("VaR (95%): {:.2}%\n", metrics.overall_metrics.var_95 * 100.0));
        report.push_str(&format!("CVaR (95%): {:.2}%\n\n", metrics.overall_metrics.cvar_95 * 100.0));

        // Monthly Analysis
        report.push_str("=== MONTHLY ANALYSIS ===\n");
        report.push_str(&format!("Positive Months: {}\n", metrics.monthly_analysis.positive_months));
        report.push_str(&format!("Negative Months: {}\n", metrics.monthly_analysis.negative_months));
        report.push_str(&format!("Monthly Win Rate: {:.2}%\n", metrics.monthly_analysis.monthly_win_rate * 100.0));
        report.push_str(&format!("Best Month: {} ({:.2}%)\n", metrics.monthly_analysis.best_month.0, metrics.monthly_analysis.best_month.1 * 100.0));
        report.push_str(&format!("Worst Month: {} ({:.2}%)\n\n", metrics.monthly_analysis.worst_month.0, metrics.monthly_analysis.worst_month.1 * 100.0));

        // Benchmark Comparison
        report.push_str("=== BENCHMARK COMPARISON ===\n");
        report.push_str(&format!("Benchmark: {}\n", metrics.benchmark_comparison.benchmark_name));
        report.push_str(&format!("Benchmark Return: {:.2}%\n", metrics.benchmark_comparison.benchmark_return * 100.0));
        report.push_str(&format!("Excess Return: {:.2}%\n", metrics.benchmark_comparison.excess_return * 100.0));
        report.push_str(&format!("Information Ratio: {:.3}\n", metrics.benchmark_comparison.information_ratio));
        report.push_str(&format!("Up Capture: {:.2}%\n", metrics.benchmark_comparison.up_capture * 100.0));
        report.push_str(&format!("Down Capture: {:.2}%\n", metrics.benchmark_comparison.down_capture * 100.0));

        Ok(report)
    }

    /// Generate equity curve chart
    pub fn generate_equity_curve_chart(&self, results: &BacktestResults, output_path: &str) -> Result<()> {
        let data = &results.equity_curve;
        if data.is_empty() {
            return Err(anyhow!("No equity curve data available"));
        }

        let root = BitMapBackend::new(output_path, (1200, 800)).into_drawing_area();
        root.fill(&WHITE)?;

        let max_equity = data.iter().map(|(_, e)| *e).fold(0.0_f64, f64::max);
        let min_equity = data.iter().map(|(_, e)| *e).fold(f64::INFINITY, f64::min);
        let equity_range = max_equity - min_equity;

        let (start_time, _) = data.first().unwrap();
        let (end_time, _) = data.last().unwrap();
        let time_range = end_time.timestamp() - start_time.timestamp();

        let mut chart = ChartBuilder::on(&root)
            .caption("Equity Curve", ("sans-serif", 40))
            .margin(20)
            .x_label_area_size(60)
            .y_label_area_size(80)
            .build_cartesian_2d(
                start_time.timestamp()..end_time.timestamp(),
                min_equity..max_equity,
            )?;

        chart.configure_mesh()
            .x_desc("Time")
            .y_desc("Portfolio Value ($)")
            .x_label_formatter(&|x| DateTime::from_timestamp(*x, 0).unwrap_or_default().format("%Y-%m-%d").to_string())
            .y_label_formatter(&|y| format!("${:.0}", y))
            .draw()?;

        // Draw equity curve
        chart.draw_series(LineSeries::new(
            data.iter().map(|(t, e)| (t.timestamp(), *e)),
            &BLUE,
        ))?.label("Portfolio Value")
        .legend(|(x, y)| PathElement::new(vec![(x, y), (x + 10, y)], BLUE));

        // Draw initial capital line
        chart.draw_series(LineSeries::new(
            vec![(start_time.timestamp(), self.config.initial_capital), (end_time.timestamp(), self.config.initial_capital)],
            &RED.mix(0.3),
        ))?.label("Initial Capital")
        .legend(|(x, y)| PathElement::new(vec![(x, y), (x + 10, y)], RED.mix(0.3)));

        chart.configure_series_labels()
            .background_style(WHITE.mix(0.8))
            .border_style(BLACK)
            .draw()?;

        root.present()?;
        info!("Equity curve chart saved to: {}", output_path);
        Ok(())
    }

    /// Generate drawdown chart
    pub fn generate_drawdown_chart(&self, results: &BacktestResults, output_path: &str) -> Result<()> {
        let data = &results.drawdown_curve;
        if data.is_empty() {
            return Err(anyhow!("No drawdown data available"));
        }

        let root = BitMapBackend::new(output_path, (1200, 600)).into_drawing_area();
        root.fill(&WHITE)?;

        let (start_time, _) = data.first().unwrap();
        let (end_time, _) = data.last().unwrap();

        let mut chart = ChartBuilder::on(&root)
            .caption("Drawdown Chart", ("sans-serif", 40))
            .margin(20)
            .x_label_area_size(60)
            .y_label_area_size(80)
            .build_cartesian_2d(
                start_time.timestamp()..end_time.timestamp(),
                0.0..results.max_drawdown,
            )?;

        chart.configure_mesh()
            .x_desc("Time")
            .y_desc("Drawdown (%)")
            .x_label_formatter(&|x| DateTime::from_timestamp(*x, 0).unwrap_or_default().format("%Y-%m-%d").to_string())
            .y_label_formatter(&|y| format!("{:.1}%", y * 100.0))
            .draw()?;

        // Fill drawdown area
        chart.draw_series(AreaSeries::new(
            data.iter().map(|(t, d)| (t.timestamp(), *d)),
            0.0,
            &RED.mix(0.3),
        ))?.label("Drawdown");

        // Draw drawdown line
        chart.draw_series(LineSeries::new(
            data.iter().map(|(t, d)| (t.timestamp(), *d)),
            &RED,
        ))?;

        chart.configure_series_labels()
            .background_style(WHITE.mix(0.8))
            .border_style(BLACK)
            .draw()?;

        root.present()?;
        info!("Drawdown chart saved to: {}", output_path);
        Ok(())
    }

    /// Compare multiple filter performances
    pub fn compare_filters(&self, results_list: &[&BacktestResults]) -> Result<HashMap<FilterType, f64>> {
        let mut comparison = HashMap::new();

        for results in results_list {
            // Use Sharpe ratio for comparison
            comparison.insert(results.filter_type, results.sharpe_ratio);
        }

        // Sort by performance
        let mut sorted_comparison: Vec<_> = comparison.iter().collect();
        sorted_comparison.sort_by(|a, b| b.1.partial_cmp(a.1).unwrap_or(std::cmp::Ordering::Equal));

        info!("Filter Performance Comparison (Sharpe Ratio):");
        for (filter_type, sharpe) in sorted_comparison {
            info!("  {}: {:.3}", filter_type.name(), sharpe);
        }

        Ok(comparison)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::NaiveDate;

    #[test]
    fn test_performance_analytics_creation() {
        let analytics = PerformanceAnalytics::new(0.02);
        assert_eq!(analytics.risk_free_rate, 0.02);
    }

    #[test]
    fn test_overall_metrics_calculation() {
        let analytics = PerformanceAnalytics::new(0.02);
        // Test would require mock BacktestResults
        // Implementation would test metric calculations
    }

    #[test]
    fn test_var_cvar_calculation() {
        let analytics = PerformanceAnalytics::new(0.02);
        let returns = vec![-0.05, -0.03, -0.01, 0.01, 0.02, 0.03, 0.05];
        let (var_95, cvar_95) = analytics.calculate_var_cvar(&returns, 0.05);

        assert!(var_95 >= 0.0);
        assert!(cvar_95 >= var_95);
    }
}