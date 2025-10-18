//! Foreign Function Interface (FFI) for Mojo integration
//!
//! This module provides FFI bindings to allow the Mojo trading bot
//! to securely interact with Rust security and cryptographic modules.

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::ptr;
use std::slice;
use std::sync::{Mutex, OnceLock};
use std::sync::Arc;
use uuid;

// Re-export main interfaces for FFI
pub use crate::crypto::CryptoEngine;
pub use crate::security::SecurityEngine;
pub use crate::solana::SolanaEngine;
pub use crate::portfolio::{PortfolioManager, StrategyType, Position, RiskLevel, PortfolioMetrics};

// Import for Result handling
use anyhow::Result;

/// FFI result type
#[repr(C)]
pub enum FfiResult {
    Success = 0,
    InvalidInput = -1,
    InternalError = -2,
    MemoryError = -3,
    NetworkError = -4,
    CryptoError = -5,
    SecurityError = -6,
    SolanaError = -7,
}

impl<T> From<Result<T>> for FfiResult {
    fn from(r: Result<T>) -> Self {
        match r {
            Ok(_) => FfiResult::Success,
            Err(_) => FfiResult::InternalError,
        }
    }
}

/// FFI-safe wrapper for byte arrays
#[repr(C)]
pub struct FfiBytes {
    pub data: *mut u8,
    pub len: usize,
    pub capacity: usize,
}

impl FfiBytes {
    /// Create from Rust Vec<u8>
    fn from_vec(vec: Vec<u8>) -> Self {
        let mut vec = std::mem::ManuallyDrop::new(vec);
        Self {
            data: vec.as_mut_ptr(),
            len: vec.len(),
            capacity: vec.capacity(),
        }
    }

    /// Convert to Rust Vec<u8>
    unsafe fn into_vec(self) -> Vec<u8> {
        Vec::from_raw_parts(self.data, self.len, self.capacity)
    }

    /// Create empty FfiBytes
    fn empty() -> Self {
        Self {
            data: ptr::null_mut(),
            len: 0,
            capacity: 0,
        }
    }
}

/// FFI-safe wrapper for strings
#[repr(C)]
pub struct FfiString {
    pub data: *mut c_char,
    pub len: usize,
}

impl FfiString {
    /// Create from Rust String using CString for proper memory management
    fn from_string(string: String) -> Self {
        let c_string = CString::new(string).unwrap();
        let len = c_string.as_bytes().len();
        Self {
            data: c_string.into_raw(),
            len,
        }
    }

    /// Convert to Rust String
    unsafe fn into_string(self) -> String {
        let slice = std::slice::from_raw_parts(self.data as *const u8, self.len);
        String::from_utf8_lossy(slice).into_owned()
    }

    /// Create empty FfiString
    fn empty() -> Self {
        Self {
            data: ptr::null_mut(),
            len: 0,
        }
    }
}

// =============================================================================
// Crypto Engine FFI
// =============================================================================

/// Create new crypto engine
#[no_mangle]
pub extern "C" fn crypto_engine_new() -> *mut CryptoEngine {
    match CryptoEngine::new() {
        Ok(engine) => Box::into_raw(Box::new(engine)),
        Err(_) => ptr::null_mut(),
    }
}

/// Destroy crypto engine
#[no_mangle]
pub extern "C" fn crypto_engine_destroy(engine: *mut CryptoEngine) {
    if !engine.is_null() {
        unsafe {
            let _ = Box::from_raw(engine);
        }
    }
}

/// Generate new keypair
#[no_mangle]
pub extern "C" fn crypto_engine_generate_keypair(
    engine: *mut CryptoEngine,
    out_bytes: *mut FfiBytes,
) -> FfiResult {
    if engine.is_null() || out_bytes.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let engine = &mut *engine;
        match engine.generate_keypair() {
            Ok(keypair) => {
                let bytes = keypair.to_bytes();
                *out_bytes = FfiBytes::from_vec(bytes);
                FfiResult::Success
            }
            Err(_) => FfiResult::CryptoError,
        }
    }
}

/// Sign message
#[no_mangle]
pub extern "C" fn crypto_engine_sign_message(
    engine: *mut CryptoEngine,
    message: *const u8,
    message_len: usize,
    out_signature: *mut FfiBytes,
) -> FfiResult {
    if engine.is_null() || message.is_null() || out_signature.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let engine = &*engine;
        let message_slice = slice::from_raw_parts(message, message_len);

        match engine.sign_message(message_slice) {
            Ok(signature) => {
                *out_signature = FfiBytes::from_vec(signature);
                FfiResult::Success
            }
            Err(_) => FfiResult::CryptoError,
        }
    }
}

/// Verify signature
#[no_mangle]
pub extern "C" fn crypto_engine_verify_signature(
    engine: *mut CryptoEngine,
    message: *const u8,
    message_len: usize,
    signature: *const u8,
    signature_len: usize,
    public_key: *const u8,
    public_key_len: usize,
) -> FfiResult {
    if engine.is_null() || message.is_null() || signature.is_null() || public_key.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let engine = &*engine;
        let message_slice = slice::from_raw_parts(message, message_len);
        let signature_slice = slice::from_raw_parts(signature, signature_len);
        let public_key_slice = slice::from_raw_parts(public_key, public_key_len);

        match engine.verify_signature(message_slice, signature_slice, public_key_slice) {
            Ok(true) => FfiResult::Success,
            Ok(false) => FfiResult::InvalidInput,
            Err(_) => FfiResult::CryptoError,
        }
    }
}

/// Encrypt data
#[no_mangle]
pub extern "C" fn crypto_engine_encrypt_data(
    engine: *mut CryptoEngine,
    data: *const u8,
    data_len: usize,
    key: *const u8,
    key_len: usize,
    out_encrypted: *mut FfiBytes,
) -> FfiResult {
    if engine.is_null() || data.is_null() || key.is_null() || out_encrypted.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let engine = &*engine;
        let data_slice = slice::from_raw_parts(data, data_len);
        let key_slice = slice::from_raw_parts(key, key_len);

        match engine.encrypt_data(data_slice, key_slice) {
            Ok(encrypted) => {
                *out_encrypted = FfiBytes::from_vec(encrypted);
                FfiResult::Success
            }
            Err(_) => FfiResult::CryptoError,
        }
    }
}

/// Decrypt data
#[no_mangle]
pub extern "C" fn crypto_engine_decrypt_data(
    engine: *mut CryptoEngine,
    encrypted_data: *const u8,
    encrypted_len: usize,
    key: *const u8,
    key_len: usize,
    out_decrypted: *mut FfiBytes,
) -> FfiResult {
    if engine.is_null() || encrypted_data.is_null() || key.is_null() || out_decrypted.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let engine = &*engine;
        let encrypted_slice = slice::from_raw_parts(encrypted_data, encrypted_len);
        let key_slice = slice::from_raw_parts(key, key_len);

        match engine.decrypt_data(encrypted_slice, key_slice) {
            Ok(decrypted) => {
                *out_decrypted = FfiBytes::from_vec(decrypted);
                FfiResult::Success
            }
            Err(_) => FfiResult::CryptoError,
        }
    }
}

// =============================================================================
// Security Engine FFI
// =============================================================================

/// Create new security engine
#[no_mangle]
pub extern "C" fn security_engine_new() -> *mut SecurityEngine {
    match SecurityEngine::new() {
        Ok(engine) => Box::into_raw(Box::new(engine)),
        Err(_) => ptr::null_mut(),
    }
}

/// Destroy security engine
#[no_mangle]
pub extern "C" fn security_engine_destroy(engine: *mut SecurityEngine) {
    if !engine.is_null() {
        unsafe {
            let _ = Box::from_raw(engine);
        }
    }
}

/// Initialize security engine
#[no_mangle]
pub extern "C" fn security_engine_initialize(engine: *mut SecurityEngine) -> FfiResult {
    if engine.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let engine = &mut *engine;
        FfiResult::from(engine.initialize())
    }
}

/// Check request security
#[no_mangle]
pub extern "C" fn security_engine_check_request(
    engine: *mut SecurityEngine,
    client_id: *const c_char,
    endpoint: *const c_char,
    data: *const u8,
    data_len: usize,
) -> FfiResult {
    if engine.is_null() || client_id.is_null() || endpoint.is_null() || data.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let engine = &*engine;
        let client_id_str = CStr::from_ptr(client_id).to_string_lossy();
        let endpoint_str = CStr::from_ptr(endpoint).to_string_lossy();
        let data_slice = slice::from_raw_parts(data, data_len);

        match engine.check_request(&client_id_str, &endpoint_str, data_slice) {
            Ok(crate::security::SecurityCheckResult::Allowed) => FfiResult::Success,
            Ok(crate::security::SecurityCheckResult::RateLimited) => FfiResult::SecurityError,
            Ok(crate::security::SecurityCheckResult::AccessDenied) => FfiResult::SecurityError,
            Ok(crate::security::SecurityCheckResult::InvalidInput) => FfiResult::InvalidInput,
            Ok(crate::security::SecurityCheckResult::ThreatDetected) => FfiResult::SecurityError,
            Err(_) => FfiResult::InternalError,
        }
    }
}

// =============================================================================
// Solana Engine FFI
// =============================================================================

/// Create new Solana engine
#[no_mangle]
pub extern "C" fn solana_engine_new(
    rpc_url: *const c_char,
    ws_url: *const c_char,
) -> *mut SolanaEngine {
    if rpc_url.is_null() {
        return ptr::null_mut();
    }

    unsafe {
        let rpc_url_str = CStr::from_ptr(rpc_url).to_string_lossy();
        let ws_url_str = if ws_url.is_null() {
            None
        } else {
            Some(CStr::from_ptr(ws_url).to_string_lossy().into_owned())
        };

        match SolanaEngine::new(&rpc_url_str, ws_url_str.as_deref()) {
            Ok(engine) => Box::into_raw(Box::new(engine)),
            Err(_) => ptr::null_mut(),
        }
    }
}

/// Destroy Solana engine
#[no_mangle]
pub extern "C" fn solana_engine_destroy(engine: *mut SolanaEngine) {
    if !engine.is_null() {
        unsafe {
            let _ = Box::from_raw(engine);
        }
    }
}

/// Get SOL balance
#[no_mangle]
pub extern "C" fn solana_engine_get_balance(
    engine: *mut SolanaEngine,
    pubkey: *const c_char,
    out_balance: *mut u64,
) -> FfiResult {
    if engine.is_null() || pubkey.is_null() || out_balance.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let engine = &*engine;
        let pubkey_str = CStr::from_ptr(pubkey).to_string_lossy();

        match engine.get_sol_balance(&pubkey_str) {
            Ok(balance) => {
                *out_balance = balance;
                FfiResult::Success
            }
            Err(_) => FfiResult::SolanaError,
        }
    }
}

/// Create transfer transaction
#[no_mangle]
pub extern "C" fn solana_engine_create_transfer_transaction(
    engine: *mut SolanaEngine,
    from_pubkey: *const c_char,
    to_pubkey: *const c_char,
    lamports: u64,
    fee_payer: *const c_char,
    out_transaction: *mut FfiBytes,
) -> FfiResult {
    if engine.is_null() || from_pubkey.is_null() || to_pubkey.is_null() || out_transaction.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let engine = &*engine;
        let from_str = CStr::from_ptr(from_pubkey).to_string_lossy();
        let to_str = CStr::from_ptr(to_pubkey).to_string_lossy();
        let fee_payer_str = if fee_payer.is_null() {
            None
        } else {
            Some(CStr::from_ptr(fee_payer).to_string_lossy().into_owned())
        };

        match engine.build_transfer_transaction(&from_str, &to_str, lamports, fee_payer_str.as_deref()) {
            Ok(transaction) => {
                let serialized = bincode::serialize(&transaction).unwrap_or_default();
                *out_transaction = FfiBytes::from_vec(serialized);
                FfiResult::Success
            }
            Err(_) => FfiResult::SolanaError,
        }
    }
}

// =============================================================================
// Utility Functions FFI
// =============================================================================

/// Free FfiBytes memory
#[no_mangle]
pub extern "C" fn ffi_bytes_free(bytes: FfiBytes) {
    if !bytes.data.is_null() {
        unsafe {
            let _ = Vec::from_raw_parts(bytes.data, bytes.len, bytes.capacity);
        }
    }
}

/// Free FfiString memory
#[no_mangle]
pub extern "C" fn ffi_string_free(string: FfiString) {
    if !string.data.is_null() {
        unsafe {
            let _ = CString::from_raw(string.data);
        }
    }
}

/// Get last error message (thread-local storage)
thread_local! {
    static LAST_ERROR: std::cell::RefCell<Option<CString>> = std::cell::RefCell::new(None);
}

/// Set last error message
#[no_mangle]
pub extern "C" fn ffi_set_last_error(message: *const c_char) {
    if !message.is_null() {
        unsafe {
            let cstr = CStr::from_ptr(message).to_owned();
            LAST_ERROR.with(|last_error| {
                *last_error.borrow_mut() = Some(cstr);
            });
        }
    }
}

/// Get last error message
#[no_mangle]
pub extern "C" fn ffi_get_last_error() -> *const c_char {
    LAST_ERROR.with(|last_error| {
        match *last_error.borrow() {
            Some(ref cstr) => cstr.as_ptr(),
            None => ptr::null(),
        }
    })
}

/// Clear last error message
#[no_mangle]
pub extern "C" fn ffi_clear_last_error() {
    LAST_ERROR.with(|last_error| {
        *last_error.borrow_mut() = None;
    });
}

/// Initialize FFI module
#[no_mangle]
pub extern "C" fn ffi_initialize() -> FfiResult {
    // Initialize logging (safe to call multiple times)
    let _ = env_logger::try_init();

    // Set up panic handler
    std::panic::set_hook(Box::new(|panic_info| {
        let message = format!("Panic: {}", panic_info);
        if let Ok(cstring) = CString::new(message) {
            unsafe {
                ffi_set_last_error(cstring.as_ptr());
            }
        }
    }));

    FfiResult::Success
}

/// Cleanup FFI module
#[no_mangle]
pub extern "C" fn ffi_cleanup() {
    ffi_clear_last_error();
}

// =============================================================================
// Infisical Secrets Manager FFI
// =============================================================================

use tokio::runtime::Runtime;

use crate::infisical_manager::{SecretsManager, ApiConfig, TradingConfig, WalletConfig};

/// Global secrets manager instance (thread-safe)
static SECRETS_MANAGER: OnceLock<Arc<Mutex<Option<SecretsManager>>>> = OnceLock::new();
static RUNTIME: OnceLock<Arc<Mutex<Option<Runtime>>>> = OnceLock::new();

/// Initialize the secrets manager
#[no_mangle]
pub extern "C" fn secrets_manager_init() -> FfiResult {
    // Check if already initialized
    let secrets_manager = SECRETS_MANAGER.get_or_init(|| {
        Arc::new(Mutex::new(None))
    });

    {
        let mut sm = secrets_manager.lock().unwrap();
        if sm.is_some() {
            return FfiResult::Success; // Already initialized
        }
    }

    // Initialize runtime if needed
    let runtime = RUNTIME.get_or_init(|| {
        Arc::new(Mutex::new(None))
    });

    let rt = {
        let mut rt_guard = runtime.lock().unwrap();
        if rt_guard.is_none() {
            match Runtime::new() {
                Ok(rt) => {
                    *rt_guard = Some(rt);
                    rt_guard.as_ref().unwrap()
                }
                Err(e) => {
                    let msg = format!("Failed to create runtime: {}", e);
                    if let Ok(cstring) = CString::new(msg) {
                        ffi_set_last_error(cstring.as_ptr());
                    }
                    return FfiResult::InternalError;
                }
            }
        } else {
            rt_guard.as_ref().unwrap().clone()
        }
    };

    // Initialize secrets manager
    let manager = match rt.block_on(SecretsManager::new()) {
        Ok(manager) => manager,
        Err(e) => {
            let msg = format!("Failed to initialize secrets manager: {}", e);
            if let Ok(cstring) = CString::new(msg) {
                ffi_set_last_error(cstring.as_ptr());
            }
            return FfiResult::InternalError;
        }
    };

    {
        let mut sm = secrets_manager.lock().unwrap();
        *sm = Some(manager);
    }

    FfiResult::Success
}

/// Destroy the secrets manager
#[no_mangle]
pub extern "C" fn secrets_manager_destroy() {
    // Note: We don't actually destroy the OnceLock instances
    // This is a limitation of the OnceLock design for FFI use cases
    // In practice, the secrets manager will be cleaned up when the process exits
    // For proper cleanup, the application should ensure single-threaded usage
}

/// Get a secret value
#[no_mangle]
pub extern "C" fn secrets_manager_get_secret(
    key: *const c_char,
    out_string: *mut FfiString,
) -> FfiResult {
    if key.is_null() || out_string.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let manager = match SECRETS_MANAGER.as_ref() {
            Some(manager) => manager,
            None => {
                if let Ok(cstring) = CString::new("Secrets manager not initialized") {
                    ffi_set_last_error(cstring.as_ptr());
                }
                return FfiResult::InternalError;
            }
        };

        let key_str = match CStr::from_ptr(key).to_str() {
            Ok(s) => s,
            Err(_) => return FfiResult::InvalidInput,
        };

        let runtime = match RUNTIME.as_ref() {
            Some(rt) => rt,
            None => return FfiResult::InternalError,
        };

        match runtime.block_on(manager.get_secret(key_str)) {
            Ok(value) => {
                *out_string = FfiString::from_string(value);
                FfiResult::Success
            }
            Err(e) => {
                let msg = format!("Failed to get secret '{}': {}", key_str, e);
                if let Ok(cstring) = CString::new(msg) {
                    ffi_set_last_error(cstring.as_ptr());
                }
                FfiResult::InternalError
            }
        }
    }
}

/// Get API configuration
#[no_mangle]
pub extern "C" fn secrets_manager_get_api_config(
    out_bytes: *mut FfiBytes,
) -> FfiResult {
    if out_bytes.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let manager = match SECRETS_MANAGER.as_ref() {
            Some(manager) => manager,
            None => {
                if let Ok(cstring) = CString::new("Secrets manager not initialized") {
                    ffi_set_last_error(cstring.as_ptr());
                }
                return FfiResult::InternalError;
            }
        };

        let runtime = match RUNTIME.as_ref() {
            Some(rt) => rt,
            None => return FfiResult::InternalError,
        };

        match runtime.block_on(manager.get_api_config()) {
            Ok(config) => {
                // Serialize config to JSON
                let json = match serde_json::to_string(&config) {
                    Ok(json) => json,
                    Err(e) => {
                        let msg = format!("Failed to serialize config: {}", e);
                        if let Ok(cstring) = CString::new(msg) {
                            ffi_set_last_error(cstring.as_ptr());
                        }
                        return FfiResult::InternalError;
                    }
                };

                *out_bytes = FfiBytes::from_vec(json.into_bytes());
                FfiResult::Success
            }
            Err(e) => {
                let msg = format!("Failed to get API config: {}", e);
                if let Ok(cstring) = CString::new(msg) {
                    ffi_set_last_error(cstring.as_ptr());
                }
                FfiResult::InternalError
            }
        }
    }
}

/// Get trading configuration
#[no_mangle]
pub extern "C" fn secrets_manager_get_trading_config(
    out_bytes: *mut FfiBytes,
) -> FfiResult {
    if out_bytes.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let manager = match SECRETS_MANAGER.as_ref() {
            Some(manager) => manager,
            None => {
                if let Ok(cstring) = CString::new("Secrets manager not initialized") {
                    ffi_set_last_error(cstring.as_ptr());
                }
                return FfiResult::InternalError;
            }
        };

        let runtime = match RUNTIME.as_ref() {
            Some(rt) => rt,
            None => return FfiResult::InternalError,
        };

        match runtime.block_on(manager.get_trading_config()) {
            Ok(config) => {
                // Serialize config to JSON
                let json = match serde_json::to_string(&config) {
                    Ok(json) => json,
                    Err(e) => {
                        let msg = format!("Failed to serialize config: {}", e);
                        if let Ok(cstring) = CString::new(msg) {
                            ffi_set_last_error(cstring.as_ptr());
                        }
                        return FfiResult::InternalError;
                    }
                };

                *out_bytes = FfiBytes::from_vec(json.into_bytes());
                FfiResult::Success
            }
            Err(e) => {
                let msg = format!("Failed to get trading config: {}", e);
                if let Ok(cstring) = CString::new(msg) {
                    ffi_set_last_error(cstring.as_ptr());
                }
                FfiResult::InternalError
            }
        }
    }
}

/// Get wallet configuration
#[no_mangle]
pub extern "C" fn secrets_manager_get_wallet_config(
    out_bytes: *mut FfiBytes,
) -> FfiResult {
    if out_bytes.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let manager = match SECRETS_MANAGER.as_ref() {
            Some(manager) => manager,
            None => {
                if let Ok(cstring) = CString::new("Secrets manager not initialized") {
                    ffi_set_last_error(cstring.as_ptr());
                }
                return FfiResult::InternalError;
            }
        };

        let runtime = match RUNTIME.as_ref() {
            Some(rt) => rt,
            None => return FfiResult::InternalError,
        };

        match runtime.block_on(manager.get_wallet_config()) {
            Ok(config) => {
                // Serialize config to JSON
                let json = match serde_json::to_string(&config) {
                    Ok(json) => json,
                    Err(e) => {
                        let msg = format!("Failed to serialize config: {}", e);
                        if let Ok(cstring) = CString::new(msg) {
                            ffi_set_last_error(cstring.as_ptr());
                        }
                        return FfiResult::InternalError;
                    }
                };

                *out_bytes = FfiBytes::from_vec(json.into_bytes());
                FfiResult::Success
            }
            Err(e) => {
                let msg = format!("Failed to get wallet config: {}", e);
                if let Ok(cstring) = CString::new(msg) {
                    ffi_set_last_error(cstring.as_ptr());
                }
                FfiResult::InternalError
            }
        }
    }
}

/// Check if secrets manager is initialized
#[no_mangle]
pub extern "C" fn secrets_manager_is_initialized() -> c_int {
    unsafe {
        if SECRETS_MANAGER.is_some() {
            1
        } else {
            0
        }
    }
}

// =============================================================================
// Portfolio Manager FFI
// =============================================================================

/// Global portfolio manager instance (thread-safe)
static PORTFOLIO_MANAGER: OnceLock<Arc<Mutex<Option<PortfolioManager>>>> = OnceLock::new();

/// Create new portfolio manager
#[no_mangle]
pub extern "C" fn portfolio_manager_new(total_capital: f64) -> *mut PortfolioManager {
    let manager = match PortfolioManager::new(total_capital) {
        Ok(manager) => manager,
        Err(_) => return ptr::null_mut(),
    };

    Box::into_raw(Box::new(manager))
}

/// Destroy portfolio manager
#[no_mangle]
pub extern "C" fn portfolio_manager_destroy(manager: *mut PortfolioManager) {
    if !manager.is_null() {
        unsafe {
            let _ = Box::from_raw(manager);
        }
    }
}

/// Initialize global portfolio manager
#[no_mangle]
pub extern "C" fn portfolio_manager_init_global(total_capital: f64) -> FfiResult {
    let portfolio_manager = PORTFOLIO_MANAGER.get_or_init(|| {
        Arc::new(Mutex::new(None))
    });

    let mut pm = portfolio_manager.lock().unwrap();
    if pm.is_some() {
        return FfiResult::Success; // Already initialized
    }

    match PortfolioManager::new(total_capital) {
        Ok(manager) => {
            *pm = Some(manager);
            FfiResult::Success
        }
        Err(e) => {
            let msg = format!("Failed to initialize portfolio manager: {}", e);
            if let Ok(cstring) = CString::new(msg) {
                unsafe {
                    ffi_set_last_error(cstring.as_ptr());
                }
            }
            FfiResult::InternalError
        }
    }
}

/// Open a new position
#[no_mangle]
pub extern "C" fn portfolio_manager_open_position(
    manager: *mut PortfolioManager,
    strategy: i32, // StrategyType as i32
    token_mint: *const c_char,
    symbol: *const c_char,
    side: i32, // OrderSide as i32
    size: f64,
    entry_price: f64,
    risk_level: i32, // RiskLevel as i32
    out_position_id: *mut [u8; 16], // UUID as byte array
) -> FfiResult {
    if manager.is_null() || token_mint.is_null() || symbol.is_null() || out_position_id.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let manager = &*manager;
        let token_mint_str = CStr::from_ptr(token_mint).to_string_lossy();
        let symbol_str = CStr::from_ptr(symbol).to_string_lossy();

        let strategy_type = match strategy {
            0 => StrategyType::Sniper,
            1 => StrategyType::Arbitrage,
            2 => StrategyType::FlashLoan,
            3 => StrategyType::MarketMaking,
            _ => return FfiResult::InvalidInput,
        };

        let order_side = match side {
            0 => crate::portfolio::OrderSide::Buy,
            1 => crate::portfolio::OrderSide::Sell,
            _ => return FfiResult::InvalidInput,
        };

        let risk = match risk_level {
            1 => RiskLevel::Low,
            2 => RiskLevel::Medium,
            3 => RiskLevel::High,
            4 => RiskLevel::Critical,
            _ => return FfiResult::InvalidInput,
        };

        match manager.open_position(
            strategy_type,
            token_mint_str.to_string(),
            symbol_str.to_string(),
            order_side,
            size,
            entry_price,
            risk,
        ) {
            Ok(position_id) => {
                *out_position_id = position_id.as_bytes().clone();
                FfiResult::Success
            }
            Err(e) => {
                let msg = format!("Failed to open position: {}", e);
                if let Ok(cstring) = CString::new(msg) {
                    ffi_set_last_error(cstring.as_ptr());
                }
                FfiResult::InternalError
            }
        }
    }
}

/// Close a position
#[no_mangle]
pub extern "C" fn portfolio_manager_close_position(
    manager: *mut PortfolioManager,
    position_id: *const [u8; 16],
    close_price: f64,
    fees: f64,
    out_pnl: *mut f64,
) -> FfiResult {
    if manager.is_null() || position_id.is_null() || out_pnl.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let manager = &*manager;
        let uuid = uuid::Uuid::from_bytes(*position_id);

        match manager.close_position(uuid, close_price, fees) {
            Ok(pnl) => {
                *out_pnl = pnl;
                FfiResult::Success
            }
            Err(e) => {
                let msg = format!("Failed to close position: {}", e);
                if let Ok(cstring) = CString::new(msg) {
                    ffi_set_last_error(cstring.as_ptr());
                }
                FfiResult::InternalError
            }
        }
    }
}

/// Update position price
#[no_mangle]
pub extern "C" fn portfolio_manager_update_position_price(
    manager: *mut PortfolioManager,
    position_id: *const [u8; 16],
    new_price: f64,
) -> FfiResult {
    if manager.is_null() || position_id.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let manager = &*manager;
        let uuid = uuid::Uuid::from_bytes(*position_id);

        match manager.update_position_price(uuid, new_price) {
            Ok(()) => FfiResult::Success,
            Err(e) => {
                let msg = format!("Failed to update position price: {}", e);
                if let Ok(cstring) = CString::new(msg) {
                    ffi_set_last_error(cstring.as_ptr());
                }
                FfiResult::InternalError
            }
        }
    }
}

/// Get portfolio metrics
#[no_mangle]
pub extern "C" fn portfolio_manager_get_metrics(
    manager: *mut PortfolioManager,
    out_bytes: *mut FfiBytes,
) -> FfiResult {
    if manager.is_null() || out_bytes.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let manager = &*manager;
        let metrics = manager.get_metrics();

        // Serialize metrics to JSON
        let json = match serde_json::to_string(&metrics) {
            Ok(json) => json,
            Err(e) => {
                let msg = format!("Failed to serialize metrics: {}", e);
                if let Ok(cstring) = CString::new(msg) {
                    ffi_set_last_error(cstring.as_ptr());
                }
                return FfiResult::InternalError;
            }
        };

        *out_bytes = FfiBytes::from_vec(json.into_bytes());
        FfiResult::Success
    }
}

/// Get available capital for strategy
#[no_mangle]
pub extern "C" fn portfolio_manager_get_available_capital(
    manager: *mut PortfolioManager,
    strategy: i32,
    out_capital: *mut f64,
) -> FfiResult {
    if manager.is_null() || out_capital.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let manager = &*manager;
        let strategy_type = match strategy {
            0 => StrategyType::Sniper,
            1 => StrategyType::Arbitrage,
            2 => StrategyType::FlashLoan,
            3 => StrategyType::MarketMaking,
            _ => return FfiResult::InvalidInput,
        };

        *out_capital = manager.get_available_capital(strategy_type);
        FfiResult::Success
    }
}

/// Check if can take new position
#[no_mangle]
pub extern "C" fn portfolio_manager_can_take_position(
    manager: *mut PortfolioManager,
    strategy: i32,
    amount: f64,
    risk_level: i32,
    out_can_take: *mut bool,
) -> FfiResult {
    if manager.is_null() || out_can_take.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let manager = &*manager;
        let strategy_type = match strategy {
            0 => StrategyType::Sniper,
            1 => StrategyType::Arbitrage,
            2 => StrategyType::FlashLoan,
            3 => StrategyType::MarketMaking,
            _ => return FfiResult::InvalidInput,
        };

        let risk = match risk_level {
            1 => RiskLevel::Low,
            2 => RiskLevel::Medium,
            3 => RiskLevel::High,
            4 => RiskLevel::Critical,
            _ => return FfiResult::InvalidInput,
        };

        *out_can_take = manager.can_take_position(strategy_type, amount, risk);
        FfiResult::Success
    }
}

/// Update token price
#[no_mangle]
pub extern "C" fn portfolio_manager_update_token_price(
    manager: *mut PortfolioManager,
    token_mint: *const c_char,
    symbol: *const c_char,
    price: f64,
    decimals: u8,
) -> FfiResult {
    if manager.is_null() || token_mint.is_null() || symbol.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let manager = &*manager;
        let token_mint_str = CStr::from_ptr(token_mint).to_string_lossy();
        let symbol_str = CStr::from_ptr(symbol).to_string_lossy();

        manager.update_token_price(
            token_mint_str.to_string(),
            symbol_str.to_string(),
            price,
            decimals,
        );
        FfiResult::Success
    }
}

/// Set emergency stop
#[no_mangle]
pub extern "C" fn portfolio_manager_set_emergency_stop(
    manager: *mut PortfolioManager,
    stop: bool,
) -> FfiResult {
    if manager.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let manager = &*manager;
        manager.set_emergency_stop(stop);
        FfiResult::Success
    }
}

/// Get open positions count
#[no_mangle]
pub extern "C" fn portfolio_manager_get_open_positions_count(
    manager: *mut PortfolioManager,
    out_count: *mut usize,
) -> FfiResult {
    if manager.is_null() || out_count.is_null() {
        return FfiResult::InvalidInput;
    }

    unsafe {
        let manager = &*manager;
        let positions = manager.get_open_positions();
        *out_count = positions.len();
        FfiResult::Success
    }
}

// ========================================================================
// STATISTICAL ARBITRAGE FFI FUNCTIONS
// ========================================================================

/// Test cointegration between two price series using Engle-Granger method
///
/// # Arguments
/// * `prices_a` - Pointer to price array for token A
/// * `prices_b` - Pointer to price array for token B
/// * `len` - Length of price arrays (must be equal)
/// * `out_hedge_ratio` - Pointer to store hedge ratio output
/// * `out_p_value` - Pointer to store p-value output
///
/// # Returns
/// * `FfiResult::Success` on success
/// * `FfiResult::Error(message)` on failure
///
/// # Safety
/// All pointers must be valid and point to allocated memory.
/// Arrays must have equal length and contain at least 20 elements.
#[no_mangle]
pub extern "C" fn stat_arb_test_cointegration(
    prices_a: *const f64,
    prices_b: *const f64,
    len: usize,
    out_hedge_ratio: *mut f64,
    out_p_value: *mut f64,
) -> FfiResult {
    unsafe {
        // Validate inputs
        if prices_a.is_null() || prices_b.is_null() || out_hedge_ratio.is_null() || out_p_value.is_null() {
            return FfiResult::Error("Null pointer passed to stat_arb_test_cointegration".into());
        }

        if len < 20 {
            return FfiResult::Error("Insufficient data points for cointegration test".into());
        }

        // Create slices from raw pointers
        let slice_a = std::slice::from_raw_parts(prices_a, len);
        let slice_b = std::slice::from_raw_parts(prices_b, len);

        // Import statistical module and test cointegration
        match crate::arbitrage::statistical::test_cointegration(slice_a, slice_b) {
            Ok((hedge_ratio, p_value)) => {
                *out_hedge_ratio = hedge_ratio;
                *out_p_value = p_value;
                FfiResult::Success
            }
            Err(e) => FfiResult::Error(format!("Cointegration test failed: {}", e).into()),
        }
    }
}

/// Calculate spread between two price series with hedge ratio
///
/// # Arguments
/// * `prices_a` - Pointer to price array for token A
/// * `prices_b` - Pointer to price array for token B
/// * `hedge_ratio` - Hedge ratio for spread calculation
/// * `len` - Length of price arrays
/// * `out_spread` - Pointer to store spread output array
///
/// # Returns
/// * `FfiResult::Success` on success
/// * `FfiResult::Error(message)` on failure
///
/// # Safety
/// All pointers must be valid and point to allocated memory.
/// `out_spread` must have capacity for at least `len` elements.
#[no_mangle]
pub extern "C" fn stat_arb_calculate_spread(
    prices_a: *const f64,
    prices_b: *const f64,
    hedge_ratio: f64,
    len: usize,
    out_spread: *mut f64,
) -> FfiResult {
    unsafe {
        // Validate inputs
        if prices_a.is_null() || prices_b.is_null() || out_spread.is_null() {
            return FfiResult::Error("Null pointer passed to stat_arb_calculate_spread".into());
        }

        if len == 0 {
            return FfiResult::Error("Empty arrays passed to stat_arb_calculate_spread".into());
        }

        // Create slices from raw pointers
        let slice_a = std::slice::from_raw_parts(prices_a, len);
        let slice_b = std::slice::from_raw_parts(prices_b, len);
        let out_slice = std::slice::from_raw_parts_mut(out_spread, len);

        // Calculate spread: spread = price_a - hedge_ratio * price_b
        for i in 0..len {
            out_slice[i] = slice_a[i] - hedge_ratio * slice_b[i];
        }

        FfiResult::Success
    }
}

/// Calculate z-scores for spread series using SIMD optimization
///
/// # Arguments
/// * `spread` - Pointer to spread array
/// * `len` - Length of spread array
/// * `mean` - Mean of the spread series
/// * `std_dev` - Standard deviation of the spread series
/// * `out_z_scores` - Pointer to store z-scores output array
///
/// # Returns
/// * `FfiResult::Success` on success
/// * `FjiResult::Error(message)` on failure
///
/// # Safety
/// All pointers must be valid and point to allocated memory.
/// `out_z_scores` must have capacity for at least `len` elements.
/// `std_dev` must be non-zero.
#[no_mangle]
pub extern "C" fn stat_arb_calculate_z_scores_batch(
    spread: *const f64,
    len: usize,
    mean: f64,
    std_dev: f64,
    out_z_scores: *mut f64,
) -> FfiResult {
    unsafe {
        // Validate inputs
        if spread.is_null() || out_z_scores.is_null() {
            return FfiResult::InvalidInput;
        }

        if len == 0 {
            return FfiResult::InvalidInput;
        }

        if std_dev == 0.0 {
            return FfiResult::InvalidInput;
        }

        // Create slices from raw pointers
        let spread_slice = std::slice::from_raw_parts(spread, len);
        let out_slice = std::slice::from_raw_parts_mut(out_z_scores, len);

        // Call SIMD-optimized z-score calculation
        crate::ffi::simd::calculate_z_scores_into(spread_slice, mean, std_dev, out_slice);

        FfiResult::Success
    }
}

/// Calculate Hurst exponent for mean reversion analysis
///
/// # Arguments
/// * `series` - Pointer to time series data
/// * `len` - Length of the series
/// * `out_hurst` - Pointer to store Hurst exponent output
///
/// # Returns
/// * `FfiResult::Success` on success
/// * `FfiResult::Error(message)` on failure
///
/// # Safety
/// All pointers must be valid and point to allocated memory.
/// Series must have at least 20 elements for meaningful results.
#[no_mangle]
pub extern "C" fn stat_arb_calculate_hurst_exponent(
    series: *const f64,
    len: usize,
    out_hurst: *mut f64,
) -> FfiResult {
    unsafe {
        // Validate inputs
        if series.is_null() || out_hurst.is_null() {
            return FfiResult::Error("Null pointer passed to stat_arb_calculate_hurst_exponent".into());
        }

        if len < 20 {
            *out_hurst = 0.5; // Default to random walk
            return FfiResult::Success;
        }

        // Create slice from raw pointer
        let slice = std::slice::from_raw_parts(series, len);

        // Import statistical module and calculate Hurst exponent
        match crate::arbitrage::statistical::calculate_hurst_exponent(slice) {
            Ok(hurst_exponent) => {
                *out_hurst = hurst_exponent;
                FfiResult::Success
            }
            Err(e) => FfiResult::Error(format!("Hurst exponent calculation failed: {}", e).into()),
        }
    }
}

/// Calculate half-life of mean reversion
///
/// # Arguments
/// * `series` - Pointer to spread series data
/// * `len` - Length of the series
/// * `out_half_life` - Pointer to store half-life output (in hours)
///
/// # Returns
/// * `FfiResult::Success` on success
/// * `FfiResult::Error(message)` on failure
///
/// # Safety
/// All pointers must be valid and point to allocated memory.
/// Series must have at least 10 elements for meaningful results.
#[no_mangle]
pub extern "C" fn stat_arb_calculate_half_life(
    series: *const f64,
    len: usize,
    out_half_life: *mut f64,
) -> FfiResult {
    unsafe {
        // Validate inputs
        if series.is_null() || out_half_life.is_null() {
            return FfiResult::Error("Null pointer passed to stat_arb_calculate_half_life".into());
        }

        if len < 10 {
            *out_half_life = 12.0; // Default 12 hours
            return FfiResult::Success;
        }

        // Create slice from raw pointer
        let slice = std::slice::from_raw_parts(series, len);

        // Import statistical module and calculate half-life
        match crate::arbitrage::statistical::calculate_half_life(slice) {
            Ok(half_life) => {
                *out_half_life = half_life;
                FfiResult::Success
            }
            Err(e) => FfiResult::Error(format!("Half-life calculation failed: {}", e).into()),
        }
    }
}

/// Calculate mean of a numeric series (standalone helper for FFI)
///
/// # Arguments
/// * `series` - Pointer to numeric series
/// * `len` - Length of the series
/// * `out_mean` - Pointer to store mean output
///
/// # Returns
/// * `FfiResult::Success` on success
/// * `FfiResult::Error(message)` on failure
///
/// # Safety
/// All pointers must be valid and point to allocated memory.
/// Series must have at least 1 element.
#[no_mangle]
pub extern "C" fn stat_arb_calculate_mean(
    series: *const f64,
    len: usize,
    out_mean: *mut f64,
) -> FfiResult {
    unsafe {
        // Validate inputs
        if series.is_null() || out_mean.is_null() {
            return FfiResult::Error("Null pointer passed to stat_arb_calculate_mean".into());
        }

        if len == 0 {
            return FfiResult::Error("Empty array passed to stat_arb_calculate_mean".into());
        }

        // Create slice from raw pointer
        let slice = std::slice::from_raw_parts(series, len);

        // Calculate mean
        let sum: f64 = slice.iter().sum();
        *out_mean = sum / len as f64;

        FfiResult::Success
    }
}

/// Calculate standard deviation of a numeric series (standalone helper for FFI)
///
/// # Arguments
/// * `series` - Pointer to numeric series
/// * `len` - Length of the series
/// * `mean` - Mean of the series (pre-calculated)
/// * `out_std` - Pointer to store standard deviation output
///
/// # Returns
/// * `FfiResult::Success` on success
/// * `FfiResult::Error(message)` on failure
///
/// # Safety
/// All pointers must be valid and point to allocated memory.
/// Series must have at least 2 elements for meaningful standard deviation.
#[no_mangle]
pub extern "C" fn stat_arb_calculate_std(
    series: *const f64,
    len: usize,
    mean: f64,
    out_std: *mut f64,
) -> FfiResult {
    unsafe {
        // Validate inputs
        if series.is_null() || out_std.is_null() {
            return FfiResult::Error("Null pointer passed to stat_arb_calculate_std".into());
        }

        if len < 2 {
            return FfiResult::Error("Insufficient data for standard deviation".into());
        }

        // Create slice from raw pointer
        let slice = std::slice::from_raw_parts(series, len);

        // Calculate variance and standard deviation
        let variance: f64 = slice.iter()
            .map(|x| (x - mean).powi(2))
            .sum::<f64>() / (len - 1) as f64;

        *out_std = variance.sqrt();

        FfiResult::Success
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use anyhow::Result;

    #[test]
    fn test_ffi_bytes_conversion() {
        let vec = vec![1, 2, 3, 4, 5];
        let ffi_bytes = FfiBytes::from_vec(vec.clone());

        assert_eq!(ffi_bytes.len, vec.len());
        assert!(!ffi_bytes.data.is_null());

        unsafe {
            let recovered = ffi_bytes.into_vec();
            assert_eq!(recovered, vec);
        }
    }

    #[test]
    fn test_ffi_string_conversion() {
        let string = "Hello, World!".to_string();
        let ffi_string = FfiString::from_string(string.clone());

        assert_eq!(ffi_string.len, string.len());
        assert!(!ffi_string.data.is_null());

        unsafe {
            let recovered = ffi_string.into_string();
            assert_eq!(recovered, string);
        }
    }

    #[test]
    fn test_ffi_result_conversion() {
        let success_result: Result<()> = Ok(());
        assert!(matches!(FfiResult::from(success_result), FfiResult::Success));

        let error_result: Result<()> = Err(anyhow::anyhow!("test error"));
        assert!(matches!(FfiResult::from(error_result), FfiResult::InternalError));
    }

    #[test]
    fn test_crypto_engine_ffi() {
        let engine = unsafe { crypto_engine_new() };
        assert!(!engine.is_null());

        unsafe {
            crypto_engine_destroy(engine);
        }
    }

    #[test]
    fn test_error_handling() {
        let message = "Test error message";
        let c_message = CString::new(message).unwrap();

        unsafe {
            ffi_set_last_error(c_message.as_ptr());
            let retrieved = ffi_get_last_error();
            assert!(!retrieved.is_null());

            let retrieved_cstr = CStr::from_ptr(retrieved);
            assert_eq!(retrieved_cstr.to_string_lossy(), message);

            ffi_clear_last_error();
            let cleared = ffi_get_last_error();
            assert!(cleared.is_null());
        }
    }
}