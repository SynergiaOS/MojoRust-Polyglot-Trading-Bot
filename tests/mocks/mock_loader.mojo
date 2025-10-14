# =============================================================================
# Mock Loader Utility
# =============================================================================

from python import Python
from time import time
from collections import Dict, List
from sys import exit

@value
struct MockLoader:
    """
    Mock data loader for offline integration testing
    Provides centralized access to all mock JSON files
    """
    var cache: Dict[String, Any]
    var cache_enabled: Bool
    var base_path: String

    fn __init__(cache_enabled: Bool = True, base_path: String = "tests/mocks/"):
        self.cache_enabled = cache_enabled
        self.cache = {}
        self.base_path = base_path

    fn load_mock_response(self, filename: String, key: String = "") -> Any:
        """
        Load mock response from JSON file with optional key
        """
        # Create cache key
        cache_key = f"{filename}:{key}" if key else filename

        # Check cache first
        if self.cache_enabled and cache_key in self.cache:
            return self.cache[cache_key]

        try:
            # Load JSON using Python
            python = Python.import_module("json")
            file_io = Python.import_module("builtins").open

            file_path = self.base_path + filename
            with file_io(file_path, "r") as f:
                data = python.load(f)

            # Get specific key if provided
            result = data[key] if key else data

            # Cache result
            if self.cache_enabled:
                self.cache[cache_key] = result

            return result

        except e:
            print(f"Error loading mock response from {filename}:{key}")
            print(f"Error details: {e}")
            return None

    fn load_helius_response(self, response_type: String, token_type: String = "valid_token") -> Any:
        """
        Load Helius API mock response
        """
        return self.load_mock_response("helius_responses.json", token_type)

    fn load_jupiter_response(self, response_type: String, scenario: String = "sol_to_token") -> Any:
        """
        Load Jupiter API mock response
        """
        return self.load_mock_response("jupiter_responses.json", scenario)

    fn load_dexscreener_response(self, response_type: String) -> Any:
        """
        Load DexScreener API mock response
        """
        return self.load_mock_response("dexscreener_responses.json", response_type)

    fn load_quicknode_response(self, response_type: String) -> Any:
        """
        Load QuickNode API mock response
        """
        return self.load_mock_response("quicknode_responses.json", response_type)

    fn load_market_scenario(self, scenario: String) -> Any:
        """
        Load market scenario for strategy testing
        """
        return self.load_mock_response("market_scenarios.json", scenario)

    def clear_cache(self):
        """
        Clear the mock response cache
        """
        self.cache = {}

    def get_cache_stats(self) -> Dict[String, Any]:
        """
        Get cache statistics
        """
        return {
            "cache_size": len(self.cache),
            "cache_enabled": self.cache_enabled,
            "cached_keys": list(self.cache.keys())
        }

    def validate_mock_data(self) -> Bool:
        """
        Validate that all mock files are present and valid JSON
        """
        required_files = [
            "helius_responses.json",
            "jupiter_responses.json",
            "dexscreener_responses.json",
            "quicknode_responses.json",
            "market_scenarios.json"
        ]

        python = Python.import_module("json")
        file_io = Python.import_module("builtins").open

        for filename in required_files:
            try:
                file_path = self.base_path + filename
                with file_io(file_path, "r") as f:
                    python.load(f)
                print(f"✓ Valid JSON: {filename}")
            except e:
                print(f"✗ Invalid JSON or missing file: {filename} - {e}")
                return False

        return True

    def smoke_test(self) -> Bool:
        """
        Run smoke test to verify mock loader functionality
        """
        print("Running mock loader smoke test...")

        # Test Helius responses
        helius_valid = self.load_helius_response("valid_token")
        if not helius_valid or "onChain" not in helius_valid:
            print("✗ Helius valid token test failed")
            return False
        print("✓ Helius valid token test passed")

        # Test Jupiter responses
        jupiter_swap = self.load_jupiter_response("swap", "sol_to_token")
        if not jupiter_swap or "inputMint" not in jupiter_swap:
            print("✗ Jupiter swap test failed")
            return False
        print("✓ Jupiter swap test passed")

        # Test DexScreener responses
        dexscreener_trending = self.load_dexscreener_response("trending_tokens")
        if not dexscreener_trending or "pairs" not in dexscreener_trending:
            print("✗ DexScreener trending test failed")
            return False
        print("✓ DexScreener trending test passed")

        # Test QuickNode responses
        quicknode_account = self.load_quicknode_response("account_info")
        if not quicknode_account or "result" not in quicknode_account:
            print("✗ QuickNode account info test failed")
            return False
        print("✓ QuickNode account info test passed")

        # Test market scenarios
        bull_market = self.load_market_scenario("bull_market")
        if not bull_market or "market_data" not in bull_market:
            print("✗ Bull market scenario test failed")
            return False
        print("✓ Bull market scenario test passed")

        # Test cache
        cache_stats = self.get_cache_stats()
        if cache_stats["cache_size"] < 5:
            print("✗ Cache test failed - expected at least 5 cached items")
            return False
        print(f"✓ Cache test passed - {cache_stats['cache_size']} items cached")

        print("✓ All smoke tests passed!")
        return True

# Global instance for easy imports
_global_mock_loader = MockLoader()

# Convenience functions for direct import
def load_helius_response(response_type: String, token_type: String = "valid_token") -> Any:
    return _global_mock_loader.load_helius_response(response_type, token_type)

def load_jupiter_response(response_type: String, scenario: String = "sol_to_token") -> Any:
    return _global_mock_loader.load_jupiter_response(response_type, scenario)

def load_dexscreener_response(response_type: String) -> Any:
    return _global_mock_loader.load_dexscreener_response(response_type)

def load_quicknode_response(response_type: String) -> Any:
    return _global_mock_loader.load_quicknode_response(response_type)

def load_market_scenario(scenario: String) -> Any:
    return _global_mock_loader.load_market_scenario(scenario)

def clear_mock_cache():
    _global_mock_loader.clear_cache()

def get_mock_cache_stats() -> Dict[String, Any]:
    return _global_mock_loader.get_cache_stats()

def run_mock_smoke_test() -> Bool:
    return _global_mock_loader.smoke_test()

# Test runner for validation
def main():
    """
    Main function to validate mock infrastructure
    """
    print("=== Mock Infrastructure Validation ===")

    # Create fresh loader
    loader = MockLoader()

    # Validate JSON files
    print("\n1. Validating JSON files...")
    if not loader.validate_mock_data():
        print("❌ JSON validation failed")
        exit(1)
    print("✅ All JSON files valid")

    # Run smoke test
    print("\n2. Running smoke test...")
    if not loader.smoke_test():
        print("❌ Smoke test failed")
        exit(1)
    print("✅ Smoke test passed")

    # Print cache stats
    print("\n3. Cache statistics:")
    stats = loader.get_cache_stats()
    print(f"   - Cache size: {stats['cache_size']} items")
    print(f"   - Cache enabled: {stats['cache_enabled']}")
    print(f"   - Cached keys: {len(stats['cached_keys'])}")

    print("\n✅ Mock infrastructure validation complete!")
    return True

if __name__ == "__main__":
    main()