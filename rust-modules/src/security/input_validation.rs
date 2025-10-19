//! Input validation and sanitization utilities
//!
//! Provides comprehensive input validation to prevent injection attacks,
//! ensure data integrity, and sanitize user inputs.

use anyhow::{anyhow, Result};
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Input validation rules
#[derive(Debug, Clone)]
pub enum ValidationRule {
    NoEmpty,
    MinLength(usize),
    MaxLength(usize),
    LengthRange(usize, usize),
    Pattern(Regex),
    NoSqlInjection,
    NoXss,
    NoPathTraversal,
    Numeric,
    PositiveNumeric,
    Email,
    Url,
    SolanaAddress,
    HexString,
    Base64String,
    Json,
    Custom(Box<dyn Fn(&str) -> bool + Send + Sync>),
}

/// Input validator
pub struct InputValidator {
    rules: HashMap<String, Vec<ValidationRule>>,
    sanitizers: HashMap<String, Sanitizer>,
}

impl InputValidator {
    /// Create new input validator
    pub fn new() -> Self {
        Self {
            rules: HashMap::new(),
            sanitizers: HashMap::new(),
        }
    }

    /// Add validation rule for an endpoint/field
    pub fn add_rule(&mut self, endpoint: &str, rule: ValidationRule) {
        self.rules.entry(endpoint.to_string()).or_insert_with(Vec::new).push(rule);
    }

    /// Add multiple validation rules
    pub fn add_rules(&mut self, endpoint: &str, rules: Vec<ValidationRule>) {
        for rule in rules {
            self.add_rule(endpoint, rule);
        }
    }

    /// Add sanitizer for an endpoint
    pub fn add_sanitizer(&mut self, endpoint: &str, sanitizer: Sanitizer) {
        self.sanitizers.insert(endpoint.to_string(), sanitizer);
    }

    /// Validate input data for endpoint
    pub fn validate(&self, data: &[u8], endpoint: &str) -> Result<()> {
        let input = String::from_utf8(data.to_vec())
            .map_err(|_| anyhow!("Invalid UTF-8 input"))?;

        let rules = self.rules.get(endpoint)
            .ok_or_else(|| anyhow!("No validation rules for endpoint: {}", endpoint))?;

        for rule in rules {
            self.apply_rule(&input, rule)?;
        }

        Ok(())
    }

    /// Validate and sanitize input
    pub fn validate_and_sanitize(&self, data: &[u8], endpoint: &str) -> Result<Vec<u8>> {
        // First validate
        self.validate(data, endpoint)?;

        // Then sanitize
        if let Some(sanitizer) = self.sanitizers.get(endpoint) {
            Ok(sanitizer.sanitize(data)?)
        } else {
            Ok(data.to_vec())
        }
    }

    /// Validate JSON data with field-specific rules
    pub fn validate_json(&self, json_data: &[u8], field_rules: &HashMap<String, Vec<ValidationRule>>) -> Result<()> {
        let json_str = String::from_utf8(json_data.to_vec())
            .map_err(|_| anyhow!("Invalid UTF-8 JSON"))?;

        let json: serde_json::Value = serde_json::from_str(&json_str)
            .map_err(|_| anyhow!("Invalid JSON format"))?;

        for (field, rules) in field_rules {
            if let Some(value) = json.get(field) {
                let field_value = match value {
                    serde_json::Value::String(s) => s.clone(),
                    _ => value.to_string(),
                };

                for rule in rules {
                    self.apply_rule(&field_value, rule)?;
                }
            }
        }

        Ok(())
    }

    /// Apply validation rule to input
    fn apply_rule(&self, input: &str, rule: &ValidationRule) -> Result<()> {
        match rule {
            ValidationRule::NoEmpty => {
                if input.trim().is_empty() {
                    return Err(anyhow!("Input cannot be empty"));
                }
            }

            ValidationRule::MinLength(min) => {
                if input.len() < *min {
                    return Err(anyhow!("Input too short, minimum {} characters", min));
                }
            }

            ValidationRule::MaxLength(max) => {
                if input.len() > *max {
                    return Err(anyhow!("Input too long, maximum {} characters", max));
                }
            }

            ValidationRule::LengthRange(min, max) => {
                if input.len() < *min || input.len() > *max {
                    return Err(anyhow!("Input length must be between {} and {} characters", min, max));
                }
            }

            ValidationRule::Pattern(regex) => {
                if !regex.is_match(input) {
                    return Err(anyhow!("Input does not match required pattern"));
                }
            }

            ValidationRule::NoSqlInjection => {
                if self.detect_sql_injection(input) {
                    return Err(anyhow!("Potential SQL injection detected"));
                }
            }

            ValidationRule::NoXss => {
                if self.detect_xss(input) {
                    return Err(anyhow!("Potential XSS attack detected"));
                }
            }

            ValidationRule::NoPathTraversal => {
                if self.detect_path_traversal(input) {
                    return Err(anyhow!("Potential path traversal attack detected"));
                }
            }

            ValidationRule::Numeric => {
                if input.parse::<f64>().is_err() {
                    return Err(anyhow!("Input must be numeric"));
                }
            }

            ValidationRule::PositiveNumeric => {
                match input.parse::<f64>() {
                    Ok(num) if num > 0.0 => {},
                    _ => return Err(anyhow!("Input must be a positive number")),
                }
            }

            ValidationRule::Email => {
                if !self.is_valid_email(input) {
                    return Err(anyhow!("Invalid email format"));
                }
            }

            ValidationRule::Url => {
                if !self.is_valid_url(input) {
                    return Err(anyhow!("Invalid URL format"));
                }
            }

            ValidationRule::SolanaAddress => {
                if !self.is_valid_solana_address(input) {
                    return Err(anyhow!("Invalid Solana address format"));
                }
            }

            ValidationRule::HexString => {
                if !self.is_valid_hex_string(input) {
                    return Err(anyhow!("Invalid hex string format"));
                }
            }

            ValidationRule::Base64String => {
                if !self.is_valid_base64_string(input) {
                    return Err(anyhow!("Invalid base64 string format"));
                }
            }

            ValidationRule::Json => {
                if serde_json::from_str::<serde_json::Value>(input).is_err() {
                    return Err(anyhow!("Invalid JSON format"));
                }
            }

            ValidationRule::Custom(validator) => {
                if !validator(input) {
                    return Err(anyhow!("Custom validation failed"));
                }
            }
        }

        Ok(())
    }

    /// Detect SQL injection patterns
    fn detect_sql_injection(&self, input: &str) -> bool {
        let sql_patterns = vec![
            r"(?i)(union|select|insert|update|delete|drop|create|alter|exec|execute)",
            r"(?i)(or|and)\s+\d+\s*=\s*\d+",
            r"(?i)(or|and)\s+['\"]?\w+['\"]?\s*=\s*['\"]?\w+['\"]?",
            r"(?i)(--|/\*|\*/|;)",
            r"(?i)(script|javascript|vbscript)",
            r"(?i)(waitfor|delay|benchmark)",
            r"(?i)(load_file|into\s+outfile|into\s+dumpfile)",
        ];

        let lower_input = input.to_lowercase();

        sql_patterns.iter().any(|pattern| {
            Regex::new(pattern).unwrap().is_match(&lower_input)
        })
    }

    /// Detect XSS patterns
    fn detect_xss(&self, input: &str) -> bool {
        let xss_patterns = vec![
            r"(?i)<script[^>]*>.*?</script>",
            r"(?i)javascript:",
            r"(?i)vbscript:",
            r"(?i)onload\s*=",
            r"(?i)onerror\s*=",
            r"(?i)onclick\s*=",
            r"(?i)onmouseover\s*=",
            r"(?i)<iframe[^>]*>",
            r"(?i)<object[^>]*>",
            r"(?i)<embed[^>]*>",
            r"(?i)<link[^>]*>",
            r"(?i)<meta[^>]*>",
            r"(?i)expression\s*\(",
            r"(?i)@import",
            r"(?i)eval\s*\(",
        ];

        xss_patterns.iter().any(|pattern| {
            Regex::new(pattern).unwrap().is_match(input)
        })
    }

    /// Detect path traversal patterns
    fn detect_path_traversal(&self, input: &str) -> bool {
        let traversal_patterns = vec![
            r"\.\.[/\\]",
            r"[/\\]\.\.[/\\]",
            r"[/\\]\.\.$",
            r"^\.\\.",
            r"%2e%2e[/\\]",
            r"%2f%2f",
            r"%5c%5c",
            r"\.\.%2f",
            r"\.\.%5c",
            r"[/\\][/\\][/\\]",
        ];

        traversal_patterns.iter().any(|pattern| {
            Regex::new(pattern).unwrap().is_match(input)
        })
    }

    /// Validate email format
    fn is_valid_email(&self, email: &str) -> bool {
        let email_regex = Regex::new(
            r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
        ).unwrap();

        email_regex.is_match(email) && email.len() <= 254
    }

    /// Validate URL format
    fn is_valid_url(&self, url: &str) -> bool {
        let url_regex = Regex::new(
            r"^https?://(?:[-\w.])+(?:[:\d]+)?(?:/(?:[\w/_.])*(?:\?(?:[\w&=%.])*)?(?:#(?:\w*))?)?$"
        ).unwrap();

        url_regex.is_match(url) && url.len() <= 2048
    }

    /// Validate Solana address format
    fn is_valid_solana_address(&self, address: &str) -> bool {
        if address.len() < 32 || address.len() > 44 {
            return false;
        }

        // Check if it's valid base58
        bs58::decode(address).into_vec().is_ok()
    }

    /// Validate hex string
    fn is_valid_hex_string(&self, hex: &str) -> bool {
        if hex.is_empty() || hex.len() % 2 != 0 {
            return false;
        }

        hex.chars().all(|c| c.is_ascii_hexdigit())
    }

    /// Validate base64 string
    fn is_valid_base64_string(&self, base64: &str) -> bool {
        base64::decode(base64).is_ok()
    }

    /// Get validation rules for endpoint
    pub fn get_rules(&self, endpoint: &str) -> Option<&Vec<ValidationRule>> {
        self.rules.get(endpoint)
    }

    /// Remove validation rules for endpoint
    pub fn remove_rules(&mut self, endpoint: &str) {
        self.rules.remove(endpoint);
        self.sanitizers.remove(endpoint);
    }

    /// Create default validation rules for common endpoints
    pub fn create_default_rules(&mut self) {
        // Trading endpoint rules
        self.add_rules("trade", vec![
            ValidationRule::NoEmpty,
            ValidationRule::MinLength(1),
            ValidationRule::MaxLength(1000),
            ValidationRule::NoSqlInjection,
            ValidationRule::NoXss,
        ]);

        // API key validation
        self.add_rules("api_key", vec![
            ValidationRule::NoEmpty,
            ValidationRule::LengthRange(16, 256),
            ValidationRule::Pattern(Regex::new(r"^[a-zA-Z0-9_-]+$").unwrap()),
        ]);

        // Solana address validation
        self.add_rules("solana_address", vec![
            ValidationRule::NoEmpty,
            ValidationRule::SolanaAddress,
        ]);

        // Amount validation
        self.add_rules("amount", vec![
            ValidationRule::NoEmpty,
            ValidationRule::PositiveNumeric,
        ]);

        // Email validation
        self.add_rules("email", vec![
            ValidationRule::NoEmpty,
            ValidationRule::Email,
        ]);
    }
}

/// Input sanitizer
pub struct Sanitizer {
    rules: Vec<SanitizeRule>,
}

impl Sanitizer {
    /// Create new sanitizer
    pub fn new() -> Self {
        Self {
            rules: Vec::new(),
        }
    }

    /// Add sanitization rule
    pub fn add_rule(&mut self, rule: SanitizeRule) {
        self.rules.push(rule);
    }

    /// Sanitize input data
    pub fn sanitize(&self, data: &[u8]) -> Result<Vec<u8>> {
        let mut result = String::from_utf8(data.to_vec())
            .map_err(|_| anyhow!("Invalid UTF-8 input"))?;

        for rule in &self.rules {
            result = self.apply_sanitize_rule(result, rule);
        }

        Ok(result.into_bytes())
    }

    fn apply_sanitize_rule(&self, input: String, rule: &SanitizeRule) -> String {
        match rule {
            SanitizeRule::Trim => input.trim().to_string(),
            SanitizeRule::Lowercase => input.to_lowercase(),
            SanitizeRule::Uppercase => input.to_uppercase(),
            SanitizeRule::RemoveWhitespace => input.chars().filter(|c| !c.is_whitespace()).collect(),
            SanitizeRule::NormalizeWhitespace => {
                let re = Regex::new(r"\s+").unwrap();
                re.replace_all(&input, " ").to_string()
            }
            SanitizeRule::RemoveHtml => {
                let re = Regex::new(r"<[^>]*>").unwrap();
                re.replace_all(&input, "").to_string()
            }
            SanitizeRule::EscapeHtml => {
                input.replace('&', "&amp;")
                     .replace('<', "&lt;")
                     .replace('>', "&gt;")
                     .replace('"', "&quot;")
                     .replace('\'', "&#x27;")
            }
            SanitizeRule::RemoveSpecialChars => {
                input.chars().filter(|c| c.is_alphanumeric() || c.is_whitespace()).collect()
            }
            SanitizeRule::Custom(sanitizer) => sanitizer(input),
        }
    }
}

/// Sanitization rules
#[derive(Clone)]
pub enum SanitizeRule {
    Trim,
    Lowercase,
    Uppercase,
    RemoveWhitespace,
    NormalizeWhitespace,
    RemoveHtml,
    EscapeHtml,
    RemoveSpecialChars,
    Custom(Box<dyn Fn(String) -> String + Send + Sync>),
}

/// Validation result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidationResult {
    pub is_valid: bool,
    pub errors: Vec<String>,
    pub sanitized_data: Option<Vec<u8>>,
}

impl ValidationResult {
    /// Create successful validation result
    pub fn success() -> Self {
        Self {
            is_valid: true,
            errors: Vec::new(),
            sanitized_data: None,
        }
    }

    /// Create failed validation result
    pub fn failure(errors: Vec<String>) -> Self {
        Self {
            is_valid: false,
            errors,
            sanitized_data: None,
        }
    }

    /// Add sanitized data to result
    pub fn with_sanitized_data(mut self, data: Vec<u8>) -> Self {
        self.sanitized_data = Some(data);
        self
    }
}

impl Default for InputValidator {
    fn default() -> Self {
        let mut validator = Self::new();
        validator.create_default_rules();
        validator
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sql_injection_detection() {
        let validator = InputValidator::new();

        assert!(validator.detect_sql_injection("SELECT * FROM users"));
        assert!(validator.detect_sql_injection("'; DROP TABLE users; --"));
        assert!(validator.detect_sql_injection("OR 1=1"));

        assert!(!validator.detect_sql_injection("normal input"));
    }

    #[test]
    fn test_xss_detection() {
        let validator = InputValidator::new();

        assert!(validator.detect_xss("<script>alert('xss')</script>"));
        assert!(validator.detect_xss("javascript:alert('xss')"));
        assert!(validator.detect_xss("<img src=x onerror=alert('xss')>"));

        assert!(!validator.detect_xss("normal text"));
    }

    #[test]
    fn test_path_traversal_detection() {
        let validator = InputValidator::new();

        assert!(validator.detect_path_traversal("../../../etc/passwd"));
        assert!(validator.detect_path_traversal("..\\..\\windows\\system32"));
        assert!(validator.detect_path_traversal("%2e%2e%2f"));

        assert!(!validator.detect_path_traversal("normal/path"));
    }

    #[test]
    fn test_email_validation() {
        let validator = InputValidator::new();

        assert!(validator.is_valid_email("test@example.com"));
        assert!(validator.is_valid_email("user.name+tag@domain.co.uk"));

        assert!(!validator.is_valid_email("invalid-email"));
        assert!(!validator.is_valid_email("@domain.com"));
        assert!(!validator.is_valid_email("user@"));
    }

    #[test]
    fn test_solana_address_validation() {
        let validator = InputValidator::new();

        assert!(validator.is_valid_solana_address("11111111111111111111111111111112"));
        assert!(validator.is_valid_solana_address("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"));

        assert!(!validator.is_valid_solana_address("invalid"));
        assert!(!validator.is_valid_solana_address("111111111111111111111111111111111111111111111"));
    }

    #[test]
    fn test_input_validation() {
        let mut validator = InputValidator::new();
        validator.add_rules("test", vec![
            ValidationRule::NoEmpty,
            ValidationRule::MinLength(3),
            ValidationRule::MaxLength(10),
        ]);

        assert!(validator.validate("test", "test").is_ok());
        assert!(validator.validate("test", "1234567890").is_ok());

        assert!(validator.validate("test", "").is_err());
        assert!(validator.validate("test", "ab").is_err());
        assert!(validator.validate("test", "12345678901").is_err());
    }

    #[test]
    fn test_sanitization() {
        let mut sanitizer = Sanitizer::new();
        sanitizer.add_rule(SanitizeRule::Trim);
        sanitizer.add_rule(SanitizeRule::Lowercase);

        let result = sanitizer.sanitize(b"  TEST INPUT  ").unwrap();
        assert_eq!(result, b"test input");
    }

    #[test]
    fn test_json_validation() {
        let validator = InputValidator::new();
        let mut field_rules = HashMap::new();

        field_rules.insert("name".to_string(), vec![
            ValidationRule::NoEmpty,
            ValidationRule::MinLength(2),
        ]);

        field_rules.insert("age".to_string(), vec![
            ValidationRule::PositiveNumeric,
        ]);

        let valid_json = r#"{"name": "John", "age": 25}"#;
        let invalid_json = r#"{"name": "", "age": -5}"#;

        assert!(validator.validate_json(valid_json.as_bytes(), &field_rules).is_ok());
        assert!(validator.validate_json(invalid_json.as_bytes(), &field_rules).is_err());
    }
}