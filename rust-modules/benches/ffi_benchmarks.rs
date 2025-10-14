//! Comprehensive FFI Performance Benchmarks
//!
//! Tests the performance impact of FFI optimizations including:
//! - Memory pooling vs standard allocation
//! - String interning vs regular strings
//! - SIMD calculations vs scalar fallback
//! - Async worker pool vs blocking calls
//! - Batch processing vs individual operations

use criterion::{black_box, criterion_group, criterion_main, Criterion, BenchmarkId, Throughput};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

// Import modules to benchmark
use mojo_trading_bot::ffi::{
    optimized::{ObjectPool, StringInterner, AsyncWorkerPool},
    simd::{
        calculate_triangular_profit_simd, calculate_batch_triangular_profits,
        calculate_spreads_simd, calculate_z_scores_simd, is_simd_available
    },
    FfiTriangularOpportunity, FfiPriceUpdate, FfiTriangularBatchInput,
    ffi_initialize_optimizations, arbitrage_engine_get_triangular_opportunities_fast,
    arbitrage_engine_update_price_batch, arbitrage_worker_pool_submit_scan,
    arbitrage_worker_pool_poll_result, ffi_is_simd_available,
    ffi_calculate_triangular_profit_simd, ffi_calculate_batch_triangular_profits,
    arbitrage_engine_new, arbitrage_engine_init_global, arbitrage_engine_register_token,
    arbitrage_engine_update_price, arbitrage_engine_scan_opportunities,
    FfiArbitrageConfig
};
use mojo_trading_bot::arbitrage::{ArbitrageEngine, ArbitrageConfig, TokenInfo, DexPrice};
use tokio::runtime::Runtime;

// Global runtime for async benchmarks
static RT: OnceLock<Arc<Mutex<Option<Runtime>>>> = OnceLock::new();

fn get_runtime() -> Arc<Mutex<Option<Runtime>>> {
    RT.get_or_init(|| {
        Arc::new(Mutex::new(Some(
            Runtime::new().expect("Failed to create tokio runtime")
        )))
    }).clone()
}

// =============================================================================
// Memory Pool Benchmarks
// =============================================================================

fn bench_object_pool_vs_allocation(c: &mut Criterion) {
    let mut group = c.benchmark_group("object_pool_vs_allocation");

    // Test different pool sizes
    for size in [10, 50, 100, 500].iter() {
        group.throughput(Throughput::Elements(*size as u64));

        // Benchmark object pool
        group.bench_with_input(
            BenchmarkId::new("object_pool", size),
            size,
            |b, &size| {
                let pool = ObjectPool::<TestStruct>::new(size);
                b.iter(|| {
                    let mut objects = Vec::with_capacity(size);
                    for _ in 0..size {
                        let obj = pool.acquire();
                        objects.push(obj);
                    }
                    // Objects are automatically returned to pool when dropped
                });
            },
        );

        // Benchmark direct allocation
        group.bench_with_input(
            BenchmarkId::new("direct_allocation", size),
            size,
            |b, &size| {
                b.iter(|| {
                    let mut objects = Vec::with_capacity(size);
                    for _ in 0..size {
                        let obj = Box::new(TestStruct::default());
                        objects.push(obj);
                    }
                });
            },
        );
    }

    group.finish();
}

#[derive(Debug, Default)]
struct TestStruct {
    data: [f64; 16],
    text: String,
}

// =============================================================================
// String Interning Benchmarks
// =============================================================================

fn bench_string_interning_vs_regular(c: &mut Criterion) {
    let mut group = c.benchmark_group("string_interning_vs_regular");

    let common_strings = vec![
        "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", // USDC
        "So11111111111111111111111111111111111111112",   // SOL
        "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB", // USDT
        "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263", // Bonk
        "mSoLzYCxHdYgdzU16g5QSh3i5K3z3KZK7ytfqcJm7So",  // Marinade SOL
    ];

    // Test string operations
    for &num_strings in [100, 500, 1000, 5000].iter() {
        group.throughput(Throughput::Elements(num_strings));

        // Benchmark string interning
        group.bench_with_input(
            BenchmarkId::new("string_interner", num_strings),
            &num_strings,
            |b, &num_strings| {
                let interner = StringInterner::new(1000);
                b.iter(|| {
                    let mut ptrs = Vec::with_capacity(num_strings);
                    for _ in 0..num_strings {
                        let s = common_strings[fastrand::usize(..common_strings.len())];
                        let ptr = interner.intern(s);
                        ptrs.push(ptr);
                    }
                });
            },
        );

        // Benchmark regular CString creation
        group.bench_with_input(
            BenchmarkId::new("regular_cstring", num_strings),
            &num_strings,
            |b, &num_strings| {
                b.iter(|| {
                    let mut strings = Vec::with_capacity(num_strings);
                    for _ in 0..num_strings {
                        let s = common_strings[fastrand::usize(..common_strings.len())];
                        let cstring = CString::new(s).unwrap();
                        strings.push(cstring.into_raw());
                    }
                    // Cleanup
                    for ptr in strings {
                        unsafe { let _ = CString::from_raw(ptr as *mut c_char); }
                    }
                });
            },
        );
    }

    group.finish();
}

// =============================================================================
// SIMD Benchmarks
// =============================================================================

fn bench_triangular_profit_simd_vs_scalar(c: &mut Criterion) {
    let mut group = c.benchmark_group("triangular_profit_calculation");

    let test_cases = vec![
        ([150.0, 1.0, 0.00001], [0.003, 0.003, 0.003]),
        ([100.0, 1.5, 0.00005], [0.0025, 0.003, 0.0035]),
        ([200.0, 0.8, 0.00002], [0.002, 0.0025, 0.003]),
        ([50.0, 2.0, 0.00002], [0.004, 0.002, 0.003]),
    ];

    for &num_calculations in [1000, 5000, 10000, 50000].iter() {
        group.throughput(Throughput::Elements(num_calculations));

        // Benchmark SIMD calculation
        group.bench_with_input(
            BenchmarkId::new("simd", num_calculations),
            &num_calculations,
            |b, &num_calculations| {
                b.iter(|| {
                    for _ in 0..num_calculations {
                        let case = test_cases[fastrand::usize(..test_cases.len())];
                        let result = calculate_triangular_profit_simd(&case.0, &case.1);
                        black_box(result);
                    }
                });
            },
        );

        // Benchmark scalar calculation
        group.bench_with_input(
            BenchmarkId::new("scalar", num_calculations),
            &num_calculations,
            |b, &num_calculations| {
                b.iter(|| {
                    for _ in 0..num_calculations {
                        let case = test_cases[fastrand::usize(..test_cases.len())];
                        let result = (1.0 / case.0[0]) * (1.0 - case.1[0]) *
                                   (1.0 / case.0[1]) * (1.0 - case.1[1]) *
                                   (1.0 / case.0[2]) * (1.0 - case.1[2]) - 1.0;
                        black_box(result);
                    }
                });
            },
        );
    }

    group.finish();
}

fn bench_batch_triangular_profits(c: &mut Criterion) {
    let mut group = c.benchmark_group("batch_triangular_profits");

    let test_cases: Vec<(f64, f64, f64, f64, f64, f64)> = vec![
        (150.0, 1.0, 0.00001, 0.003, 0.003, 0.003),
        (100.0, 1.5, 0.00005, 0.0025, 0.003, 0.0035),
        (200.0, 0.8, 0.00002, 0.002, 0.0025, 0.003),
        (50.0, 2.0, 0.00002, 0.004, 0.002, 0.003),
        (300.0, 0.5, 0.00001, 0.001, 0.004, 0.002),
        (75.0, 1.2, 0.00003, 0.0025, 0.0035, 0.003),
        (120.0, 0.9, 0.00002, 0.003, 0.0025, 0.004),
        (180.0, 1.1, 0.000015, 0.002, 0.003, 0.0035),
    ];

    for &batch_size in [100, 500, 1000, 5000].iter() {
        group.throughput(Throughput::Elements(batch_size));

        // Generate test data
        let mut batch_data = Vec::with_capacity(batch_size);
        for _ in 0..batch_size {
            let case = test_cases[fastrand::usize(..test_cases.len())];
            batch_data.push(case);
        }

        // Benchmark batch SIMD processing
        group.bench_with_input(
            BenchmarkId::new("batch_simd", batch_size),
            &batch_size,
            |b, _| {
                b.iter(|| {
                    let results = calculate_batch_triangular_profits(&batch_data);
                    black_box(results);
                });
            },
        );

        // Benchmark individual scalar processing
        group.bench_with_input(
            BenchmarkId::new("individual_scalar", batch_size),
            &batch_size,
            |b, _| {
                b.iter(|| {
                    let mut results = Vec::with_capacity(batch_size);
                    for &(p1, p2, p3, f1, f2, f3) in &batch_data {
                        let result = (1.0 / p1) * (1.0 - f1) *
                                   (1.0 / p2) * (1.0 - f2) *
                                   (1.0 / p3) * (1.0 - f3) - 1.0;
                        results.push(result);
                    }
                    black_box(results);
                });
            },
        );
    }

    group.finish();
}

// =============================================================================
// Async Worker Pool Benchmarks
// =============================================================================

fn bench_async_worker_pool_vs_blocking(c: &mut Criterion) {
    let mut group = c.benchmark_group("async_worker_pool_vs_blocking");

    // Initialize optimizations
    ffi_initialize_optimizations(4);

    // Initialize arbitrage engine
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

    unsafe {
        arbitrage_engine_init_global(config);

        // Register test tokens
        arbitrage_engine_register_token(
            CString::new("So11111111111111111111111111111111111111112").unwrap().as_ptr(),
            CString::new("SOL").unwrap().as_ptr(),
            CString::new("Solana").unwrap().as_ptr(),
            9,
            1,
        );

        arbitrage_engine_register_token(
            CString::new("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v").unwrap().as_ptr(),
            CString::new("USDC").unwrap().as_ptr(),
            CString::new("USD Coin").unwrap().as_ptr(),
            6,
            1,
        );
    }

    for &num_operations in [10, 50, 100, 500].iter() {
        group.throughput(Throughput::Elements(num_operations));

        // Benchmark async worker pool
        group.bench_with_input(
            BenchmarkId::new("async_worker_pool", num_operations),
            &num_operations,
            |b, &num_operations| {
                b.iter(|| {
                    let mut task_ids = Vec::with_capacity(num_operations);

                    // Submit tasks
                    for _ in 0..num_operations {
                        let task_id = unsafe { arbitrage_worker_pool_submit_scan() };
                        if task_id > 0 {
                            task_ids.push(task_id);
                        }
                    }

                    // Wait for results
                    let rt = get_runtime().lock().unwrap().as_ref().unwrap().clone();
                    rt.block_on(async {
                        for task_id in task_ids {
                            let mut completed = false;
                            for _ in 0..100 { // Max 100 attempts
                                let mut triangular_count = 0usize;
                                let mut cross_dex_count = 0usize;
                                let mut statistical_count = 0usize;
                                let mut is_complete = false;

                                unsafe {
                                    let result = arbitrage_worker_pool_poll_result(
                                        task_id,
                                        &mut triangular_count,
                                        &mut cross_dex_count,
                                        &mut statistical_count,
                                        &mut is_complete,
                                    );

                                    if is_complete || result != mojo_trading_bot::ffi::FfiResult::Success {
                                        completed = true;
                                        break;
                                    }
                                }

                                if !completed {
                                    tokio::time::sleep(Duration::from_millis(1)).await;
                                }
                            }
                        }
                    });
                });
            },
        );

        // Benchmark blocking calls
        group.bench_with_input(
            BenchmarkId::new("blocking_calls", num_operations),
            &num_operations,
            |b, &num_operations| {
                let rt = get_runtime().lock().unwrap().as_ref().unwrap().clone();
                b.iter(|| {
                    rt.block_on(async {
                        for _ in 0..num_operations {
                            let mut triangular_count = 0usize;
                            let mut cross_dex_count = 0usize;
                            let mut statistical_count = 0usize;

                            unsafe {
                                let _ = arbitrage_engine_scan_opportunities(
                                    &mut triangular_count,
                                    &mut cross_dex_count,
                                    &mut statistical_count,
                                );
                            }
                        }
                    });
                });
            },
        );
    }

    group.finish();
}

// =============================================================================
// FFI Function Benchmarks
// =============================================================================

fn bench_ffi_function_overhead(c: &mut Criterion) {
    let mut group = c.benchmark_group("ffi_function_overhead");

    let prices = [150.0, 1.0, 0.00001];
    let fees = [0.003, 0.003, 0.003];

    for &num_calls in [1000, 5000, 10000, 50000].iter() {
        group.throughput(Throughput::Elements(num_calls));

        // Benchmark FFI function call overhead
        group.bench_with_input(
            BenchmarkId::new("ffi_triangular_simd", num_calls),
            &num_calls,
            |b, &num_calls| {
                b.iter(|| {
                    for _ in 0..num_calls {
                        let result = unsafe { ffi_calculate_triangular_profit_simd(
                            prices.as_ptr(),
                            fees.as_ptr(),
                        ) };
                        black_box(result);
                    }
                });
            },
        );

        // Benchmark direct function call
        group.bench_with_input(
            BenchmarkId::new("direct_triangular_simd", num_calls),
            &num_calls,
            |b, &num_calls| {
                b.iter(|| {
                    for _ in 0..num_calls {
                        let result = calculate_triangular_profit_simd(&prices, &fees);
                        black_box(result);
                    }
                });
            },
        );
    }

    group.finish();
}

// =============================================================================
// Batch vs Individual Operations Benchmarks
// =============================================================================

fn bench_batch_vs_individual_operations(c: &mut Criterion) {
    let mut group = c.benchmark_group("batch_vs_individual_operations");

    // Generate test price updates
    let test_updates: Vec<FfiPriceUpdate> = (0..1000)
        .map(|i| {
            let addr = format!("So111111111111111111111111111111111111111{:02x}", i % 256);
            let dex = if i % 2 == 0 { "raydium" } else { "jupiter" };
            let price = 100.0 + (i as f64 * 0.1);
            let liquidity = 10000.0 + (i as f64 * 100.0);
            let volume = 50000.0 + (i as f64 * 500.0);

            FfiPriceUpdate {
                token_address: CString::new(addr).unwrap().into_raw(),
                dex_name: CString::new(dex).unwrap().into_raw(),
                price,
                liquidity,
                volume_24h: volume,
            }
        })
        .collect();

    for &batch_size in [10, 50, 100, 500].iter() {
        group.throughput(Throughput::Elements(batch_size));

        // Benchmark batch update
        group.bench_with_input(
            BenchmarkId::new("batch_update", batch_size),
            &batch_size,
            |b, &batch_size| {
                b.iter(|| {
                    let updates = &test_updates[..batch_size];
                    let result = unsafe { arbitrage_engine_update_price_batch(updates.as_ptr(), batch_size) };
                    black_box(result);
                });
            },
        );

        // Benchmark individual updates
        group.bench_with_input(
            BenchmarkId::new("individual_updates", batch_size),
            &batch_size,
            |b, &batch_size| {
                b.iter(|| {
                    for update in &test_updates[..batch_size] {
                        let result = unsafe { arbitrage_engine_update_price(
                            update.token_address,
                            update.dex_name,
                            update.price,
                            update.liquidity,
                            update.volume_24h,
                        ) };
                        black_box(result);
                    }
                });
            },
        );
    }

    // Cleanup test data
    for update in test_updates {
        unsafe {
            let _ = CString::from_raw(update.token_address as *mut c_char);
            let _ = CString::from_raw(update.dex_name as *mut c_char);
        }
    }

    group.finish();
}

// =============================================================================
// Memory Usage Benchmarks
// =============================================================================

fn bench_memory_usage_patterns(c: &mut Criterion) {
    let mut group = c.benchmark_group("memory_usage_patterns");

    // Test memory patterns with and without optimizations
    for &num_objects in [100, 500, 1000, 5000].iter() {
        group.throughput(Throughput::Elements(num_objects));

        // Benchmark with optimizations
        group.bench_with_input(
            BenchmarkId::new("with_optimizations", num_objects),
            &num_objects,
            |b, &num_objects| {
                ffi_initialize_optimizations(4);
                b.iter(|| {
                    // Use fast opportunities function
                    let mut opportunities_ptr = std::ptr::null_mut();
                    let mut count = 0usize;
                    let result = unsafe { arbitrage_engine_get_triangular_opportunities_fast(
                        &mut opportunities_ptr,
                        &mut count,
                    ) };
                    black_box(result);
                    black_box(count);

                    // Cleanup
                    if !opportunities_ptr.is_null() {
                        unsafe {
                            let slice = std::slice::from_raw_parts_mut(opportunities_ptr, count);
                            for ffi_opp in slice {
                                // Free string pointers (simplified)
                                for addr_ptr in &ffi_opp.cycle_addresses {
                                    if !addr_ptr.is_null() {
                                        let _ = CString::from_raw(*addr_ptr as *mut c_char);
                                    }
                                }
                            }
                            let _ = Vec::from_raw_parts(opportunities_ptr, count, count);
                        }
                    }
                });
            },
        );

        // Benchmark without optimizations (regular allocation)
        group.bench_with_input(
            BenchmarkId::new("without_optimizations", num_objects),
            &num_objects,
            |b, &num_objects| {
                b.iter(|| {
                    // Create test structures manually
                    let mut opportunities = Vec::with_capacity(num_objects);
                    for i in 0..num_objects {
                        let opp = TestStruct {
                            data: [i as f64; 16],
                            text: format!("test_opportunity_{}", i),
                        };
                        opportunities.push(opp);
                    }
                    black_box(opportunities.len());
                });
            },
        );
    }

    group.finish();
}

// Register benchmark groups
criterion_group!(
    benches,
    bench_object_pool_vs_allocation,
    bench_string_interning_vs_regular,
    bench_triangular_profit_simd_vs_scalar,
    bench_batch_triangular_profits,
    bench_async_worker_pool_vs_blocking,
    bench_ffi_function_overhead,
    bench_batch_vs_individual_operations,
    bench_memory_usage_patterns
);

criterion_main!(benches);