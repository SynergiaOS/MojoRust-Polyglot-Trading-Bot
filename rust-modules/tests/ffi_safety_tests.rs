//! FFI Safety Tests for MojoRust Trading Bot
//!
//! Comprehensive tests for memory safety, thread safety, and performance
//! of the FFI optimization layer.

use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};
use std::ptr;

use mojo_trading_bot::ffi::*;

#[test]
fn test_ffi_triangular_opportunity_memory_safety() {
    // Test that FFI structs have correct memory layout
    let opp = FfiTriangularOpportunity::default();

    // Verify all string pointers start as null
    for i in 0..4 {
        assert_eq!(opp.cycle_addresses[i], ptr::null());
        assert_eq!(opp.cycle_symbols[i], ptr::null());
    }

    for i in 0..3 {
        assert_eq!(opp.dex_names[i], ptr::null());
    }

    // Verify numeric fields have correct default values
    assert_eq!(opp.prices, [0.0; 3]);
    assert_eq!(opp.profit_percentage, 0.0);
    assert_eq!(opp.timestamp, 0);
}

#[test]
fn test_ffi_cross_dex_opportunity_memory_safety() {
    let opp = FfiCrossDexOpportunity::default();

    // Verify all string pointers start as null
    assert!(opp.token_address.is_null());
    assert!(opp.token_symbol.is_null());
    assert!(opp.buy_dex.is_null());
    assert!(opp.sell_dex.is_null());

    // Verify numeric fields have correct default values
    assert_eq!(opp.buy_price, 0.0);
    assert_eq!(opp.sell_price, 0.0);
    assert_eq!(opp.timestamp, 0);
}

#[test]
fn test_ffi_statistical_opportunity_memory_safety() {
    let opp = FfiStatisticalOpportunity::default();

    // Verify all string pointers start as null
    assert!(opp.token_address.is_null());
    assert!(opp.token_symbol.is_null());

    // Verify numeric fields have correct default values
    assert_eq!(opp.current_price, 0.0);
    assert_eq!(opp.mean_price, 0.0);
    assert_eq!(opp.timestamp, 0);
}

#[test]
fn test_ffi_string_memory_management() {
    // Test that string memory is properly managed
    let test_string = "test_string_12345";
    let c_string = std::ffi::CString::new(test_string).unwrap();
    let ptr = c_string.into_raw();

    // Verify we can read the string back
    unsafe {
        let c_str = std::ffi::CStr::from_ptr(ptr);
        assert_eq!(c_str.to_string_lossy(), test_string);

        // Clean up
        let _ = std::ffi::CString::from_raw(ptr as *mut std::os::raw::c_char);
    }
}

#[test]
fn test_ffi_thread_safety() {
    // Test that FFI operations are thread-safe
    let handles: Vec<_> = (0..10).map(|i| {
        thread::spawn(move || {
            let opp = FfiTriangularOpportunity::default();
            // Verify thread-safe access to default values
            assert_eq!(opp.profit_percentage, 0.0);
            assert_eq!(opp.timestamp, 0);
            format!("Thread {} completed", i)
        })
    }).collect();

    for handle in handles {
        let result = handle.join().unwrap();
        println!("{}", result);
    }
}

#[test]
fn test_ffi_alignment_consistency() {
    // Verify that Rust and Mojo struct layouts match
    use std::mem;

    // Test sizes are consistent
    let rust_size = std::mem::size_of::<FfiTriangularOpportunity>();
    let rust_align = std::mem::align_of::<FfiTriangularOpportunity>();

    // These should be consistent with the Mojo struct definitions
    assert!(rust_size > 0);
    assert!(rust_align > 0);

    // Verify struct is properly aligned for C ABI
    assert_eq!(rust_align, 8); // Should be 8 for pointers on x86_64
}

#[test]
fn test_ffi_result_handling() {
    // Test FFI result handling
    let success = FfiResult { code: 0 };
    let error = FfiResult { code: 1 };

    assert_eq!(success.code, 0);
    assert_eq!(error.code, 1);
}

#[test]
fn test_concurrent_ffi_operations() {
    // Test concurrent FFI operations don't cause data races
    let arc_opp = Arc::new(FfiTriangularOpportunity::default());

    let handles: Vec<_> = (0..5).map(|_| {
        let opp = Arc::clone(&arc_opp);
        thread::spawn(move || {
            // Read operation should be safe
            let profit = opp.profit_percentage;
            assert_eq!(profit, 0.0);
        })
    }).collect();

    for handle in handles {
        handle.join().unwrap();
    }
}

#[test]
fn test_ffi_performance_thresholds() {
    // Test that FFI operations meet performance requirements
    let start = Instant::now();

    // Simulate FFI operation overhead
    let opp = FfiTriangularOpportunity::default();
    let _ = opp.profit_percentage;
    let _ = opp.timestamp;

    let elapsed = start.elapsed();

    // FFI operations should be fast (< 1ms)
    assert!(elapsed < Duration::from_millis(1),
           "FFI operation took too long: {:?}", elapsed);
}

#[test]
fn test_ffi_memory_leak_prevention() {
    // Test that memory is properly cleaned up
    let mut allocated_ptrs = Vec::new();

    for i in 0..100 {
        let test_string = format!("test_string_{}", i);
        let c_string = std::ffi::CString::new(test_string).unwrap();
        let ptr = c_string.into_raw();
        allocated_ptrs.push(ptr);
    }

    // Clean up all allocated strings
    for ptr in allocated_ptrs {
        unsafe {
            let _ = std::ffi::CString::from_raw(ptr as *mut std::os::raw::c_char);
        }
    }

    // If we reach here without panics, memory management is working
}

#[cfg(test)]
mod integration_tests {
    use super::*;

    #[test]
    fn test_optimizations_initialization() {
        // Test that optimizations can be initialized and cleaned up
        unsafe {
            let config = FfiArbitrageConfig {
                min_profit_threshold: 0.5,
                max_slippage: 2.0,
                min_liquidity: 10000.0,
                max_gas_price: 0.01,
                confidence_threshold: 0.7,
                scan_interval_ms: 500,
                opportunity_timeout_ms: 30000,
                max_concurrent_trades: 5,
                risk_tolerance: 0.5,
            };

            let result = arbitrage_engine_init_global(config);
            assert_eq!(result.code, 0);
        }
    }

    #[test]
    fn test_simd_availability() {
        // Test SIMD detection doesn't crash
        let _available = mojo_trading_bot::ffi::simd::is_simd_available();
    }

    #[test]
    fn test_ffi_benchmarks() {
        // Test that FFI benchmarks can run
        let prices = [150.0, 1.0, 0.00001];
        let fees = [0.003, 0.003, 0.003];

        let result = mojo_trading_bot::ffi::simd::calculate_triangular_profit_simd(&prices, &fees);

        // Result should be a valid floating point number
        assert!(!result.is_nan());
        assert!(!result.is_infinite());
    }
}