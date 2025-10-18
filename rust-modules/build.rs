//! Build script for Mojo Trading Bot Rust modules
//!
//! This script handles compilation settings, version information,
//! and build-time configuration for the Rust security modules.

use std::env;
use std::fs;
use std::path::Path;

fn main() {
    println!("cargo:rerun-if-changed=src/");
    println!("cargo:rerun-if-changed=Cargo.toml");

    // Generate protobuf files for Helius LaserStream
    generate_protobuf_files();

    // Generate simple version info
    let build_time = std::process::Command::new("date")
        .arg("+%Y-%m-%d %H:%M:%S")
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|_| "unknown".to_string());

    println!("cargo:rustc-env=BUILD_TIMESTAMP={}", build_time);

    // Set optimization flags
    if env::var("CARGO_CFG_TARGET_OS").unwrap_or_default() == "linux" {
        println!("cargo:rustc-link-arg=-Wl,--gc-sections");
    }

    // Create output directory
    let out_dir = env::var("OUT_DIR").unwrap();
    let dest_path = Path::new(&out_dir).join("build_info.rs");

    // Generate build information
    let build_info = format!(
        r#"
/// Build timestamp
pub const BUILD_TIMESTAMP: &str = "{}";

/// Target architecture
pub const TARGET_ARCH: &str = "{}";

/// Target OS
pub const TARGET_OS: &str = "{}";

/// Target environment
pub const TARGET_ENV: &str = "{}";

/// Profile (debug/release)
pub const PROFILE: &str = "{}";

/// Optimization level
pub const OPT_LEVEL: &str = "{}";

/// Debug info enabled
pub const DEBUG: bool = {};

/// Rustc version
pub const RUSTC_VERSION: &str = "{}";

/// Cargo version
pub const CARGO_VERSION: &str = "{}";
"#,
        build_time,
        env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_else(|_| "unknown".to_string()),
        env::var("CARGO_CFG_TARGET_OS").unwrap_or_else(|_| "unknown".to_string()),
        env::var("CARGO_CFG_TARGET_ENV").unwrap_or_else(|_| "unknown".to_string()),
        env::var("PROFILE").unwrap_or_else(|_| "unknown".to_string()),
        env::var("OPT_LEVEL").unwrap_or_else(|_| "unknown".to_string()),
        env::var("DEBUG").unwrap_or_else(|_| "false".to_string()) == "true",
        env::var("RUSTC_VERSION").unwrap_or_else(|_| "unknown".to_string()),
        env::var("CARGO_PKG_VERSION").unwrap_or_else(|_| "unknown".to_string()),
    );

    if let Err(e) = fs::write(&dest_path, build_info) {
        eprintln!("Error writing build info: {}", e);
    }

    // Generate linker script for security
    generate_linker_script();

    // Set security-related compile flags
    set_security_flags();
}

fn generate_linker_script() {
    let out_dir = env::var("OUT_DIR").unwrap();
    let linker_script_path = Path::new(&out_dir).join("security.ld");

    let script_content = r#"
/* Security-focused linker script */
SECTIONS
{
    /* Zero-initialized data */
    .bss :
    {
        *(.bss*)
        *(COMMON)
    }

    /* Read-only data */
    .rodata :
    {
        *(.rodata*)
        *(.rodata.str1.*)
        *(.rodata.str4.*)
    }

    /* Executable code */
    .text :
    {
        *(.text*)
        *(.text.*)
    }

    /* Data section */
    .data :
    {
        *(.data*)
        *(.data.*)
    }

    /* Stack protection */
    .stack :
    {
        . = ALIGN(16);
        . = . + 0x100000; /* 1MB stack */
        . = ALIGN(16);
    } > RAM

    /* Heap protection */
    .heap :
    {
        . = ALIGN(16);
        . = . + 0x100000; /* 1MB heap */
        . = ALIGN(16);
    } > RAM
}

/* Security symbols */
PROVIDE(__stack_start = .);
PROVIDE(__heap_start = .);
PROVIDE(__heap_end = ORIGIN(RAM) + LENGTH(RAM));

/* Stack canary */
__stack_chk_guard = 0xdeadbeefdeadbeef;
"#;

    if let Err(e) = fs::write(&linker_script_path, script_content) {
        eprintln!("Error writing linker script: {}", e);
    }
}

fn set_security_flags() {
    // Enable stack protection for release builds only
    if env::var("PROFILE").unwrap_or_default() == "release" {
        println!("cargo:rustc-link-arg=-fstack-protector-strong");
        println!("cargo:rustc-link-arg=-fPIE");
        println!("cargo:rustc-link-arg=-Wl,-z,relro");
        println!("cargo:rustc-link-arg=-Wl,-z,now");
        println!("cargo:rustc-link-arg=-D_FORTIFY_SOURCE=2");
        println!("cargo:rustc-link-arg=-Wformat");
        println!("cargo:rustc-link-arg=-Werror=format-security");
    }
}

fn generate_protobuf_files() {
    let out_dir = env::var("OUT_DIR").unwrap();

    // Create proto directory structure if it doesn't exist
    let proto_dir = Path::new("src").join("proto");
    if !proto_dir.exists() {
        fs::create_dir_all(&proto_dir).unwrap();
    }

    // Create a simple proto file for Helius LaserStream
    let proto_content = r#"
syntax = "proto3";

package helius.laserstream.v1;

// LaserStream service definition
service LaserStreamService {
    // Subscribe to real-time shreds and blockchain data
    rpc SubscribeShreds(SubscribeRequest) returns (stream ShredData);
}

// Request to subscribe to specific accounts or programs
message SubscribeRequest {
    repeated string accounts = 1;
    repeated string program_ids = 2;
    bool include_transactions = 3;
    bool include_account_updates = 4;
    string commitment = 5;
}

// Shred data containing transaction information
message ShredData {
    string signature = 1;
    uint64 slot = 2;
    int64 timestamp = 3;
    string program_id = 4;
    string account = 5;
    uint64 transaction_amount = 6;
    uint64 block_height = 7;
    bool is_confirmed = 8;
    repeated string instructions = 9;
    map<string, string> metadata = 10;
}

// Block notification containing multiple shreds
message BlockNotification {
    uint64 slot = 1;
    uint64 block_height = 2;
    int64 timestamp = 3;
    repeated ShredData shreds = 4;
    string block_hash = 5;
    repeated string validator_votes = 6;
}

// Account update notification
message AccountUpdate {
    string account = 1;
    uint64 slot = 2;
    int64 timestamp = 3;
    uint64 lamports = 4;
    bytes data = 5;
    string owner = 6;
    bool executable = 7;
    uint64 rent_epoch = 8;
}

// Transaction information
message TransactionInfo {
    string signature = 1;
    repeated string account_keys = 2;
    repeated string instructions = 3;
    uint64 compute_units_consumed = 4;
    uint64 fee = 5;
    string status = 6;
    int64 block_time = 7;
}
"#;

    let proto_file = proto_dir.join("laserstream.proto");
    if let Err(e) = fs::write(&proto_file, proto_content) {
        eprintln!("Error writing proto file: {}", e);
    }

    // Note: In a real implementation, you would use prost_build to compile .proto files
    // For now, we'll create the Rust structs manually in the helius_laserstream module
    println!("cargo:rerun-if-changed=src/proto/laserstream.proto");
}