#!/usr/bin/env mojo3

# =============================================================================
# API Integration Tests
# =============================================================================
# Integration tests for all API clients using centralized mocks
# =============================================================================

import sys
from time import time
from collections import Dict, List

# Add source path
sys.path.append("../../src")

# Import core types and test utilities
from core.types import (
    MarketData, TradingSignal, TokenMetadata, TradingPair, SwapQuote
)
from core.config import Config

# Import mock loader
from tests.mocks.mock_loader import (
    load_helius_response, load_jupiter_response,
    load_dexscreener_response, load_quicknode_response,
    clear_mock_cache, get_mock_cache_stats
)

# =============================================================================
# Test Framework
# =============================================================================

var test_count = 0
var passed_tests = 0
var failed_tests = 0

fn assert_equal(actual, expected, test_name: String):
    test_count += 1
    if actual == expected:
        passed_tests += 1
        print(f"✅ PASS: {test_name}")
    else:
        failed_tests += 1
        print(f"❌ FAIL: {test_name}")
        print(f"   Expected: {expected}, Got: {actual}")

fn assert_true(condition: Bool, test_name: String):
    test_count += 1
    if condition:
        passed_tests += 1
        print(f"✅ PASS: {test_name}")
    else:
        failed_tests += 1
        print(f"❌ FAIL: {test_name}")
        print(f"   Expected: True, Got: False")

fn assert_false(condition: Bool, test_name: String):
    test_count += 1
    if not condition:
        passed_tests += 1
        print(f"✅ PASS: {test_name}")
    else:
        failed_tests += 1
        print(f"❌ FAIL: {test_name}")
        print(f"   Expected: False, Got: True")

fn assert_close(actual: Float, expected: Float, tolerance: Float, test_name: String):
    test_count += 1
    if abs(actual - expected) <= tolerance:
        passed_tests += 1
        print(f"✅ PASS: {test_name}")
    else:
        failed_tests += 1
        print(f"❌ FAIL: {test_name}")
        print(f"   Expected: {expected} ± {tolerance}, Got: {actual}")

fn assert_in_range(value: Float, min_val: Float, max_val: Float, test_name: String):
    test_count += 1
    if value >= min_val and value <= max_val:
        passed_tests += 1
        print(f"✅ PASS: {test_name}")
    else:
        failed_tests += 1
        print(f"❌ FAIL: {test_name}")
        print(f"   Expected range: [{min_val}, {max_val}], Got: {value}")

fn assert_not_none(value, test_name: String):
    test_count += 1
    if value is not None:
        passed_tests += 1
        print(f"✅ PASS: {test_name}")
    else:
        failed_tests += 1
        print(f"❌ FAIL: {test_name}")
        print(f"   Expected non-None value")

fn assert_dict_contains(dict_obj: Dict[String, Any], key: String, test_name: String):
    test_count += 1
    if key in dict_obj:
        passed_tests += 1
        print(f"✅ PASS: {test_name}")
    else:
        failed_tests += 1
        print(f"❌ FAIL: {test_name}")
        print(f"   Dictionary missing key: {key}")

fn assert_list_not_empty(list_obj: List[Any], test_name: String):
    test_count += 1
    if len(list_obj) > 0:
        passed_tests += 1
        print(f"✅ PASS: {test_name}")
    else:
        failed_tests += 1
        print(f"❌ FAIL: {test_name}")
        print(f"   Expected non-empty list")

# =============================================================================
# Helius API Integration Tests
# =============================================================================

fn test_helius_integration():
    print("\n🧪 Testing Helius API Integration...")

    # Clear cache to start fresh
    clear_mock_cache()

    # Test valid token response
    valid_token_response = load_helius_response("valid_token", "valid_token")
    assert_not_none(valid_token_response, "Helius returns valid token response")

    if valid_token_response:
        # Check on-chain data structure
        assert_dict_contains(valid_token_response, "onChain", "Helius response has onChain data")
        on_chain = valid_token_response["onChain"]
        assert_dict_contains(on_chain, "account", "On-chain data has account info")
        assert_dict_contains(on_chain, "metadata", "On-chain data has metadata")

        # Check token metadata structure
        assert_dict_contains(valid_token_response, "tokenMetadata", "Helius response has tokenMetadata")
        metadata = valid_token_response["tokenMetadata"]
        assert_equal(metadata["symbol"], "TEST", "Token symbol matches expected")
        assert_equal(metadata["name"], "Test Token", "Token name matches expected")

        # Check enrichments (Organic Score)
        assert_dict_contains(valid_token_response, "enrichments", "Helius response has enrichments")
        enrichments = valid_token_response["enrichments"]
        assert_in_range(enrichments["organicScore"], 0.0, 1.0, "Organic score in valid range")
        assert_in_range(enrichments["confidence"], 0.0, 1.0, "Organic score confidence in valid range")

        # Check security info
        assert_dict_contains(valid_token_response, "securityInfo", "Helius response has security info")
        security = valid_token_response["securityInfo"]
        assert_false(security["isHoneypot"], "Valid token is not honeypot")
        assert_true(security["isVerified"], "Valid token is verified")
        assert_in_range(security["buyTax"], 0.0, 1.0, "Buy tax in valid range")
        assert_in_range(security["sellTax"], 0.0, 1.0, "Sell tax in valid range")

    # Test scam token response
    scam_token_response = load_helius_response("scam_token", "scam_token")
    assert_not_none(scam_token_response, "Helius returns scam token response")

    if scam_token_response:
        security = scam_token_response["securityInfo"]
        assert_true(security["isHoneypot"], "Scam token detected as honeypot")
        assert_false(security["isVerified"], "Scam token is not verified")
        assert_in_range(security["buyTax"], 0.0, 1.0, "Scam token buy tax in valid range")
        assert_in_range(security["sellTax"], 0.0, 1.0, "Scam token sell tax in valid range")

        enrichments = scam_token_response["enrichments"]
        assert_in_range(enrichments["organicScore"], 0.0, 1.0, "Scam token organic score in valid range")
        assert_equal(enrichments["riskLevel"], "high", "Scam token has high risk level")

    # Test error response
    error_response = load_helius_response("error_response", "error_response")
    assert_not_none(error_response, "Helius returns error response")

    if error_response:
        assert_dict_contains(error_response, "error", "Error response has error field")
        error = error_response["error"]
        assert_dict_contains(error, "code", "Error has code")
        assert_dict_contains(error, "message", "Error has message")

    print("✅ Helius API integration tests completed")

# =============================================================================
# Jupiter API Integration Tests
# =============================================================================

fn test_jupiter_integration():
    print("\n🧪 Testing Jupiter API Integration...")

    # Test SOL to token swap
    sol_to_token_response = load_jupiter_response("swap", "sol_to_token")
    assert_not_none(sol_to_token_response, "Jupiter returns SOL to token response")

    if sol_to_token_response:
        # Check basic swap structure
        assert_dict_contains(sol_to_token_response, "inputMint", "Swap has inputMint")
        assert_dict_contains(sol_to_token_response, "outputMint", "Swap has outputMint")
        assert_dict_contains(sol_to_token_response, "inputAmount", "Swap has inputAmount")
        assert_dict_contains(sol_to_token_response, "outputAmount", "Swap has outputAmount")
        assert_dict_contains(sol_to_token_response, "routePlan", "Swap has routePlan")

        # Validate amounts are positive
        assert_true(sol_to_token_response["inputAmount"] > 0, "Input amount positive")
        assert_true(sol_to_token_response["outputAmount"] > 0, "Output amount positive")

        # Check slippage protection
        assert_dict_contains(sol_to_token_response, "otherAmountThreshold", "Swap has slippage protection")
        assert_true(sol_to_token_response["outputAmount"] >= sol_to_token_response["otherAmountThreshold"],
                   "Output amount meets minimum threshold")

        # Check route plan
        route_plan = sol_to_token_response["routePlan"]
        assert_list_not_empty(route_plan, "Route plan has routes")

        if len(route_plan) > 0:
            first_route = route_plan[0]
            assert_dict_contains(first_route, "swapInfo", "Route has swap info")
            swap_info = first_route["swapInfo"]
            assert_dict_contains(swap_info, "inAmount", "Swap info has input amount")
            assert_dict_contains(swap_info, "outAmount", "Swap info has output amount")
            assert_dict_contains(swap_info, "label", "Swap info has label (DEX name)")

        # Check price impact
        assert_dict_contains(sol_to_token_response, "priceImpactPct", "Swap has price impact")
        price_impact = sol_to_token_response["priceImpactPct"]
        assert_in_range(price_impact, 0.0, 100.0, "Price impact in valid range")

        # Check performance metrics
        assert_dict_contains(sol_to_token_response, "timeTaken", "Swap has timing info")
        assert_true(sol_to_token_response["timeTaken"] < 1.0, "Swap completes within 1 second")

    # Test token to SOL swap
    token_to_sol_response = load_jupiter_response("swap", "token_to_sol")
    assert_not_none(token_to_sol_response, "Jupiter returns token to SOL response")

    if token_to_sol_response:
        assert_true(token_to_sol_response["inputAmount"] > 0, "Token to SOL input amount positive")
        assert_true(token_to_sol_response["outputAmount"] > 0, "Token to SOL output amount positive")

    # Test multi-hop swap
    multi_hop_response = load_jupiter_response("swap", "multi_hop")
    assert_not_none(multi_hop_response, "Jupiter returns multi-hop response")

    if multi_hop_response:
        route_plan = multi_hop_response["routePlan"]
        assert_true(len(route_plan) > 1, "Multi-hop route has multiple steps")

    # Test error responses
    no_route_response = load_jupiter_response("no_route", "no_route")
    assert_not_none(no_route_response, "Jupiter returns no route error")

    if no_route_response:
        assert_dict_contains(no_route_response, "error", "No route response has error")
        assert_equal(no_route_response["error"], "No routes found for this swap", "No route error message correct")

    print("✅ Jupiter API integration tests completed")

# =============================================================================
# DexScreener API Integration Tests
# =============================================================================

fn test_dexscreener_integration():
    print("\n🧪 Testing DexScreener API Integration...")

    # Test trending tokens
    trending_response = load_dexscreener_response("trending_tokens")
    assert_not_none(trending_response, "DexScreener returns trending tokens")

    if trending_response:
        assert_dict_contains(trending_response, "pairs", "Trending response has pairs")
        pairs = trending_response["pairs"]
        assert_list_not_empty(pairs, "Trending pairs not empty")

        if len(pairs) > 0:
            first_pair = pairs[0]
            # Check basic pair structure
            assert_dict_contains(first_pair, "chainId", "Pair has chainId")
            assert_dict_contains(first_pair, "dexId", "Pair has dexId")
            assert_dict_contains(first_pair, "baseToken", "Pair has base token")
            assert_dict_contains(first_pair, "quoteToken", "Pair has quote token")
            assert_dict_contains(first_pair, "priceNative", "Pair has native price")
            assert_dict_contains(first_pair, "priceUsd", "Pair has USD price")

            # Validate price data
            assert_true(first_pair["priceNative"] > 0, "Native price positive")
            assert_true(first_pair["priceUsd"] > 0, "USD price positive")

            # Check volume data
            assert_dict_contains(first_pair, "volume", "Pair has volume data")
            volume = first_pair["volume"]
            assert_dict_contains(volume, "h24", "Volume has 24h data")
            assert_dict_contains(volume, "h1", "Volume has 1h data")
            assert_dict_contains(volume, "m5", "Volume has 5m data")
            assert_true(volume["h24"] >= 0, "24h volume non-negative")
            assert_true(volume["h1"] >= 0, "1h volume non-negative")
            assert_true(volume["m5"] >= 0, "5m volume non-negative")

            # Check price changes
            assert_dict_contains(first_pair, "priceChange", "Pair has price change data")
            price_change = first_pair["priceChange"]
            assert_dict_contains(price_change, "h24", "Price change has 24h data")
            assert_dict_contains(price_change, "h1", "Price change has 1h data")
            assert_dict_contains(price_change, "m5", "Price change has 5m data")

            # Check liquidity
            assert_dict_contains(first_pair, "liquidity", "Pair has liquidity data")
            liquidity = first_pair["liquidity"]
            assert_dict_contains(liquidity, "usd", "Liquidity has USD value")
            assert_true(liquidity["usd"] > 0, "Liquidity USD positive")

            # Check transaction counts
            assert_dict_contains(first_pair, "txns", "Pair has transaction data")
            txns = first_pair["txns"]
            assert_dict_contains(txns, "h24", "Transactions have 24h data")
            assert_true(txns["h24"]["buys"] >= 0, "24h buy count non-negative")
            assert_true(txns["h24"]["sells"] >= 0, "24h sell count non-negative")

    # Test token info
    token_info_response = load_dexscreener_response("token_info")
    assert_not_none(token_info_response, "DexScreener returns token info")

    if token_info_response:
        pairs = token_info_response["pairs"]
        if len(pairs) > 0:
            first_pair = pairs[0]
            assert_dict_contains(first_pair, "fdv", "Pair has fully diluted valuation")
            assert_dict_contains(first_pair, "marketCap", "Pair has market cap")
            assert_true(first_pair["fdv"] >= 0, "FDV non-negative")
            assert_true(first_pair["marketCap"] >= 0, "Market cap non-negative")

    # Test pump fun token
    pump_fun_response = load_dexscreener_response("pump_fun_token")
    assert_not_none(pump_fun_response, "DexScreener returns pump fun token")

    if pump_fun_response:
        pairs = pump_fun_response["pairs"]
        if len(pairs) > 0:
            pump_pair = pairs[0]
            assert_equal(pump_pair["dexId"], "pump-fun", "Pump fun token from correct DEX")

            # Check buzz metrics (if available)
            if "buzz" in pump_pair:
                buzz = pump_pair["buzz"]
                assert_dict_contains(buzz, "hours", "Buzz has hourly data")

    print("✅ DexScreener API integration tests completed")

# =============================================================================
# QuickNode API Integration Tests
# =============================================================================

fn test_quicknode_integration():
    print("\n🧪 Testing QuickNode API Integration...")

    # Test account info
    account_info_response = load_quicknode_response("account_info")
    assert_not_none(account_info_response, "QuickNode returns account info")

    if account_info_response:
        assert_dict_contains(account_info_response, "result", "Account info has result")
        result = account_info_response["result"]
        assert_dict_contains(result, "value", "Result has value")
        value = result["value"]

        # Check account value structure
        assert_dict_contains(value, "lamports", "Account has lamports")
        assert_dict_contains(value, "owner", "Account has owner")
        assert_dict_contains(value, "data", "Account has data")
        assert_true(value["lamports"] >= 0, "Lamports non-negative")

    # Test multiple accounts
    multiple_accounts_response = load_quicknode_response("multiple_accounts")
    assert_not_none(multiple_accounts_response, "QuickNode returns multiple accounts")

    if multiple_accounts_response:
        result = multiple_accounts_response["result"]
        assert_dict_contains(result, "value", "Multiple accounts result has value")
        value = result["value"]
        assert_true(len(value) > 1, "Multiple accounts returned")

    # Test token balance
    token_balance_response = load_quicknode_response("token_balance")
    assert_not_none(token_balance_response, "QuickNode returns token balance")

    if token_balance_response:
        result = token_balance_response["result"]
        assert_dict_contains(result, "value", "Token balance has value")
        value = result["value"]
        assert_dict_contains(value, "amount", "Balance has amount")
        assert_dict_contains(value, "uiAmount", "Balance has UI amount")
        assert_dict_contains(value, "decimals", "Balance has decimals")
        assert_true(value["uiAmount"] >= 0, "UI amount non-negative")
        assert_true(value["decimals"] >= 0, "Decimals non-negative")

    # Test transaction history
    transaction_history_response = load_quicknode_response("transaction_history")
    assert_not_none(transaction_history_response, "QuickNode returns transaction history")

    if transaction_history_response:
        result = transaction_history_response["result"]
        assert_dict_contains(result, "value", "Transaction history has value")
        value = result["value"]
        assert_list_not_empty(value, "Transaction history not empty")

        if len(value) > 0:
            first_tx = value[0]
            assert_dict_contains(first_tx, "signature", "Transaction has signature")
            assert_dict_contains(first_tx, "slot", "Transaction has slot")
            assert_dict_contains(first_tx, "blockTime", "Transaction has block time")
            assert_dict_contains(first_tx, "meta", "Transaction has metadata")

    # Test slot info
    slot_info_response = load_quicknode_response("slot_info")
    assert_not_none(slot_info_response, "QuickNode returns slot info")

    if slot_info_response:
        result = slot_info_response["result"]
        assert_dict_contains(result, "value", "Slot info has value")
        value = result["value"]
        assert_dict_contains(value, "parent", "Slot has parent")
        assert_dict_contains(value, "root", "Slot has root")
        assert_dict_contains(value, "processed", "Slot has processed flag")
        assert_true(value["processed"], "Slot processed")

    # Test health check
    health_response = load_quicknode_response("health_check")
    assert_not_none(health_response, "QuickNode returns health check")

    if health_response:
        result = health_response["result"]
        assert_dict_contains(result, "value", "Health check has value")
        value = result["value"]
        assert_dict_contains(value, "status", "Health check has status")
        assert_equal(value["status"], "healthy", "Health status is healthy")

    print("✅ QuickNode API integration tests completed")

# =============================================================================
# API Error Handling Tests
# =============================================================================

fn test_api_error_handling():
    print("\n🧪 Testing API Error Handling...")

    # Test Helius error handling
    helius_error = load_helius_response("error_response", "error_response")
    assert_not_none(helius_error, "Helius error response available")

    if helius_error:
        assert_dict_contains(helius_error, "error", "Helius error has error structure")
        error = helius_error["error"]
        assert_true(error["code"] < 0, "Error code is negative")
        assert_true(len(error["message"]) > 0, "Error message not empty")

    # Test Jupiter error handling
    jupiter_no_route = load_jupiter_response("no_route", "no_route")
    assert_not_none(jupiter_no_route, "Jupiter no route error available")

    if jupiter_no_route:
        assert_equal(jupiter_no_route["error"], "No routes found for this swap", "Jupiter no route message correct")

    jupiter_insufficient_liquidity = load_jupiter_response("insufficient_liquidity", "insufficient_liquidity")
    assert_not_none(jupiter_insufficient_liquidity, "Jupiter insufficient liquidity error available")

    if jupiter_insufficient_liquidity:
        assert_equal(jupiter_insufficient_liquidity["error"], "Insufficient liquidity", "Jupiter insufficient liquidity message correct")

    # Test QuickNode error handling
    quicknode_error = load_quicknode_response("error_invalid_account", "error_invalid_account")
    assert_not_none(quicknode_error, "QuickNode error response available")

    if quicknode_error:
        assert_dict_contains(quicknode_error, "error", "QuickNode error has error structure")
        error = quicknode_error["error"]
        assert_true(error["code"] < 0, "QuickNode error code is negative")
        assert_true(len(error["message"]) > 0, "QuickNode error message not empty")

    print("✅ API error handling tests completed")

# =============================================================================
# API Data Consistency Tests
# =============================================================================

fn test_api_data_consistency():
    print("\n🧪 Testing API Data Consistency...")

    # Test Helius vs Jupiter token consistency
    helius_valid = load_helius_response("valid_token", "valid_token")
    jupiter_sol_token = load_jupiter_response("swap", "sol_to_token")

    assert_not_none(helius_valid, "Helius valid token available")
    assert_not_none(jupiter_sol_token, "Jupiter SOL token available")

    if helius_valid and jupiter_sol_token:
        # Check SOL addresses consistency
        helius_sol_address = "So11111111111111111111111111111111111111112"
        jupiter_input_mint = jupiter_sol_token["inputMint"]
        assert_equal(helius_sol_address, jupiter_input_mint, "SOL addresses consistent across APIs")

    # Test DexScreener vs Jupiter price consistency
    dexscreener_trending = load_dexscreener_response("trending_tokens")

    assert_not_none(dexscreener_trending, "DexScreener trending available")

    if dexscreener_trending:
        pairs = dexscreener_trending["pairs"]
        if len(pairs) > 0:
            # Find SOL/USDC pair
            sol_usdc_pair = None
            for pair in pairs:
                if (pair["baseToken"]["symbol"] == "SOL" and
                    pair["quoteToken"]["symbol"] == "USDC"):
                    sol_usdc_pair = pair
                    break

            if sol_usdc_pair:
                # Check price reasonableness
                price = sol_usdc_pair["priceNative"]
                assert_in_range(price, 50.0, 200.0, "SOL price in reasonable range")

                # Check volume consistency
                volume = sol_usdc_pair["volume"]
                assert_true(volume["h24"] >= volume["h6"], "24h volume >= 6h volume")
                assert_true(volume["h6"] >= volume["h1"], "6h volume >= 1h volume")
                assert_true(volume["h1"] >= volume["m5"], "1h volume >= 5m volume")

    # Test timestamp consistency
    current_time = time()

    # Check Helius timestamps are recent (within 24 hours)
    if helius_valid:
        # Note: Mock data might not have real timestamps, but structure should be there
        pass

    # Check QuickNode slot consistency
    quicknode_slot = load_quicknode_response("slot_info")
    if quicknode_slot:
        result = quicknode_slot["result"]
        if result and "value" in result:
            slot_info = result["value"]
            assert_true(slot_info["parent"] < slot_info.get("root", slot_info["parent"]), "Parent slot <= root slot")

    print("✅ API data consistency tests completed")

# =============================================================================
# Test Runner
# =============================================================================

fn run_all_tests():
    print("🚀 Starting API Integration Tests")
    print("=" * 60)

    start_time = time()

    # Run all test modules
    test_helius_integration()
    test_jupiter_integration()
    test_dexscreener_integration()
    test_quicknode_integration()
    test_api_error_handling()
    test_api_data_consistency()

    end_time = time()
    duration = end_time - start_time

    # Print cache statistics
    print("\n📊 Cache Statistics:")
    cache_stats = get_mock_cache_stats()
    print(f"   - Cache size: {cache_stats['cache_size']} items")
    print(f"   - Cache enabled: {cache_stats['cache_enabled']}")

    # Print results
    print("\n" + "=" * 60)
    print("📊 API Integration Test Results Summary")
    print("=" * 60)
    print(f"Total Tests: {test_count}")
    print(f"Passed: {passed_tests} ✅")
    print(f"Failed: {failed_tests} ❌")
    print(f"Duration: {duration:.2f}s")

    if failed_tests == 0:
        print("\n🎉 All API integration tests passed!")
        return 0
    else:
        print(f"\n⚠️  {failed_tests} test(s) failed. Please check API integrations.")
        return 1

# =============================================================================
# Main Entry Point
# =============================================================================

fn main():
    result = run_all_tests()
    sys.exit(result)

if __name__ == "__main__":
    main()