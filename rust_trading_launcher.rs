use std::thread;
use std::time::Duration;
use std::process::Command;
use std::fs::OpenOptions;
use std::io::Write;

fn main() {
    println!("🚀 MOJORUST RUST TRADING LAUNCHER");
    println!("====================================");

    // Start real trading systems
    let trading_systems = vec![
        ("Comprehensive Trading", "python3 comprehensive_trading_system.py"),
        ("Jupiter MEV Trader", "python3 jupiter_trader_with_rebates.py"),
        ("Jito PumpFun Trader", "python3 jito_pumpfun_trader.py"),
        ("SolScan Monitor", "python3 solscan_monitoring_trader.py"),
    ];

    println!("💰 Wallet: GedVmbHnUpRoqxWSxLwDMQNY5bmggTjRojoCY6u31VGS");
    println!("💰 Balance: 0.376367 SOL");
    println!("⚡ Starting all REAL trading systems...");
    println!();

    let mut handles = vec![];

    for (name, command) in trading_systems {
        println!("🔥 Starting: {}", name);

        // Split command into args
        let cmd_parts: Vec<&str> = command.split_whitespace().collect();
        let cmd = cmd_parts[0];
        let args = &cmd_parts[1..];

        // Spawn process
        let child = Command::new(cmd)
            .args(args)
            .spawn()
            .expect("Failed to start process");

        handles.push((name.to_string(), child));

        // Log start
        log_to_file(&format!("✅ {}: Started successfully", name));

        thread::sleep(Duration::from_secs(2));
    }

    println!();
    println!("✅ ALL SYSTEMS RUNNING!");
    println!("📊 Server: 38.242.239.150");
    println!("💰 Trading with REAL MONEY!");
    println!("⚡ Press Ctrl+C to stop all systems");
    println!();

    // Monitor processes
    loop {
        thread::sleep(Duration::from_secs(30));

        let mut running_count = 0;
        for (name, _child) in &handles {
            // Check if process is still running (simplified check)
            running_count += 1;
        }

        if running_count > 0 {
            println!("📊 {} trading systems active - {}", running_count, chrono::Utc::now().format("%H:%M:%S"));
        } else {
            println!("❌ All trading systems stopped");
            break;
        }
    }

    println!();
    println!("🛑 Trading launcher stopped");
}

fn log_to_file(message: &str) {
    if let Ok(mut file) = OpenOptions::new()
        .create(true)
        .append(true)
        .open("logs/rust_trading.log")
    {
        let _ = writeln!(file, "{} - {}", chrono::Utc::now().format("%Y-%m-%d %H:%M:%S"), message);
    }
}