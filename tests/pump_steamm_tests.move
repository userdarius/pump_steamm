#[test_only]
module pump_steamm::pump_steamm_tests {
    use sui::test_scenario::{Self as ts};
    use sui::coin::{Self};
    use sui::sui::SUI;
    use sui::transfer;
    use std::option;
    
    use pump_steamm::bonding_curve::{Self};
    use pump_steamm::registry::{Self};
    
    // Constants for testing
    const INITIAL_VIRTUAL_SUI: u64 = 30_000_000; // 30 SUI with 6 decimals
    const INITIAL_VIRTUAL_TOKENS: u64 = 1_073_000_191_000_000; // 1,073,000,191 tokens with 6 decimals
    const TEST_ADDR: address = @0xA;
    
    // Simple struct for testing
    public struct TEST_TOKEN has drop {}
    
    #[test]
    fun test_math() {
        assert!(1 + 1 == 2, 0);
    }
    
    #[test]
    fun test_scenario_basics() {
        // Create a test scenario
        let mut scenario = ts::begin(TEST_ADDR);
        
        // First transaction
        {
            let ctx = ts::ctx(&mut scenario);
            // Just verify we can get a context
            assert!(ts::sender(&scenario) == TEST_ADDR, 0);
        };
        
        // End the scenario
        ts::end(scenario);
    }
    
    #[test]
    fun test_bonding_curve_default_values() {
        // Create a test scenario
        let mut scenario = ts::begin(TEST_ADDR);
        
        // First transaction
        {
            let ctx = ts::ctx(&mut scenario);
            
            // Create registry
            let mut registry = registry::init_for_testing(ctx);
            
            // Create a mock bonding curve for testing
            let bonding_curve = bonding_curve::create_for_testing_mock(
                &mut registry,
                ctx
            );
            
            // Verify the initial state of the bonding curve using mock accessors
            assert!(bonding_curve::get_virtual_sui_reserves_mock(&bonding_curve) == INITIAL_VIRTUAL_SUI, 0);
            assert!(bonding_curve::get_virtual_token_reserves_mock(&bonding_curve) == INITIAL_VIRTUAL_TOKENS, 0);
            assert!(bonding_curve::is_transitioned_mock(&bonding_curve) == false, 0);
            
            // Clean up
            transfer::public_share_object(registry);
            transfer::public_transfer(bonding_curve, TEST_ADDR);
        };
        
        ts::end(scenario);
    }
    
    #[test]
    fun test_bonding_curve_accessors() {
        // Create a test scenario
        let mut scenario = ts::begin(TEST_ADDR);
        
        // First transaction
        {
            let ctx = ts::ctx(&mut scenario);
            
            // Create registry
            let mut registry = registry::init_for_testing(ctx);
            
            // Create a mock bonding curve for testing
            let bonding_curve = bonding_curve::create_for_testing_mock(
                &mut registry,
                ctx
            );
            
            // Verify the initial state of the bonding curve using mock accessor functions
            assert!(bonding_curve::get_total_minted_mock(&bonding_curve) == 0, 0);
            assert!(bonding_curve::get_virtual_sui_reserves_mock(&bonding_curve) == INITIAL_VIRTUAL_SUI, 0);
            assert!(bonding_curve::get_virtual_token_reserves_mock(&bonding_curve) == INITIAL_VIRTUAL_TOKENS, 0);
            assert!(bonding_curve::is_transitioned_mock(&bonding_curve) == false, 0);
            
            // Clean up
            transfer::public_share_object(registry);
            transfer::public_transfer(bonding_curve, TEST_ADDR);
        };
        
        ts::end(scenario);
    }
} 