module pump_steamm::bonding_curve;

use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};
use sui::balance::{Self, Balance};
use sui::transfer;
use std::type_name::TypeName;
use sui::tx_context::{Self, TxContext};
use sui::object::{Self, UID};
use sui::sui::SUI;
use std::string::{String, utf8};
use sui::url::Url;
use std::option;
use pump_steamm::version::{Self, Version};
use pump_steamm::events::{Self, emit_event};
use pump_steamm::registry::Registry;
use sui::math;


// Constants
const CURRENT_VERSION: u16 = 1;
const TOTAL_SUPPLY: u64 = 1_000_000_000_000_000; // 1 billion tokens with 6 decimals
const INITIAL_VIRTUAL_SUI: u64 = 30_000_000; // 30 SUI with 6 decimals
const INITIAL_VIRTUAL_TOKENS: u64 = 1_073_000_191_000_000; // 1,073,000,191 tokens with 6 decimals
const K: u128 = 32_190_005_730_000_000_000_000; // Constant product k
const LISTING_THRESHOLD: u64 = 69_000_000_000; // $69,000 in SUI 

// Errors
const EInsufficientLiquidity: u64 = 0;
const ETransitionedToAMM: u64 = 1;
const EInvalidAmount: u64 = 2;
const a = 1_000_000_000;
const b = 30;

// Events
public struct NewBondingCurveResult has copy, drop, store {
    bonding_curve_id: ID,
    coin_type: TypeName,
}

/// Bonding curve configuration and state
public struct BondingCurve<phantom T> has key {
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
public fun create_token<T: drop>(
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
        sui_reserves: balance::zero(),
        creator: tx_context::sender(ctx),
        transitioned: false,
        version: version::new(CURRENT_VERSION),
    };

    let event = NewBondingCurveResult { bonding_curve_id: object::id(&bonding_curve), coin_type: T::type_name() }; // FIX THIS

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
    
    mint_tokens(bonding_curve, tokens_to_mint, ctx);
    update_reserves(bonding_curve, payment);
    
    bonding_curve.virtual_sui_reserves += amount;
    bonding_curve.virtual_token_reserves -= tokens_to_mint;
    
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
    
    burn_tokens(bonding_curve, tokens);
    send_sui(bonding_curve, sui_amount, ctx);
    
    bonding_curve.virtual_sui_reserves -= sui_amount;
    bonding_curve.virtual_token_reserves += amount;
}

fun calculate_tokens_to_mint<T>(bonding_curve: &BondingCurve<T>, sui_amount: u64): u64 {
    let x = (bonding_curve.virtual_sui_reserves as u128) + (sui_amount as u128);
    let y = INITIAL_VIRTUAL_TOKENS as u128 - (K / (INITIAL_VIRTUAL_SUI as u128 + x));
    (y as u64) - bonding_curve.virtual_token_reserves
}

fun calculate_sui_to_receive<T>(bonding_curve: &BondingCurve<T>, token_amount: u64): u64 {
    let y = (bonding_curve.virtual_token_reserves as u128) + (token_amount as u128);
    let x = (K / (INITIAL_VIRTUAL_TOKENS as u128 - y)) - (INITIAL_VIRTUAL_SUI as u128);
    bonding_curve.virtual_sui_reserves - (x as u64)
}

fun check_transition<T>(bonding_curve: &mut BondingCurve<T>) {
    if (bonding_curve.sui_reserves >= LISTING_THRESHOLD) {
        bonding_curve.transitioned = true;
        // TODO: Initialize AMM pool with remaining liquidity
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
    let amount = coin::value(&payment);
    bonding_curve.sui_reserves = balance::add(&mut bonding_curve.sui_reserves, amount); // FIX THIS 
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
