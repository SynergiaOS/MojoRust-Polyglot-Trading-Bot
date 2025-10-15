# =============================================================================
# Placeholder Detection Utility
# =============================================================================
# Detects placeholder API credentials and enables graceful fallback mode

from collections import Dict, List, Any
from os import environ
from core.logger import get_api_logger

@value
struct PlaceholderPatterns:
    """
    Common placeholder patterns for API credentials
    """
    var placeholder_prefixes: List[String]
    var placeholder_keywords: List[String]
    var demo_keywords: List[String]
    var test_keywords: List[String]

    fn __init__() -> Self:
        self.placeholder_prefixes = [
            "your_", "YOUR_", "my_", "MY_"
        ]
        self.placeholder_keywords = [
            "placeholder", "example", "sample", "dummy", "fake",
            "test", "testing", "demo", "dev", "development",
            "xxx", "yyy", "zzz", "abc", "123", "456"
        ]
        self.demo_keywords = [
            "demo_key", "demo_api", "demo_token", "demo_secret",
            "demo_key_here", "demo_api_key", "demo_token_here"
        ]
        self.test_keywords = [
            "test_key", "test_api", "test_token", "test_secret",
            "test_key_here", "test_api_key", "test_token_here"
        ]

struct PlaceholderDetector:
    """
    Detects placeholder API credentials and provides graceful handling
    """
    var patterns: PlaceholderPatterns
    var logger
    var detection_cache: Dict[String, Bool]

    fn __init__() -> Self:
        self.patterns = PlaceholderPatterns()
        self.logger = get_api_logger()
        self.detection_cache = Dict[String, Bool]()

    fn is_placeholder_value(self, key: String, value: String) -> Bool:
        """
        Check if a value appears to be a placeholder
        """
        # Check cache first
        cache_key = f"{key}:{value}"
        if cache_key in self.detection_cache:
            return self.detection_cache[cache_key]

        is_placeholder = False

        # Empty values
        if not value or value.strip() == "":
            is_placeholder = True

        # Check for placeholder prefixes
        for prefix in self.patterns.placeholder_prefixes:
            if value.lower().startswith(prefix.lower()):
                is_placeholder = True
                break

        # Check for placeholder keywords
        value_lower = value.lower()
        for keyword in self.patterns.placeholder_keywords:
            if keyword in value_lower:
                is_placeholder = True
                break

        # Check for demo patterns
        for demo in self.patterns.demo_keywords:
            if demo in value_lower:
                is_placeholder = True
                break

        # Check for test patterns
        for test in self.patterns.test_keywords:
            if test in value_lower:
                is_placeholder = True
                break

        # Check for common placeholder suffixes
        placeholder_suffixes = [
            "_here", "_placeholder", "_example", "_sample",
            "_key_here", "_api_key_here", "_token_here",
            "_secret_here", "_your_key", "_your_api"
        ]
        for suffix in placeholder_suffixes:
            if value_lower.endswith(suffix):
                is_placeholder = True
                break

        # Check for typical placeholder patterns
        placeholder_patterns = [
            "your_", "enter_your_", "replace_with_", "add_your_",
            "insert_", "put_your_", "set_your_", "change_to_"
        ]
        for pattern in placeholder_patterns:
            if pattern in value_lower:
                is_placeholder = True
                break

        # Cache result
        self.detection_cache[cache_key] = is_placeholder

        return is_placeholder

    fn scan_environment_placeholders(self) -> Dict[String, Any]:
        """
        Scan environment variables for placeholder API credentials
        """
        placeholder_vars = Dict[String, String]()
        api_key_patterns = [
            "API_KEY", "APIKEY", "API_TOKEN", "API_SECRET",
            "ACCESS_KEY", "ACCESS_TOKEN", "SECRET_KEY", "SECRET_TOKEN",
            "AUTH_TOKEN", "AUTH_KEY", "PRIVATE_KEY", "PUBLIC_KEY",
            "WEBHOOK_URL", "WEBHOOK_SECRET", "DATABASE_URL", "DB_URL"
        ]

        # Scan all environment variables
        for env_key, env_value in environ.items():
            # Check if this looks like an API credential
            is_api_key = False
            for pattern in api_key_patterns:
                if pattern in env_key.upper():
                    is_api_key = True
                    break

            if is_api_key and self.is_placeholder_value(env_key, env_value):
                placeholder_vars[env_key] = env_value

        # Create summary report
        total_placeholders = len(placeholder_vars)
        critical_apis = ["HELIUS_API_KEY", "QUICKNODE_API_KEY", "CLAUDE_API_KEY"]
        critical_placeholders = [key for key in critical_apis if key in placeholder_vars]

        report = {
            "total_placeholders": total_placeholders,
            "critical_placeholders": len(critical_placeholders),
            "placeholder_variables": placeholder_vars,
            "critical_placeholder_keys": critical_placeholders,
            "has_placeholders": total_placeholders > 0,
            "has_critical_placeholders": len(critical_placeholders) > 0,
            "placeholder_percentage": 0.0,
            "recommendation": ""
        }

        # Calculate placeholder percentage for API variables
        api_vars_count = sum(1 for key in environ.keys() if any(pattern in key.upper() for pattern in api_key_patterns))
        if api_vars_count > 0:
            report["placeholder_percentage"] = (total_placeholders / api_vars_count) * 100.0

        # Generate recommendation
        if report["has_critical_placeholders"]:
            report["recommendation"] = "CRITICAL: Replace placeholder API keys before production deployment"
        elif report["has_placeholders"]:
            report["recommendation"] = "WARNING: Replace placeholder credentials for full functionality"
        else:
            report["recommendation"] = "OK: No placeholder credentials detected"

        return report

    def log_placeholder_detection(self, report: Dict[String, Any]):
        """
        Log placeholder detection results
        """
        if report["has_placeholders"]:
            self.logger.warning(
                f"🚨 Placeholder API credentials detected: {report['total_placeholders']} variables",
                total_placeholders=report["total_placeholders"],
                critical_placeholders=report["critical_placeholders"],
                placeholder_percentage=f"{report['placeholder_percentage']:.1f}%",
                recommendation=report["recommendation"]
            )

            # Log critical placeholders specifically
            if report["has_critical_placeholders"]:
                for key in report["critical_placeholder_keys"]:
                    self.logger.error(
                        f"❌ Critical placeholder detected: {key}",
                        variable=key,
                        value=environ.get(key, ""),
                        severity="critical"
                    )

            # Log all placeholder variables
            for key, value in report["placeholder_variables"].items():
                self.logger.info(
                    f"🔑 Placeholder API variable: {key}",
                    variable=key,
                    has_value=bool(value and value.strip()),
                    is_critical=key in report["critical_placeholder_keys"]
                )
        else:
            self.logger.info(
                "✅ No placeholder API credentials detected",
                recommendation=report["recommendation"]
            )

    def enable_fallback_mode_for_placeholders(self, fallback_handlers: List[Any]) -> Bool:
        """
        Enable fallback mode for API clients that have placeholder credentials
        """
        report = self.scan_environment_placeholders()
        self.log_placeholder_detection(report)

        if report["has_placeholders"]:
            # Enable fallback mode for all handlers
            for handler in fallback_handlers:
                if hasattr(handler, "config"):
                    handler.config.use_real_api = False
                    handler.config.fallback_to_mock = True
                    handler.config.log_fallbacks = True

                    if hasattr(handler, "logger"):
                        handler.logger.warning("🔄 Fallback mode enabled due to placeholder credentials")

            return True
        return False

    def validate_api_configuration(self, required_keys: List[String]) -> Dict[String, Any]:
        """
        Validate required API keys and check for placeholders
        """
        validation_result = {
            "valid": True,
            "missing_keys": [],
            "placeholder_keys": [],
            "valid_keys": [],
            "summary": "",
            "ready_for_production": False
        }

        for key in required_keys:
            value = environ.get(key, "")

            if not value or value.strip() == "":
                validation_result["missing_keys"].append(key)
                validation_result["valid"] = False
            elif self.is_placeholder_value(key, value):
                validation_result["placeholder_keys"].append(key)
                validation_result["valid"] = False
            else:
                validation_result["valid_keys"].append(key)

        # Determine production readiness
        validation_result["ready_for_production"] = (
            validation_result["valid"] and
            len(validation_result["valid_keys"]) == len(required_keys)
        )

        # Generate summary
        if validation_result["ready_for_production"]:
            validation_result["summary"] = "✅ All API keys configured and ready for production"
        elif validation_result["missing_keys"]:
            validation_result["summary"] = f"❌ Missing API keys: {', '.join(validation_result['missing_keys'])}"
        elif validation_result["placeholder_keys"]:
            validation_result["summary"] = f"⚠️  Placeholder API keys: {', '.join(validation_result['placeholder_keys'])}"
        else:
            validation_result["summary"] = "⚠️  API configuration has issues"

        return validation_result

    def get_placeholder_replacement_guide(self) -> Dict[String, String]:
        """
        Get guide for replacing placeholder credentials
        """
        return {
            "HELIUS_API_KEY": "Get from https://dev.helius.xyz",
            "QUICKNODE_API_KEY": "Get from https://www.quicknode.com",
            "CLAUDE_API_KEY": "Get from https://console.anthropic.com",
            "HONEYPOT_API_KEY": "Get from https://honeypot.is",
            "TWITTER_API_KEY": "Get from https://developer.twitter.com",
            "PUMPPORTAL_API_KEY": "Get from https://pumpportal.fun",
            "SOLANA_PRIVATE_KEY": "Generate with Solana CLI: solana-keygen new",
            "JWT_SECRET_KEY": "Generate with: openssl rand -base64 32",
            "REPLACEMENT_GUIDE": "Replace placeholder values in .env file with real API keys",
            "SECURITY_NOTE": "Never commit real API keys to version control"
        }

# Global placeholder detector instance
var global_placeholder_detector = PlaceholderDetector()

# Utility functions for easy access
fn detect_placeholder_credentials() -> Dict[String, Any]:
    """Quick check for placeholder credentials"""
    return global_placeholder_detector.scan_environment_placeholders()

fn is_api_key_placeholder(key: String, value: String) -> Bool:
    """Check if specific API key is placeholder"""
    return global_placeholder_detector.is_placeholder_value(key, value)

fn validate_required_api_keys(required_keys: List[String]) -> Dict[String, Any]:
    """Validate required API keys"""
    return global_placeholder_detector.validate_api_configuration(required_keys)

fn enable_graceful_fallback_for_placeholders(fallback_handlers: List[Any]) -> Bool:
    """Enable fallback mode if placeholders detected"""
    return global_placeholder_detector.enable_fallback_mode_for_placeholders(fallback_handlers)