//! Build script for Mojo Trading Bot Rust modules
//!
//! This script handles compilation settings, version information,
//! and build-time configuration for the Rust security modules.

use vergen::{vergen, Config, ShaKind};
use std::env;
use std::fs;
use std::path::Path;

fn main() {
    println!("cargo:rerun-if-changed=src/");
    println!("cargo:rerun-if-changed=Cargo.toml");

    // Generate version information
    let mut config = Config::default();
    *config.git_mut().sha_kind_mut() = ShaKind::Short;
    *config.git_mut().branch_mut() = true;
    *config.build_mut().timestamp_mut() = true;

    if let Err(e) = vergen(config) {
        eprintln!("Error generating version info: {}", e);
    }

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
        env::var("VERGEN_BUILD_TIMESTAMP").unwrap_or_else(|_| "unknown".to_string()),
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
    // Enable stack protection
    println!("cargo:rustc-cdylib-link-arg=-fstack-protector-strong");

    // Enable position-independent code
    println!("cargo:rustc-cdylib-link-arg=-fPIE");

    // Enable relro (read-only relocations)
    println!("cargo:rustc-cdylib-link-arg=-Wl,-z,relro");
    println!("cargo:rustc-cdylib-link-arg=-Wl,-z,now");

    // Enable fortify source
    if env::var("PROFILE").unwrap_or_default() == "release" {
        println!("cargo:rustc-cdylib-link-arg=-D_FORTIFY_SOURCE=2");
    }

    // Enable format string protection
    println!("cargo:rustc-cdylib-link-arg=-Wformat");
    println!("cargo:rustc-cdylib-link-arg=-Werror=format-security");

    // Enable buffer overflow protection
    println!("cargo:rustc-cdylib-link-arg=-D_FORTIFY_SOURCE=2");
}