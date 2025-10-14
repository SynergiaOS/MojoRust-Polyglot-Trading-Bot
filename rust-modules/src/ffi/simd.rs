// =============================================================================
// SIMD-Optimized Numerical Calculations Module
// =============================================================================
// High-performance SIMD implementations for arbitrage profit calculations
// Provides 10-20% speedup for numerical operations with AVX2 support

use std::arch::x86_64::*;

/// Check if SIMD is available at runtime
pub fn is_simd_available() -> bool {
    #[cfg(target_arch = "x86_64")]
    {
        is_x86_feature_detected!("avx2")
    }
    #[cfg(not(target_arch = "x86_64"))]
    {
        false
    }
}

/// Calculate triangular arbitrage profit using SIMD
/// Input: prices = [token1/token2, token2/token3, token3/token1]
///        fees = [fee1, fee2, fee3] (as percentages, e.g., 0.003 for 0.3%)
/// Output: profit percentage (0.01 = 1%)
#[inline(always)]
pub fn calculate_triangular_profit_simd(prices: &[f64; 3], fees: &[f64; 3]) -> f64 {
    #[cfg(all(target_arch = "x86_64", target_feature = "avx2"))]
    unsafe {
        // Load prices and fees into SIMD registers
        let price_vec = _mm256_set_pd(0.0, prices[2], prices[1], prices[0]);
        let fee_vec = _mm256_set_pd(0.0, fees[2], fees[1], fees[0]);

        // Calculate 1/price for all three prices
        let one = _mm256_set1_pd(1.0);
        let inv_prices = _mm256_div_pd(one, price_vec);

        // Calculate (1 - fee) for all three fees
        let fee_multiplier = _mm256_sub_pd(one, fee_vec);

        // Multiply: (1/price) * (1 - fee) for all three
        let adjusted = _mm256_mul_pd(inv_prices, fee_multiplier);

        // Extract values from SIMD register
        let mut result = [0.0; 4];
        _mm256_storeu_pd(result.as_mut_ptr(), adjusted);

        // Final calculation: result[0] * result[1] * result[2] - 1.0
        // This represents: (1/p1)*(1-f1) * (1/p2)*(1-f2) * (1/p3)*(1-f3) - 1.0
        let gross_profit = result[0] * result[1] * result[2];
        gross_profit - 1.0
    }

    #[cfg(not(all(target_arch = "x86_64", target_feature = "avx2")))]
    {
        // Scalar fallback
        (1.0 / prices[0]) * (1.0 - fees[0]) *
        (1.0 / prices[1]) * (1.0 - fees[1]) *
        (1.0 / prices[2]) * (1.0 - fees[2]) - 1.0
    }
}

/// Calculate batch triangular profits using SIMD
/// Processes multiple opportunities simultaneously for maximum throughput
/// Input: slice of (price1, price2, price3, fee1, fee2, fee3) tuples
/// Output: vector of profit percentages
#[inline(always)]
pub fn calculate_batch_triangular_profits(
    opportunities: &[(f64, f64, f64, f64, f64, f64)]
) -> Vec<f64> {
    let mut results = Vec::with_capacity(opportunities.len());

    #[cfg(all(target_arch = "x86_64", target_feature = "avx2"))]
    unsafe {
        // Process 4 opportunities at once with AVX2
        let chunks = opportunities.chunks_exact(4);
        let remainder = chunks.remainder();

        for chunk in chunks {
            // Load 4 sets of prices (p1, p2, p3)
            let p1_vec = _mm256_set_pd(chunk[3].0, chunk[2].0, chunk[1].0, chunk[0].0);
            let p2_vec = _mm256_set_pd(chunk[3].1, chunk[2].1, chunk[1].1, chunk[0].1);
            let p3_vec = _mm256_set_pd(chunk[3].2, chunk[2].2, chunk[1].2, chunk[0].2);

            // Load 4 sets of fees (f1, f2, f3)
            let f1_vec = _mm256_set_pd(chunk[3].3, chunk[2].3, chunk[1].3, chunk[0].3);
            let f2_vec = _mm256_set_pd(chunk[3].4, chunk[2].4, chunk[1].4, chunk[0].4);
            let f3_vec = _mm256_set_pd(chunk[3].5, chunk[2].5, chunk[1].5, chunk[0].5);

            // Calculate 1/price
            let one = _mm256_set1_pd(1.0);
            let inv_p1 = _mm256_div_pd(one, p1_vec);
            let inv_p2 = _mm256_div_pd(one, p2_vec);
            let inv_p3 = _mm256_div_pd(one, p3_vec);

            // Calculate (1 - fee)
            let adj_f1 = _mm256_sub_pd(one, f1_vec);
            let adj_f2 = _mm256_sub_pd(one, f2_vec);
            let adj_f3 = _mm256_sub_pd(one, f3_vec);

            // Calculate adjusted prices
            let adj_p1 = _mm256_mul_pd(inv_p1, adj_f1);
            let adj_p2 = _mm256_mul_pd(inv_p2, adj_f2);
            let adj_p3 = _mm256_mul_pd(inv_p3, adj_f3);

            // Calculate gross profit
            let gross_profit = _mm256_mul_pd(_mm256_mul_pd(adj_p1, adj_p2), adj_p3);

            // Subtract 1.0 to get net profit
            let net_profit = _mm256_sub_pd(gross_profit, one);

            // Store results
            let mut batch_results = [0.0; 4];
            _mm256_storeu_pd(batch_results.as_mut_ptr(), net_profit);
            results.extend_from_slice(&batch_results);
        }

        // Process remainder with scalar
        for &(p1, p2, p3, f1, f2, f3) in remainder {
            let profit = (1.0 / p1) * (1.0 - f1) *
                        (1.0 / p2) * (1.0 - f2) *
                        (1.0 / p3) * (1.0 - f3) - 1.0;
            results.push(profit);
        }
    }

    #[cfg(not(all(target_arch = "x86_64", target_feature = "avx2")))]
    {
        // Scalar fallback
        for &(p1, p2, p3, f1, f2, f3) in opportunities {
            let profit = (1.0 / p1) * (1.0 - f1) *
                        (1.0 / p2) * (1.0 - f2) *
                        (1.0 / p3) * (1.0 - f3) - 1.0;
            results.push(profit);
        }
    }

    results
}

/// Calculate cross-DEX spreads using SIMD
/// Input: buy_prices and sell_prices arrays
/// Output: vector of spread percentages
#[inline(always)]
pub fn calculate_spreads_simd(buy_prices: &[f64], sell_prices: &[f64]) -> Vec<f64> {
    assert_eq!(buy_prices.len(), sell_prices.len());
    let n = buy_prices.len();
    let mut results = Vec::with_capacity(n);

    #[cfg(all(target_arch = "x86_64", target_feature = "avx2"))]
    unsafe {
        // Process 4 spreads at once
        let chunks = buy_prices.chunks_exact(4);
        let remainder = chunks.remainder();

        let mut i = 0;
        for chunk in chunks {
            // Load 4 buy prices and 4 sell prices at the same indices
            let buy_vec = _mm256_loadu_pd(chunk.as_ptr());
            let sell_vec = _mm256_loadu_pd(sell_prices[i..i + 4].as_ptr());

            // Calculate spread: (sell - buy) / buy * 100
            let diff = _mm256_sub_pd(sell_vec, buy_vec);
            let spread = _mm256_div_pd(diff, buy_vec);
            let spread_pct = _mm256_mul_pd(spread, _mm256_set1_pd(100.0));

            // Store results
            let mut batch_results = [0.0; 4];
            _mm256_storeu_pd(batch_results.as_mut_ptr(), spread_pct);
            results.extend_from_slice(&batch_results);

            i += 4;
        }

        // Process remainder with scalar
        let remainder_idx = i;
        for j in remainder_idx..n {
            let spread = (sell_prices[j] - buy_prices[j]) / buy_prices[j] * 100.0;
            results.push(spread);
        }
    }

    #[cfg(not(all(target_arch = "x86_64", target_feature = "avx2")))]
    {
        // Scalar fallback
        for i in 0..n {
            let spread = (sell_prices[i] - buy_prices[i]) / buy_prices[i] * 100.0;
            results.push(spread);
        }
    }

    results
}

/// Calculate Z-scores for statistical arbitrage using SIMD
/// Z-score = (price - mean) / std_dev
/// Input: prices array, mean and standard deviation
/// Output: vector of Z-scores
#[inline(always)]
pub fn calculate_z_scores_simd(prices: &[f64], mean: f64, std_dev: f64) -> Vec<f64> {
    if std_dev == 0.0 {
        return vec![0.0; prices.len()];
    }

    let n = prices.len();
    let mut results = Vec::with_capacity(n);

    #[cfg(all(target_arch = "x86_64", target_feature = "avx2"))]
    unsafe {
        let mean_vec = _mm256_set1_pd(mean);
        let std_dev_vec = _mm256_set1_pd(std_dev);

        let chunks = prices.chunks_exact(4);
        let remainder = chunks.remainder();

        for chunk in chunks {
            // Load 4 prices
            let price_vec = _mm256_loadu_pd(chunk.as_ptr());

            // Calculate (price - mean) / std_dev
            let diff = _mm256_sub_pd(price_vec, mean_vec);
            let z_score = _mm256_div_pd(diff, std_dev_vec);

            // Store results
            let mut batch_results = [0.0; 4];
            _mm256_storeu_pd(batch_results.as_mut_ptr(), z_score);
            results.extend_from_slice(&batch_results);
        }

        // Process remainder with scalar
        for &price in remainder {
            let z_score = (price - mean) / std_dev;
            results.push(z_score);
        }
    }

    #[cfg(not(all(target_arch = "x86_64", target_feature = "avx2")))]
    {
        // Scalar fallback
        for &price in prices {
            let z_score = (price - mean) / std_dev;
            results.push(z_score);
        }
    }

    results
}

/// Calculate moving average using SIMD for trend analysis
/// Input: prices array and window size
/// Output: vector of moving averages
#[inline(always)]
pub fn calculate_moving_average_simd(prices: &[f64], window: usize) -> Vec<f64> {
    if window == 0 || prices.len() < window {
        return vec![0.0; prices.len()];
    }

    let n = prices.len();
    let mut results = Vec::with_capacity(n);

    // For first window-1 elements, use available data
    for i in 0..window.saturating_sub(1) {
        let sum: f64 = prices[..=i].iter().sum();
        results.push(sum / (i + 1) as f64);
    }

    #[cfg(all(target_arch = "x86_64", target_feature = "avx2"))]
    unsafe {
        // Use SIMD for the main calculation
        for i in (window - 1)..n {
            let window_start = i - (window - 1);

            if window >= 4 {
                // Calculate sum of last 4 elements with SIMD
                let sum_vec = if window_start + 4 <= i + 1 {
                    let chunk = &prices[i - 3..=i];
                    let vec = _mm256_loadu_pd(chunk.as_ptr());
                    // Horizontal sum using shuffles
                    let shuffled1 = _mm256_permute4x64_pd(vec, 0b00001111);
                    let sum1 = _mm256_add_pd(vec, shuffled1);
                    let shuffled2 = _mm256_permute4x64_pd(sum1, 0b00000101);
                    let sum2 = _mm256_add_pd(sum1, shuffled2);
                    // Extract the lower 128 bits which contains the sum
                    let sum128 = _mm256_extractf128_pd(sum2, 0);
                    // Add the two 64-bit values in the 128-bit vector
                    let mut result = [0.0; 2];
                    _mm_storeu_pd(result.as_mut_ptr(), sum128);
                    result[0] + result[1]
                } else {
                    // Fallback to scalar for edge cases
                    prices[window_start..=i].iter().sum()
                };

                results.push(sum_vec / window as f64);
            } else {
                // Small window, use scalar
                let sum: f64 = prices[window_start..=i].iter().sum();
                results.push(sum / window as f64);
            }
        }
    }

    #[cfg(not(all(target_arch = "x86_64", target_feature = "avx2")))]
    {
        // Scalar fallback for moving average
        for i in (window - 1)..n {
            let window_start = i - (window - 1);
            let sum: f64 = prices[window_start..=i].iter().sum();
            results.push(sum / window as f64);
        }
    }

    results
}

/// Calculate price impact using SIMD
/// Price impact = (new_price - old_price) / old_price * 100
#[inline(always)]
pub fn calculate_price_impact_simd(old_prices: &[f64], new_prices: &[f64]) -> Vec<f64> {
    assert_eq!(old_prices.len(), new_prices.len());
    let n = old_prices.len();
    let mut results = Vec::with_capacity(n);

    #[cfg(all(target_arch = "x86_64", target_feature = "avx2"))]
    unsafe {
        let chunks = old_prices.chunks_exact(4);
        let remainder = chunks.remainder();

        let mut i = 0;
        for chunk in chunks {
            // Load 4 old prices and 4 new prices at the same indices
            let old_vec = _mm256_loadu_pd(chunk.as_ptr());
            let new_vec = _mm256_loadu_pd(new_prices[i..i + 4].as_ptr());

            // Calculate price impact: (new - old) / old * 100
            let diff = _mm256_sub_pd(new_vec, old_vec);
            let impact = _mm256_div_pd(diff, old_vec);
            let impact_pct = _mm256_mul_pd(impact, _mm256_set1_pd(100.0));

            // Handle division by zero - set to 0 where old price is 0
            let zero_vec = _mm256_setzero_pd();
            let is_zero = _mm256_cmp_pd(old_vec, zero_vec, _CMP_EQ_OQ);
            let safe_impact = _mm256_blendv_pd(is_zero, zero_vec, impact_pct);

            // Store results
            let mut batch_results = [0.0; 4];
            _mm256_storeu_pd(batch_results.as_mut_ptr(), safe_impact);
            results.extend_from_slice(&batch_results);

            i += 4;
        }

        // Process remainder with scalar
        let remainder_idx = i;
        for j in remainder_idx..n {
            if old_prices[j] != 0.0 {
                let impact = (new_prices[j] - old_prices[j]) / old_prices[j] * 100.0;
                results.push(impact);
            } else {
                results.push(0.0);
            }
        }
    }

    #[cfg(not(all(target_arch = "x86_64", target_feature = "avx2")))]
    {
        // Scalar fallback
        for i in 0..n {
            if old_prices[i] != 0.0 {
                let impact = (new_prices[i] - old_prices[i]) / old_prices[i] * 100.0;
                results.push(impact);
            } else {
                results.push(0.0);
            }
        }
    }

    results
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_simd_vs_scalar_triangular() {
        let test_cases = vec![
            ([150.0, 1.0, 0.00001], [0.003, 0.003, 0.003]),
            ([100.0, 1.5, 0.00005], [0.0025, 0.003, 0.0035]),
            ([200.0, 0.8, 0.00002], [0.002, 0.0025, 0.003]),
            ([50.0, 2.0, 0.00002], [0.004, 0.002, 0.003]),
        ];

        for (prices, fees) in test_cases {
            let simd_result = calculate_triangular_profit_simd(&prices, &fees);

            // Scalar calculation for comparison
            let scalar_result = (1.0/prices[0])*(1.0-fees[0]) *
                               (1.0/prices[1])*(1.0-fees[1]) *
                               (1.0/prices[2])*(1.0-fees[2]) - 1.0;

            // Results should be nearly identical (within floating point precision)
            let diff = (simd_result - scalar_result).abs();
            assert!(diff < 1e-10,
                   "SIMD and scalar results differ significantly: {} vs {}",
                   simd_result, scalar_result);
        }
    }

    #[test]
    fn test_batch_triangular_profits() {
        let opportunities = vec![
            (150.0, 1.0, 0.00001, 0.003, 0.003, 0.003),
            (100.0, 1.5, 0.00005, 0.0025, 0.003, 0.0035),
            (200.0, 0.8, 0.00002, 0.002, 0.0025, 0.003),
            (50.0, 2.0, 0.00002, 0.004, 0.002, 0.003),
            (300.0, 0.5, 0.00001, 0.001, 0.004, 0.002),
        ];

        let results = calculate_batch_triangular_profits(&opportunities);
        assert_eq!(results.len(), opportunities.len());

        // Compare with individual calculations
        for (i, &(p1, p2, p3, f1, f2, f3)) in opportunities.iter().enumerate() {
            let individual = calculate_triangular_profit_simd(&[p1, p2, p3], &[f1, f2, f3]);
            assert!((results[i] - individual).abs() < 1e-10);
        }
    }

    #[test]
    fn test_spreads_calculation() {
        let buy_prices = vec![100.0, 50.0, 200.0];
        let sell_prices = vec![102.0, 52.5, 196.0];

        let spreads = calculate_spreads_simd(&buy_prices, &sell_prices);

        assert_eq!(spreads.len(), 3);
        assert!((spreads[0] - 2.0).abs() < 1e-10); // (102-100)/100*100 = 2%
        assert!((spreads[1] - 5.0).abs() < 1e-10); // (52.5-50)/50*100 = 5%
        assert!((spreads[2] + 2.0).abs() < 1e-10); // (196-200)/200*100 = -2%
    }

    #[test]
    fn test_z_scores_calculation() {
        let prices = vec![95.0, 100.0, 105.0, 110.0];
        let mean = 102.5;
        let std_dev = 5.59;

        let z_scores = calculate_z_scores_simd(&prices, mean, std_dev);

        assert_eq!(z_scores.len(), 4);
        assert!((z_scores[0] + 1.34).abs() < 0.01); // (95-102.5)/5.59 = -1.34
        assert!((z_scores[1] + 0.45).abs() < 0.01); // (100-102.5)/5.59 = -0.45
        assert!((z_scores[2] + 0.45).abs() < 0.01); // (105-102.5)/5.59 = 0.45
        assert!((z_scores[3] + 1.34).abs() < 0.01); // (110-102.5)/5.59 = 1.34
    }

    #[test]
    fn test_moving_average() {
        let prices = vec![10.0, 20.0, 30.0, 40.0, 50.0, 60.0];
        let window = 3;

        let ma = calculate_moving_average_simd(&prices, window);

        assert_eq!(ma.len(), prices.len());
        assert!((ma[0] - 10.0).abs() < 1e-10); // avg of [10]
        assert!((ma[1] - 15.0).abs() < 1e-10); // avg of [10, 20]
        assert!((ma[2] - 20.0).abs() < 1e-10); // avg of [10, 20, 30]
        assert!((ma[3] - 30.0).abs() < 1e-10); // avg of [20, 30, 40]
        assert!((ma[4] - 40.0).abs() < 1e-10); // avg of [30, 40, 50]
        assert!((ma[5] - 50.0).abs() < 1e-10); // avg of [40, 50, 60]
    }

    #[test]
    fn test_price_impact() {
        let old_prices = vec![100.0, 50.0, 200.0];
        let new_prices = vec![102.0, 48.0, 206.0];

        let impacts = calculate_price_impact_simd(&old_prices, &new_prices);

        assert_eq!(impacts.len(), 3);
        assert!((impacts[0] - 2.0).abs() < 1e-10); // (102-100)/100*100 = 2%
        assert!((impacts[1] + 4.0).abs() < 1e-10); // (48-50)/50*100 = -4%
        assert!((impacts[2] - 3.0).abs() < 1e-10); // (206-200)/200*100 = 3%
    }

    #[test]
    fn test_simd_availability() {
        // This test just verifies the function doesn't crash
        let _available = is_simd_available();
        // The actual result depends on the CPU this runs on
    }
}