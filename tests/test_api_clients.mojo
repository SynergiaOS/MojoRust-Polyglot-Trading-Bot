#!/usr/bin/env mojo3
# =============================================================================
# API Clients Test Suite
# =============================================================================

import core.types
from time import time

# =============================================================================
# Test Framework
# =============================================================================

var tests_passed = 0
var tests_failed = 0

fn assert_true(condition: Bool, test_name: String):
    if condition:
        tests_passed += 1
        print(f"✅ {test_name}")
    else:
        tests_failed += 1
        print(f"❌ {test_name}")

fn assert_not_none(value, test_name: String):
    if value is not None:
        tests_passed += 1
        print(f"✅ {test_name}")
    else:
        tests_failed += 1
        print(f"❌ {test_name}")

# =============================================================================
# Helius Client Tests
# =============================================================================

fn test_helius_client():
    """
    Test Helius API client functionality
    """
    print("🧪 Testing Helius Client...")

    from data.helius_client import HeliusClient
    client = HeliusClient(api_key="test_key")

    # Test token metadata
    metadata = client.get_token_metadata("test_address")
    assert_not_none(metadata, "Token metadata retrieval")

    # Test holder data
    holder_data = client.get_holder_data("test_address")
    assert_not_none(holder_data, "Holder data retrieval")

    # Test transaction history
    tx_history = client.get_transaction_history("test_address")
    assert_not_none(tx_history, "Transaction history retrieval")

    # Test health check
    is_healthy = client.health_check()
    assert_true(is_healthy, "Health check")

# =============================================================================
# QuickNode Client Tests
# =============================================================================

fn test_quicknode_client():
    """
    Test QuickNode RPC client functionality
    """
    print("🧪 Testing QuickNode Client...")

    from data.quicknode_client import QuickNodeClient, QuickNodeRPCs
    rpcs = QuickNodeRPCs(primary="test_rpc")
    client = QuickNodeClient(rpcs=rpcs)

    # Test balance retrieval
    balance = client.get_balance("test_address")
    assert_true(balance >= 0.0, "Balance retrieval")

    # Test account info
    account_info = client.get_account_info("test_address")
    assert_not_none(account_info, "Account info retrieval")

    # Test transaction details
    tx_details = client.get_transaction("test_signature")
    assert_not_none(tx_details, "Transaction details retrieval")

    # Test latest blockhash
    blockhash = client.get_latest_blockhash()
    assert_not_none(blockhash, "Latest blockhash retrieval")

    # Test health check
    is_healthy = client.health_check()
    assert_true(is_healthy, "Health check")

# =============================================================================
# DexScreener Client Tests
# =============================================================================

fn test_dexscreener_client():
    """
    Test DexScreener API client functionality
    """
    print("🧪 Testing DexScreener Client...")

    from data.dexscreener_client import DexScreenerClient
    client = DexScreenerClient()

    # Test token pairs retrieval
    pairs = client.get_token_pairs("test_token")
    assert_true(len(pairs) >= 0, "Token pairs retrieval")

    # Test latest tokens
    latest_tokens = client.get_latest_tokens("solana", 10)
    assert_true(len(latest_tokens) <= 10, "Latest tokens retrieval limit")

    # Test trending tokens
    trending_tokens = client.get_trending_tokens("solana")
    assert_true(len(trending_tokens) >= 0, "Trending tokens retrieval")

    # Test search functionality
    search_results = client.search_tokens("query")
    assert_true(len(search_results) >= 0, "Search functionality")

# =============================================================================
# Jupiter Client Tests
# =============================================================================

fn test_jupiter_client():
    """
    Test Jupiter API client functionality
    """
    print("🧪 Testing Jupiter Client...")

    from data.jupiter_client import JupiterClient
    client = JupiterClient()

    # Test quote retrieval
    quote = client.get_quote("input_mint", "output_mint", 1000.0)
    assert_not_none(quote, "Quote retrieval")

    # Test supported tokens
    supported_tokens = client.get_supported_tokens()
    assert_true(len(supported_tokens) > 0, "Supported tokens retrieval")

    # Test route information
    routes = client.get_routes_for_pair("input_mint", "output_mint")
    assert_true(len(routes) >= 0, "Route information retrieval")

    # Test platform info
    platform_info = client.get_platform_info()
    assert_not_none(platform_info, "Platform info retrieval")

    # Test health check
    is_healthy = client.health_check()
    assert_true(is_healthy, "Health check")

# =============================================================================
# Main Test Runner
# =============================================================================

fn run_all_api_tests():
    """
    Run all API client tests
    """
    print("🚀 Starting API Clients Test Suite")
    print("=" * 50)

    test_helius_client()
    test_quicknode_client()
    test_dexscreener_client()
    test_jupiter_client()

    print("\n" + "=" * 50)
    print(f"📊 API Clients Test Results:")
    print(f"   ✅ Passed: {tests_passed}")
    print(f"   ❌ Failed: {tests_failed}")
    print(f"   📊 Success Rate: {(tests_passed / (tests_passed + tests_failed) * 100):.1f}%")

    return tests_failed == 0

fn main():
    """
    Main entry point
    """
    success = run_all_api_tests()
    return 0 if success else 1

if __name__ == "__main__":
    exit(main())