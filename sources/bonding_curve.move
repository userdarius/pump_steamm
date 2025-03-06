module pump_steamm::bonding_curve;

use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};
use sui::balance::{Self, Balance};
use sui::transfer;
use std::type_name::TypeName;
use std::type_name;
use sui::tx_context::{Self, TxContext};
use sui::object::{Self, UID};
use sui::sui::SUI;
use std::string::{String, utf8};
use sui::url::Url;
use std::option;
use pump_steamm::version::{Self, Version};
use pump_steamm::events::{Self, emit_event};
use pump_steamm::registry::Registry;
use pump_steamm::global_admin::GlobalAdmin;
use sui::math;


// Constants
const CURRENT_VERSION: u16 = 1;
const MAX_SUPPLY: u64 = 1_000_000_000_000_000_000; // 1 billion tokens with 9 decimals

// Updated constants to match the working simulation but with 9 decimals
const INITIAL_VIRTUAL_SUI: u64 = 30_000_000_000; // 30 SUI with 9 decimals
const INITIAL_VIRTUAL_TOKENS: u64 = 1_000_000_000_000_000; // 1 million tokens with 9 decimals
// K = INITIAL_VIRTUAL_SUI * INITIAL_VIRTUAL_TOKENS (calculated at runtime)
const LISTING_THRESHOLD: u64 = 69_000_000_000; // 69 SUI with 9 decimals

// Errors
const EInsufficientLiquidity: u64 = 0;
const ETransitionedToAMM: u64 = 1;
const EInvalidAmount: u64 = 2;  
const ENotAuthorized: u64 = 3;
const ENegativeTokenMinting: u64 = 4;

// Events
public struct NewBondingCurveResult has copy, drop {
    bonding_curve_id: ID,
    coin_type: TypeName,
}

public struct TransitionToAMMResult has copy, drop {
    bonding_curve_id: ID,
    virtual_sui_reserves: u64,
    virtual_token_reserves: u64,
}

// Event for buy transaction
public struct BuyResult has copy, drop {
    bonding_curve_id: ID,
    sui_amount: u64,
    tokens_minted: u64,
}

// Event for sell transaction
public struct SellResult has copy, drop {
    bonding_curve_id: ID,
    token_amount: u64,
    sui_received: u64,
}

/// Bonding curve configuration and state
public struct BondingCurve<phantom T> has key, store {
    id: UID,
    treasury_cap: TreasuryCap<T>,
    metadata: CoinMetadata<T>,
    total_minted: u64,
    virtual_sui_reserves: u64,
    virtual_token_reserves: u64,   
    sui_reserves: Balance<SUI>, 
    creator: address,
    transitioned: bool,
    version: Version
}

/// Initialize new bonding curve token
public fun create_token<T: drop + store>(
    registry: &mut Registry,
    creator: T,
    name: vector<u8>,
    symbol: vector<u8>,
    description: vector<u8>,
    image_url: Option<Url>,
    ctx: &mut TxContext
): BondingCurve<T> {

    let (treasury_cap, metadata) = coin::create_currency<T>(
        creator,
        9, // Decimals
        name,
        symbol,
        description,

        image_url, 
        ctx,
    );

    let bonding_curve = BondingCurve {
        id: object::new(ctx),
        treasury_cap: treasury_cap,
        metadata: metadata,
        total_minted: 0,
        virtual_sui_reserves: INITIAL_VIRTUAL_SUI,
        virtual_token_reserves: 0, // Start with 0 tokens in reserve to match working simulation
        sui_reserves: balance::zero(),
        creator: tx_context::sender(ctx),
        transitioned: false,
        version: version::new(CURRENT_VERSION),
    };

    let event = NewBondingCurveResult { bonding_curve_id: object::id(&bonding_curve), coin_type: type_name::get<T>() };

    emit_event(event);

    registry.register_bonding_curve( event.bonding_curve_id, event.coin_type);

    bonding_curve
}

/// Buy tokens through bonding curve
public entry fun buy<T>(
    bonding_curve: &mut BondingCurve<T>,
    payment: Coin<SUI>,
    ctx: &mut TxContext
) {
    assert!(!bonding_curve.transitioned, ETransitionedToAMM);
    
    let amount = coin::value(&payment);
    let tokens_to_mint = calculate_tokens_to_mint(bonding_curve, amount);
    
    // Ensure tokens_to_mint is positive
    assert!(tokens_to_mint > 0, ENegativeTokenMinting);
    
    mint_tokens(bonding_curve, tokens_to_mint, ctx);
    update_reserves(bonding_curve, payment);
    
    bonding_curve.virtual_sui_reserves = bonding_curve.virtual_sui_reserves + amount;
    bonding_curve.virtual_token_reserves = bonding_curve.virtual_token_reserves + tokens_to_mint;
    
    // Emit buy event
    let event = BuyResult {
        bonding_curve_id: object::id(bonding_curve),
        sui_amount: amount,
        tokens_minted: tokens_to_mint,
    };
    emit_event(event);
    
    check_transition(bonding_curve);
}

/// Sell tokens back through bonding curve
public entry fun sell<T>(
    bonding_curve: &mut BondingCurve<T>,
    tokens: Coin<T>,
    ctx: &mut TxContext
) {
    assert!(!bonding_curve.transitioned, ETransitionedToAMM);
    
    let amount = coin::value(&tokens);
    let sui_amount = calculate_sui_to_receive(bonding_curve, amount);
    
    // Ensure sui_amount is positive
    assert!(sui_amount > 0, EInvalidAmount);
    
    burn_tokens(bonding_curve, tokens);
    send_sui(bonding_curve, sui_amount, ctx);
    
    bonding_curve.virtual_sui_reserves = bonding_curve.virtual_sui_reserves - sui_amount;
    bonding_curve.virtual_token_reserves = bonding_curve.virtual_token_reserves - amount;
    
    // Emit sell event
    let event = SellResult {
        bonding_curve_id: object::id(bonding_curve),
        token_amount: amount,
        sui_received: sui_amount,
    };
    emit_event(event);
}

/// Calculate tokens to mint based on SUI amount
fun calculate_tokens_to_mint<T>(bonding_curve: &BondingCurve<T>, sui_amount: u64): u64 {
    // Calculate constant product K as INITIAL_VIRTUAL_SUI * INITIAL_VIRTUAL_TOKENS
    let k = (INITIAL_VIRTUAL_SUI as u128) * (INITIAL_VIRTUAL_TOKENS as u128);
    
    // Calculate new virtual SUI amount
    let x = (bonding_curve.virtual_sui_reserves as u128) + (sui_amount as u128);
    
    // Calculate what the token supply should be after purchase using the formula:
    // new_token_supply = INITIAL_VIRTUAL_TOKENS - (K / x)
    let new_token_supply = (INITIAL_VIRTUAL_TOKENS as u128) - (k / x);
    
    // Tokens to mint is the difference between new supply and current virtual tokens
    if (new_token_supply > (bonding_curve.virtual_token_reserves as u128)) {
        (new_token_supply - (bonding_curve.virtual_token_reserves as u128) as u64)
    } else {
        0 // No tokens minted if calculation would result in a negative number
    }
}

/// Calculate SUI to receive based on token amount
fun calculate_sui_to_receive<T>(bonding_curve: &BondingCurve<T>, token_amount: u64): u64 {
    // Calculate constant product K as INITIAL_VIRTUAL_SUI * INITIAL_VIRTUAL_TOKENS
    let k = (INITIAL_VIRTUAL_SUI as u128) * (INITIAL_VIRTUAL_TOKENS as u128);
    
    // Calculate new virtual token amount
    let new_virtual_tokens = (bonding_curve.virtual_token_reserves as u128) + (token_amount as u128);
    
    // Check if we would exceed the initial token supply
    if (new_virtual_tokens >= (INITIAL_VIRTUAL_TOKENS as u128)) {
        return 0
    };
    
    // Calculate what the SUI reserves should be after the sale using the formula:
    // new_sui_amount = K / (INITIAL_VIRTUAL_TOKENS - new_virtual_tokens)
    let new_sui_amount = k / ((INITIAL_VIRTUAL_TOKENS as u128) - new_virtual_tokens);
    
    // SUI to receive is the difference between current virtual SUI and new SUI amount
    if ((bonding_curve.virtual_sui_reserves as u128) > new_sui_amount) {
        ((bonding_curve.virtual_sui_reserves as u128) - new_sui_amount as u64)
    } else {
        0 // No SUI received if calculation would result in a negative number
    }
}

/// Check if the bonding curve should transition to AMM
fun check_transition<T>(bonding_curve: &mut BondingCurve<T>) {
    if (!bonding_curve.transitioned && bonding_curve.virtual_sui_reserves >= LISTING_THRESHOLD) {
        // Transition to AMM
        bonding_curve.transitioned = true;
        
        // Calculate constant product K as virtual_sui_reserves * virtual_token_reserves
        // This will set the initial AMM k to the current state
        
        // Emit transition event
        let event = TransitionToAMMResult {
            bonding_curve_id: object::id(bonding_curve),
            virtual_sui_reserves: bonding_curve.virtual_sui_reserves,
            virtual_token_reserves: bonding_curve.virtual_token_reserves,
        };
        
        emit_event(event);
    }
}

fun mint_tokens<T>(
    bonding_curve: &mut BondingCurve<T>,
    amount: u64,
    ctx: &mut TxContext
) {
    let new_total = bonding_curve.total_minted + amount;
    assert!(new_total <= MAX_SUPPLY, EInvalidAmount);
    
    let tokens = coin::mint(&mut bonding_curve.treasury_cap, amount, ctx);
    transfer::public_transfer(tokens, tx_context::sender(ctx));
    bonding_curve.total_minted = new_total;
}

fun burn_tokens<T>(
    bonding_curve: &mut BondingCurve<T>,
    tokens: Coin<T>
) {
    let amount = coin::value(&tokens);
    bonding_curve.total_minted = bonding_curve.total_minted - amount;
    coin::burn(&mut bonding_curve.treasury_cap, tokens);
}

fun update_reserves<T>(
    bonding_curve: &mut BondingCurve<T>,
    payment: Coin<SUI>
) {
    let payment_balance = coin::into_balance(payment);
    balance::join(&mut bonding_curve.sui_reserves, payment_balance); 
}

fun send_sui<T>(
    bonding_curve: &mut BondingCurve<T>,
    amount: u64,
    ctx: &mut TxContext
) {
    let balance = &mut bonding_curve.sui_reserves;
    assert!(balance::value(balance) >= amount, EInsufficientLiquidity);
    
    let sui = coin::take(balance, amount, ctx);
    transfer::public_transfer(sui, tx_context::sender(ctx));
}



/// Admin-only function to withdraw collected fees
public entry fun withdraw_fees<T>(
    bonding_curve: &mut BondingCurve<T>,
    admin: &GlobalAdmin,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext
) {
    // Only the admin can call this function
    assert!(tx_context::sender(ctx) == object::id_address(admin), ENotAuthorized);
    
    // Calculate fee - can add a proper fee mechanism here
    let fee_amount = amount;
    assert!(balance::value(&bonding_curve.sui_reserves) >= fee_amount, EInsufficientLiquidity);
    
    // Send fee to recipient
    let sui = coin::take(&mut bonding_curve.sui_reserves, fee_amount, ctx);
    transfer::public_transfer(sui, recipient);
}

/// Admin-only function to perform maintenance operations
public entry fun perform_maintenance<T>(
    bonding_curve: &mut BondingCurve<T>,
    admin: &GlobalAdmin,
    ctx: &mut TxContext
) {
    // Only the admin can call this function
    assert!(tx_context::sender(ctx) == object::id_address(admin), ENotAuthorized);
    
    // Implement maintenance operations here
    // For example:
    // - Update curve parameters
    // - Adjust virtual reserves
    // - Update versions
}

/// Admin-only function to update curve parameters
public entry fun update_parameters<T>(
    bonding_curve: &mut BondingCurve<T>,
    admin: &GlobalAdmin,
    new_virtual_sui: Option<u64>,
    new_virtual_tokens: Option<u64>,
    ctx: &mut TxContext
) {
    // Only the admin can call this function
    assert!(tx_context::sender(ctx) == object::id_address(admin), ENotAuthorized);
    
    // Update virtual reserves if provided
    if (option::is_some(&new_virtual_sui)) {
        bonding_curve.virtual_sui_reserves = option::destroy_some(new_virtual_sui);
    };
    
    if (option::is_some(&new_virtual_tokens)) {
        bonding_curve.virtual_token_reserves = option::destroy_some(new_virtual_tokens);
    };
}

/// Accessors for testing
#[test_only]
public fun get_total_minted<T>(bonding_curve: &BondingCurve<T>): u64 {
    bonding_curve.total_minted
}

#[test_only]
public fun get_virtual_sui_reserves<T>(bonding_curve: &BondingCurve<T>): u64 {
    bonding_curve.virtual_sui_reserves
}

#[test_only]
public fun get_virtual_token_reserves<T>(bonding_curve: &BondingCurve<T>): u64 {
    bonding_curve.virtual_token_reserves
}

#[test_only]
public fun is_transitioned<T>(bonding_curve: &BondingCurve<T>): bool {
    bonding_curve.transitioned
}

/// Create a bonding curve for testing purposes
#[test_only]
public fun create_for_testing<T: drop + store>(
    registry: &mut Registry,
    treasury_cap: TreasuryCap<T>,
    metadata: CoinMetadata<T>,
    ctx: &mut TxContext
): BondingCurve<T> {
    let bonding_curve = BondingCurve {
        id: object::new(ctx),
        treasury_cap,
        metadata,
        total_minted: 0,
        virtual_sui_reserves: INITIAL_VIRTUAL_SUI,
        virtual_token_reserves: 0, // Start with 0 tokens in reserve to match working simulation
        sui_reserves: balance::zero(),
        creator: tx_context::sender(ctx),
        transitioned: false,
        version: version::new(CURRENT_VERSION),
    };

    let bonding_curve_id = object::id(&bonding_curve);
    let coin_type = type_name::get<T>();
    
    registry.register_bonding_curve(bonding_curve_id, coin_type);

    bonding_curve
}

/// Create a simplified version of BondingCurve for testing
#[test_only]
public struct MockBondingCurve has key, store {
    id: UID,
    total_minted: u64,
    virtual_sui_reserves: u64,
    virtual_token_reserves: u64,   
    sui_reserves: Balance<SUI>, 
    creator: address,
    transitioned: bool,
    version: Version
}

/// Create a mock bonding curve for testing purposes without requiring a treasury cap or metadata
#[test_only]
public fun create_for_testing_mock(
    registry: &mut Registry,
    ctx: &mut TxContext
): MockBondingCurve {
    let mock_bonding_curve = MockBondingCurve {
        id: object::new(ctx),
        total_minted: 0,
        virtual_sui_reserves: INITIAL_VIRTUAL_SUI,
        virtual_token_reserves: 0, // Start with 0 tokens in reserve to match working simulation
        sui_reserves: balance::zero(),
        creator: tx_context::sender(ctx),
        transitioned: false,
        version: version::new(CURRENT_VERSION),
    };

    let bonding_curve_id = object::id(&mock_bonding_curve);
    // Use a dummy type name since it's just for testing
    let coin_type = type_name::get<SUI>();
    
    registry.register_bonding_curve(bonding_curve_id, coin_type);

    mock_bonding_curve
}

#[test_only]
public fun get_virtual_sui_reserves_mock(bonding_curve: &MockBondingCurve): u64 {
    bonding_curve.virtual_sui_reserves
}

#[test_only]
public fun get_virtual_token_reserves_mock(bonding_curve: &MockBondingCurve): u64 {
    bonding_curve.virtual_token_reserves
}

#[test_only]
public fun get_total_minted_mock(bonding_curve: &MockBondingCurve): u64 {
    bonding_curve.total_minted
}

#[test_only]
public fun is_transitioned_mock(bonding_curve: &MockBondingCurve): bool {
    bonding_curve.transitioned
}