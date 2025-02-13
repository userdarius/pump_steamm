module pump_steamm::admin_cap;

public struct AdminCap has key { id: UID }

fun init(ctx: &mut TxContext) {
    transfer::transfer(
        AdminCap { id: object::new(ctx) },
        ctx.sender()
    )
}