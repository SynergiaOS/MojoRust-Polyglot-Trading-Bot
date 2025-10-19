//! Save Flash Loan Performance Benchmarks
//! Latency and throughput testing with Criterion

use criterion::{black_box, criterion_group, criterion_main, Criterion, BenchmarkId, Throughput};
use solana_sdk::{signature::Keypair, pubkey::Pubkey, transaction::Transaction};
use serde_json::json;
use std::time::Duration;
use tokio::runtime::Runtime;
use std::sync::Arc;

// Mock implementations for benchmarking
struct MockSaveFlashLoanExecutor {
    client: Arc<reqwest::Client>,
    save_program_id: Pubkey,
}

impl MockSaveFlashLoanExecutor {
    fn new() -> Self {
        Self {
            client: Arc::new(reqwest::Client::new()),
            save_program_id: solana_program::pubkey!("SAVe7x8r3PUUyL6pzT6s3nr1T9b4wxxA2pYFnzFvLaV"),
        }
    }

    async fn execute_flash_loan(
        &self,
        keypair: &Keypair,
        token_mint: &str,
        amount: u64,
        quote: serde_json::Value,
    ) -> Result<(), Box<dyn std::error::Error>> {
        // Simulate Save flash loan execution phases

        // Phase 1: Dynamic fee calculation (simulated)
        tokio::time::sleep(Duration::from_millis(2)).await;
        let priority_fee = 1000; // Mock priority fee

        // Phase 2: Jupiter swap instruction creation (simulated)
        tokio::time::sleep(Duration::from_millis(5)).await;
        let swap_instruction = create_mock_swap_instruction(&quote);

        // Phase 3: Save flash loan instructions creation
        tokio::time::sleep(Duration::from_millis(3)).await;
        let save_instructions = create_mock_save_instructions(amount, &self.save_program_id, keypair);

        // Phase 4: Transaction construction and signing
        tokio::time::sleep(Duration::from_millis(4)).await;
        let mut instructions = vec![];
        instructions.extend(save_instructions);
        instructions.push(swap_instruction);

        // Add compute budget instruction
        instructions.insert(0, solana_sdk::compute_budget::ComputeBudgetInstruction::set_compute_unit_price(priority_fee));

        let tx = Transaction::new_signed_with_payer(
            &instructions,
            Some(&keypair.pubkey()),
            vec![keypair],
            Pubkey::new_unique(), // Mock recent blockhash
        );

        // Phase 5: Jito bundle submission (simulated)
        tokio::time::sleep(Duration::from_millis(6)).await;
        let bundle_result = submit_mock_jito_bundle(&tx).await;

        if !bundle_result.success {
            return Err("Bundle submission failed".into());
        }

        Ok(())
    }
}

fn create_mock_swap_instruction(quote: &serde_json::Value) -> solana_sdk::instruction::Instruction {
    // Mock Jupiter swap instruction
    solana_sdk::instruction::Instruction::new_with_bytes(
        solana_program::pubkey!("JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4"),
        &base64::decode("mock_swap_instruction_data").unwrap_or_default(),
        vec![],
    )
}

fn create_mock_save_instructions(
    amount: u64,
    save_program_id: &Pubkey,
    keypair: &Keypair,
) -> Vec<solana_sdk::instruction::Instruction> {
    let reserve = Pubkey::new_unique();

    // Flash loan begin instruction
    let mut begin_data = vec![0u8]; // Begin marker
    begin_data.extend_from_slice(&amount.to_le_bytes());

    let begin_instruction = solana_sdk::instruction::Instruction::new_with_bytes(
        *save_program_id,
        &begin_data,
        vec![
            solana_sdk::instruction::AccountMeta::new(reserve, false),
            solana_sdk::instruction::AccountMeta::new(keypair.pubkey(), true),
        ],
    );

    // Flash loan end instruction
    let repayment_amount = amount + (amount * 3 / 10000); // Add 0.03% fee
    let mut end_data = vec![1u8]; // End marker
    end_data.extend_from_slice(&amount.to_le_bytes());
    end_data.extend_from_slice(&repayment_amount.to_le_bytes());

    let end_instruction = solana_sdk::instruction::Instruction::new_with_bytes(
        *save_program_id,
        &end_data,
        vec![
            solana_sdk::instruction::AccountMeta::new(reserve, false),
            solana_sdk::instruction::AccountMeta::new(keypair.pubkey(), true),
        ],
    );

    vec![begin_instruction, end_instruction]
}

async fn submit_mock_jito_bundle(transaction: &Transaction) -> MockBundleResult {
    // Simulate Jito bundle submission with realistic latency
    tokio::time::sleep(Duration::from_millis(10 + fastrand::u64(0..10))).await;

    // Simulate 85% success rate
    if fastrand::f64() < 0.85 {
        MockBundleResult {
            success: true,
            bundle_id: format!("bundle_{}", fastrand::u64(1000..9999)),
            signatures: vec![format!("signature_{}", fastrand::u64(10000..99999))],
            execution_time_ms: 15 + fastrand::u64(0..10),
        }
    } else {
        MockBundleResult {
            success: false,
            bundle_id: format!("failed_bundle_{}", fastrand::u64(1000..9999)),
            signatures: vec![],
            execution_time_ms: 25 + fastrand::u64(0..15),
        }
    }
}

#[derive(Debug, Clone)]
struct MockBundleResult {
    success: bool,
    bundle_id: String,
    signatures: Vec<String>,
    execution_time_ms: u64,
}

fn bench_save_flash_loan_single(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let executor = MockSaveFlashLoanExecutor::new();
    let keypair = Keypair::new();
    let token_mint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v";

    let quote = json!({
        "inputMint": "So11111111111111111111111111111111111111112",
        "outputMint": token_mint,
        "inAmount": "2000000000",
        "outAmount": "2100000000", // +5% profit
        "slippageBps": 50,
        "priceImpactPct": "0.15"
    });

    c.bench_function("save_flash_loan_single", |b| {
        b.to_async(&rt).iter(|| {
            let keypair = Keypair::new(); // Fresh keypair for each iteration
            executor.execute_flash_loan(
                black_box(&keypair),
                black_box(token_mint),
                black_box(2_000_000_000), // 2 SOL
                black_box(quote.clone())
            )
        });
    });
}

fn bench_save_flash_loan_different_amounts(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let executor = MockSaveFlashLoanExecutor::new();
    let token_mint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v";

    let amounts = vec![
        100_000_000,   // 0.1 SOL
        500_000_000,   // 0.5 SOL
        1_000_000_000, // 1 SOL
        2_000_000_000, // 2 SOL
        5_000_000_000, // 5 SOL (maximum)
    ];

    let mut group = c.benchmark_group("save_flash_loan_amounts");

    for amount in amounts {
        let quote = json!({
            "inputMint": "So11111111111111111111111111111111111111112",
            "outputMint": token_mint,
            "inAmount": amount.to_string(),
            "outAmount": (amount * 105 / 100).to_string(), // +5% profit
            "slippageBps": 50,
            "priceImpactPct": "0.15"
        });

        group.throughput(Throughput::Bytes(amount));
        group.bench_with_input(
            BenchmarkId::new("save_flash_loan", amount / 1_000_000_000), // Display in SOL
            &amount,
            |b, &amount| {
                b.to_async(&rt).iter(|| {
                    let keypair = Keypair::new();
                    executor.execute_flash_loan(
                        black_box(&keypair),
                        black_box(token_mint),
                        black_box(amount),
                        black_box(quote.clone())
                    )
                });
            },
        );
    }

    group.finish();
}

fn bench_save_flash_loan_concurrent(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let executor = Arc::new(MockSaveFlashLoanExecutor::new());
    let token_mint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v";

    let quote = json!({
        "inputMint": "So11111111111111111111111111111111111111112",
        "outputMint": token_mint,
        "inAmount": "1000000000",
        "outAmount": "1050000000",
        "slippageBps": 50,
        "priceImpactPct": "0.15"
    });

    let mut group = c.benchmark_group("save_flash_loan_concurrent");

    for concurrency in [1, 2, 4, 8] {
        group.bench_with_input(
            BenchmarkId::new("concurrent_flash_loans", concurrency),
            &concurrency,
            |b, &concurrency| {
                b.to_async(&rt).iter(|| {
                    let mut tasks = Vec::new();

                    for _ in 0..concurrency {
                        let exec = executor.clone();
                        let keypair = Keypair::new();
                        let quote_clone = quote.clone();
                        let token_clone = token_mint.to_string();

                        tasks.push(tokio::spawn(async move {
                            exec.execute_flash_loan(
                                &keypair,
                                &token_clone,
                                1_000_000_000,
                                quote_clone
                            ).await
                        }));
                    }

                    rt.block_on(async {
                        let results = futures::future::join_all(tasks).await;
                        let successful = results.iter().filter(|r| r.as_ref().unwrap().is_ok()).count();
                        black_box(successful);
                    });
                });
            },
        );
    }

    group.finish();
}

fn bench_instruction_creation(c: &mut Criterion) {
    let keypair = Keypair::new();
    let save_program_id = solana_program::pubkey!("SAVe7x8r3PUUyL6pzT6s3nr1T9b4wxxA2pYFnzFvLaV");

    let mut group = c.benchmark_group("instruction_creation");

    // Benchmark Save flash loan instructions creation
    group.bench_function("save_instructions", |b| {
        b.iter(|| {
            create_mock_save_instructions(
                black_box(2_000_000_000),
                black_box(&save_program_id),
                black_box(&keypair)
            )
        });
    });

    // Benchmark Jupiter swap instruction creation
    let quote = json!({
        "inputMint": "So11111111111111111111111111111111111111112",
        "outputMint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
        "outAmount": "2100000000"
    });

    group.bench_function("jupiter_swap_instruction", |b| {
        b.iter(|| create_mock_swap_instruction(black_box(&quote)))
    });

    group.finish();
}

fn bench_fee_calculation(c: &mut Criterion) {
    let mut group = c.benchmark_group("fee_calculation");

    let amounts = vec![
        100_000_000,   // 0.1 SOL
        1_000_000_000, // 1 SOL
        5_000_000_000, // 5 SOL
    ];

    for amount in amounts {
        group.bench_with_input(
            BenchmarkId::new("save_fee", amount / 1_000_000_000),
            &amount,
            |b, &amount| {
                b.iter(|| {
                    // Save fee calculation: amount * 3 / 10000 (0.03%)
                    black_box(amount * 3 / 10000)
                });
            },
        );
    }

    // Benchmark Jupiter fee calculation
    group.bench_function("jupiter_fee", |b| {
        b.iter(|| {
            // Jupiter fee: ~0.3% with minimum
            let amount = 2_000_000_000;
            let fee = amount * 3 / 1000; // 0.3%
            black_box(fee.max(10000)) // 0.001 SOL minimum
        });
    });

    group.finish();
}

fn bench_roi_calculation(c: &mut Criterion) {
    let mut group = c.benchmark_group("roi_calculation");

    let test_cases = vec![
        (1_000_000_000, 0.02), // 1 SOL, 2% ROI
        (2_000_000_000, 0.05), // 2 SOL, 5% ROI
        (5_000_000_000, 0.03), // 5 SOL, 3% ROI
    ];

    for (amount, roi) in test_cases {
        group.bench_with_input(
            BenchmarkId::new("net_profit", amount / 1_000_000_000),
            &(amount, roi),
            |b, &(amount, roi)| {
                b.iter(|| {
                    let gross_profit = (amount as f64 * roi) as u64;
                    let save_fee = amount * 3 / 10000;
                    let jito_tip = 150_000_000; // 0.15 SOL
                    let net_profit = gross_profit - save_fee - jito_tip;
                    black_box(net_profit)
                });
            },
        );
    }

    group.finish();
}

fn bench_memory_allocation(c: &mut Criterion) {
    let mut group = c.benchmark_group("memory_allocation");

    // Benchmark transaction creation memory usage
    group.bench_function("transaction_creation", |b| {
        b.iter(|| {
            let keypair = Keypair::new();
            let instructions = create_mock_save_instructions(
                2_000_000_000,
                &solana_program::pubkey!("SAVe7x8r3PUUyL6pzT6s3nr1T9b4wxxA2pYFnzFvLaV"),
                &keypair
            );

            let tx = Transaction::new_signed_with_payer(
                &instructions,
                Some(&keypair.pubkey()),
                vec![&keypair],
                Pubkey::new_unique(),
            );

            black_box(tx)
        });
    });

    // Benchmark quote processing memory usage
    group.bench_function("quote_processing", |b| {
        let quote = json!({
            "inputMint": "So11111111111111111111111111111111111111112",
            "outputMint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            "inAmount": "2000000000",
            "outAmount": "2100000000",
            "slippageBps": 50,
            "priceImpactPct": "0.15",
            "routePlan": [
                {
                    "swapInfo": {
                        "ammId": "11111111111111111111111111111112",
                        "label": "Orca",
                        "feeAmount": "1000000"
                    }
                }
            ]
        });

        b.iter(|| {
            let amount: u64 = quote["inAmount"].as_str().unwrap().parse().unwrap();
            let out_amount: u64 = quote["outAmount"].as_str().unwrap().parse().unwrap();
            let slippage_bps: u64 = quote["slippageBps"].as_u64().unwrap();
            black_box((amount, out_amount, slippage_bps))
        });
    });

    group.finish();
}

criterion_group!(
    benches,
    bench_save_flash_loan_single,
    bench_save_flash_loan_different_amounts,
    bench_save_flash_loan_concurrent,
    bench_instruction_creation,
    bench_fee_calculation,
    bench_roi_calculation,
    bench_memory_allocation
);

criterion_main!(benches);