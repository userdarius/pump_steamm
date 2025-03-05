/// Top level object that tracks all bonding curves.
/// Ensures that there is only one bonding curve of each type.
module pump_steamm::registry;

use std::type_name::TypeName;
use sui::vec_set::{Self, VecSet};
use pump_steamm::global_admin::GlobalAdmin;
use pump_steamm::version::{Self, Version};
use sui::bag::{Self, Bag};
use pump_steamm::bonding_curve::{Self, BondingCurve};
use sui::object::{Self, UID};
use sui::tx_context::{Self, TxContext};

// ===== Constants =====

const CURRENT_VERSION: u16 = 1;

public struct BondingCurveKey has copy, store, drop { bonding_curve_id: ID, coin_type: TypeName }

// ===== Errors =====

const EDuplicatedBondingCurveType: u64 = 1;

public struct Registry has key, store {
    id: UID,
    version: Version,
    bondingCurves: Bag
}

public struct BondingCurveData has copy, drop, store {
    bondingCurve_id: ID,
}


fun init(ctx: &mut TxContext) {
    let registry = Registry {
        id: object::new(ctx),
        version: version::new(CURRENT_VERSION),
        bondingCurves: bag::new(ctx),
    };

    transfer::share_object(registry);
}

public(package) fun register_bonding_curve(
        registry: &mut Registry,
        bonding_curve_id: ID,
        coin_type: TypeName
    ) {
        registry.version.assert_version_and_upgrade(CURRENT_VERSION);
        let key = BondingCurveKey { bonding_curve_id, coin_type};

        assert!(!registry.bondingCurves.contains(key), EDuplicatedBondingCurveType);

        let data = BondingCurveData { bondingCurve_id: bonding_curve_id };
        registry.bondingCurves.add(key, data);
    }

// ===== Versioning =====

entry fun migrate(registry: &mut Registry, _admin: &GlobalAdmin) {
    registry.version.migrate_(CURRENT_VERSION);
}

// ===== Tests =====

#[test_only]
public fun init_for_testing(ctx: &mut TxContext): Registry {
    let registry = Registry {
        id: object::new(ctx),
        version: version::new(CURRENT_VERSION),
        bondingCurves: bag::new(ctx),
    };

    registry
}
