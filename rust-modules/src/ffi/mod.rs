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

// Re-export main interfaces for FFI
pub use crate::crypto::CryptoEngine;
pub use crate::security::SecurityEngine;
pub use crate::solana::SolanaEngine;

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