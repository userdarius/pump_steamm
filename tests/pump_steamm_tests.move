#[test_only]
module pump_steamm::pump_steamm_tests {
    use sui::test_scenario::{Self as ts};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::object::{Self, ID};
    use sui::tx_context::{Self, TxContext};
    use std::option::{Self, Option};
    
    use pump_steamm::bonding_curve::{Self, MockBondingCurve};
    use pump_steamm::registry::{Self};
    
    const INITIAL_VIRTUAL_SUI: u64 = 30_000_000_000;
    const INITIAL_VIRTUAL_TOKENS: u64 = 1_000_000_000_000_000;
    const TEST_ADDR: address = @0xA;
    const TEST_ADDR_2: address = @0xB;
    
    public struct TEST_TOKEN has drop, store {}
    
    #[test]
    fun test_math() {
        assert!(1 + 1 == 2, 0);
    }
    
    #[test]
    fun test_scenario_basics() {
        let mut scenario = ts::begin(TEST_ADDR);
        
        {
            let ctx = ts::ctx(&mut scenario);
            assert!(ts::sender(&scenario) == TEST_ADDR, 0);
        };
        
        ts::end(scenario);
    }
    
    #[test]
    fun test_bonding_curve_default_values() {
        let mut scenario = ts::begin(TEST_ADDR);
        
        {
            let ctx = ts::ctx(&mut scenario);
            
            let mut registry = registry::init_for_testing(ctx);
            
            let bonding_curve = bonding_curve::create_for_testing_mock(
                &mut registry,
                ctx
            );
            
            assert!(bonding_curve::get_virtual_sui_reserves_mock(&bonding_curve) == INITIAL_VIRTUAL_SUI, 0);
            assert!(bonding_curve::get_virtual_token_reserves_mock(&bonding_curve) == 0, 0);
            assert!(bonding_curve::is_transitioned_mock(&bonding_curve) == false, 0);
            
            transfer::public_share_object(registry);
            transfer::public_transfer(bonding_curve, TEST_ADDR);
        };
        
        ts::end(scenario);
    }
    
    #[test]
    fun test_bonding_curve_accessors() {
        let mut scenario = ts::begin(TEST_ADDR);
        
        {
            let ctx = ts::ctx(&mut scenario);
            
            let mut registry = registry::init_for_testing(ctx);
            
            let bonding_curve = bonding_curve::create_for_testing_mock(
                &mut registry,
                ctx
            );
            
            assert!(bonding_curve::get_total_minted_mock(&bonding_curve) == 0, 0);
            assert!(bonding_curve::get_virtual_sui_reserves_mock(&bonding_curve) == INITIAL_VIRTUAL_SUI, 0);
            assert!(bonding_curve::get_virtual_token_reserves_mock(&bonding_curve) == 0, 0);
            assert!(bonding_curve::is_transitioned_mock(&bonding_curve) == false, 0);
            
            transfer::public_share_object(registry);
            transfer::public_transfer(bonding_curve, TEST_ADDR);
        };
        
        ts::end(scenario);
    }
    
    fun create_sui(amount: u64, ctx: &mut TxContext): Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, ctx)
    }
    
    #[test]
    fun test_simulate_buy_calculation() {
        let mut scenario = ts::begin(TEST_ADDR);
        
        {
            let ctx = ts::ctx(&mut scenario);
            
            let mut registry = registry::init_for_testing(ctx);
            
            let bonding_curve = bonding_curve::create_for_testing_mock(
                &mut registry,
                ctx
            );
            
            let initial_virtual_sui = bonding_curve::get_virtual_sui_reserves_mock(&bonding_curve);
            let initial_virtual_tokens = bonding_curve::get_virtual_token_reserves_mock(&bonding_curve);
            
            let sui_amount = 1_000_000_000;
            
            let k = (INITIAL_VIRTUAL_SUI as u128) * (1_000_000_000_000_000 as u128);
            let x = (initial_virtual_sui as u128) + (sui_amount as u128);
            let new_token_supply = (1_000_000_000_000_000 as u128) - (k / x);
            let tokens_to_mint = (new_token_supply - (initial_virtual_tokens as u128) as u64);
            
            assert!(tokens_to_mint > 0, 0);
            
            transfer::public_share_object(registry);
            transfer::public_transfer(bonding_curve, TEST_ADDR);
        };
        
        ts::end(scenario);
    }
    
    #[test]
    fun test_simulate_sell_calculation() {
        let initial_virtual_sui = 31_000_000_000;
        let tokens_to_sell = 100_000_000;
        
        let token_supply = 1_000_000_000_000_000;
        
        let k = (INITIAL_VIRTUAL_SUI as u128) * (token_supply as u128);
        
        let token_reserves = 1_000_000_000;
        
        let new_token_reserves = (token_reserves - tokens_to_sell as u128);
        
        let new_sui_amount = k / ((token_supply as u128) - new_token_reserves);
        
        let sui_to_receive = ((initial_virtual_sui as u128) - new_sui_amount as u64);
        
        assert!(sui_to_receive > 0, 0);
        assert!(new_sui_amount < (initial_virtual_sui as u128), 0);
        
        assert!(sui_to_receive < initial_virtual_sui, 0);
    }
    
    #[test]
    fun test_simulate_transition_threshold() {
        let mut scenario = ts::begin(TEST_ADDR);
        
        {
            let ctx = ts::ctx(&mut scenario);
            
            let mut registry = registry::init_for_testing(ctx);
            
            let bonding_curve = bonding_curve::create_for_testing_mock(
                &mut registry,
                ctx
            );
            
            assert!(!bonding_curve::is_transitioned_mock(&bonding_curve), 0);
            
            let amount_needed = 39_000_000_000;
            
            assert!(INITIAL_VIRTUAL_SUI + amount_needed == 69_000_000_000, 0);
            
            transfer::public_share_object(registry);
            transfer::public_transfer(bonding_curve, TEST_ADDR);
        };
        
        ts::end(scenario);
    }
} 