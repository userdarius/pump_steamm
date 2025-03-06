import numpy as np
import matplotlib.pyplot as plt
from decimal import Decimal, getcontext

# Set high precision for decimal calculations
getcontext().prec = 40

# Constants from Move module (adjusted for simulation)
INITIAL_VIRTUAL_SUI = Decimal("30")  # 30 SUI
INITIAL_VIRTUAL_TOKENS = Decimal("1000000")  # 1M tokens
K = INITIAL_VIRTUAL_SUI * INITIAL_VIRTUAL_TOKENS  # Constant product k
LISTING_THRESHOLD = Decimal("69")  # 69 SUI for transition to AMM


def calculate_tokens_to_mint(virtual_sui, virtual_tokens, sui_amount):
    """
    Calculate how many tokens will be minted for a given SUI amount

    From the Move code:
    let x = (bonding_curve.virtual_sui_reserves as u128) + (sui_amount as u128);
    let y = INITIAL_VIRTUAL_TOKENS as u128 - (K / x);
    (y as u64) - bonding_curve.virtual_token_reserves
    """
    # First, calculate the new virtual SUI amount after adding the purchase amount
    x = virtual_sui + sui_amount

    # Calculate what the token supply should be after the purchase
    # This is the key formula from the Move code
    new_token_supply = INITIAL_VIRTUAL_TOKENS - (K / x)

    # Tokens to mint is the difference between what we should have and what we currently have
    tokens_to_mint = new_token_supply - virtual_tokens

    return max(Decimal("0"), tokens_to_mint)


def calculate_sui_to_receive(virtual_sui, virtual_tokens, token_amount):
    """
    Calculate how much SUI will be received for a given token amount

    From the Move code:
    let y = (bonding_curve.virtual_token_reserves as u128) + (token_amount as u128);
    let x = (K / (INITIAL_VIRTUAL_TOKENS as u128 - y)) - (INITIAL_VIRTUAL_SUI as u128);
    bonding_curve.virtual_sui_reserves - (x as u64)
    """
    # First, calculate the new virtual token amount
    new_virtual_tokens = virtual_tokens + token_amount

    # Check if we would exceed the initial token supply
    if new_virtual_tokens >= INITIAL_VIRTUAL_TOKENS:
        return Decimal("0")

    # Calculate what the SUI reserves should be after the sale
    # This is the key formula from the Move code
    x = K / (INITIAL_VIRTUAL_TOKENS - new_virtual_tokens)

    # SUI to receive is the difference between current virtual SUI and new SUI amount
    sui_to_receive = virtual_sui - x

    return max(Decimal("0"), sui_to_receive)


def calculate_price(virtual_tokens):
    """Calculate token price in SUI at current point"""
    denominator = INITIAL_VIRTUAL_TOKENS - virtual_tokens

    if denominator <= Decimal("0"):
        return Decimal("0")

    price = K / (denominator * denominator)
    return price


def simulate_buy_transaction(virtual_sui, virtual_tokens, sui_amount):
    """Simulate a buy transaction and return new state"""
    tokens_to_mint = calculate_tokens_to_mint(virtual_sui, virtual_tokens, sui_amount)

    if tokens_to_mint <= Decimal("0"):
        print(f"No tokens would be minted for {sui_amount} SUI")
        return virtual_sui, virtual_tokens, Decimal("0")

    new_virtual_sui = virtual_sui + sui_amount
    new_virtual_tokens = virtual_tokens + tokens_to_mint

    print(f"Buy {sui_amount} SUI -> Mint {tokens_to_mint} tokens")
    print(f"  New virtual SUI: {new_virtual_sui}")
    print(f"  New virtual tokens: {new_virtual_tokens}")
    print(f"  New price: {calculate_price(new_virtual_tokens)}")

    return new_virtual_sui, new_virtual_tokens, tokens_to_mint


def simulate_sell_transaction(virtual_sui, virtual_tokens, token_amount):
    """Simulate a sell transaction and return new state"""
    sui_to_receive = calculate_sui_to_receive(virtual_sui, virtual_tokens, token_amount)

    if sui_to_receive <= Decimal("0"):
        print(f"No SUI would be received for {token_amount} tokens")
        return virtual_sui, virtual_tokens, Decimal("0")

    new_virtual_sui = virtual_sui - sui_to_receive
    new_virtual_tokens = virtual_tokens - token_amount

    print(f"Sell {token_amount} tokens -> Receive {sui_to_receive} SUI")
    print(f"  New virtual SUI: {new_virtual_sui}")
    print(f"  New virtual tokens: {new_virtual_tokens}")
    print(f"  New price: {calculate_price(new_virtual_tokens)}")

    return new_virtual_sui, new_virtual_tokens, sui_to_receive


def plot_bonding_curve():
    """Plot the bonding curve price function"""
    # Create a range of SUI values to plot
    sui_range = np.linspace(0, float(LISTING_THRESHOLD) * 1.5, 1000)

    # Calculate token price and supply at each point
    prices = []
    token_supply = []

    virtual_sui = INITIAL_VIRTUAL_SUI
    virtual_tokens = Decimal("0")  # Start with 0 tokens

    for sui in sui_range:
        # Calculate tokens that would be minted
        tokens = calculate_tokens_to_mint(
            virtual_sui, virtual_tokens, Decimal(str(sui))
        )

        # Update virtual reserves
        virtual_sui += Decimal(str(sui))
        virtual_tokens += tokens

        # Calculate price at this point
        price = calculate_price(virtual_tokens)

        # Store results
        prices.append(float(price))
        token_supply.append(float(virtual_tokens))

    # Create the plots
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 12))

    # Price curve
    ax1.plot(sui_range, prices)
    ax1.set_title("Token Price vs. SUI Invested")
    ax1.set_xlabel("Cumulative SUI Invested")
    ax1.set_ylabel("Token Price (in SUI)")
    ax1.axvline(
        x=float(LISTING_THRESHOLD), color="g", linestyle="--", label="Listing Threshold"
    )
    ax1.grid(True)
    ax1.legend()

    # Token supply curve
    ax2.plot(sui_range, token_supply)
    ax2.set_title("Token Supply vs. SUI Invested")
    ax2.set_xlabel("Cumulative SUI Invested")
    ax2.set_ylabel("Token Supply")
    ax2.axvline(
        x=float(LISTING_THRESHOLD), color="g", linestyle="--", label="Listing Threshold"
    )
    ax2.grid(True)
    ax2.legend()

    plt.tight_layout()
    plt.savefig("working_bonding_curve.png")
    plt.close()

    print("Bonding curve plot saved as working_bonding_curve.png")


def run_simulation():
    """Run a simple simulation of the bonding curve"""
    virtual_sui = INITIAL_VIRTUAL_SUI
    virtual_tokens = Decimal("0")  # Start with 0 tokens
    user_tokens = Decimal("0")

    print(f"Initial state:")
    print(f"  Virtual SUI: {virtual_sui}")
    print(f"  Virtual tokens: {virtual_tokens}")
    print(f"  K: {K}")
    print(f"  Initial price: {calculate_price(virtual_tokens)}")
    print()

    # Simulate a series of buy and sell transactions
    print("=== Buy Transactions ===")

    # Buy 5 SUI
    virtual_sui, virtual_tokens, tokens_minted = simulate_buy_transaction(
        virtual_sui, virtual_tokens, Decimal("5")
    )
    user_tokens += tokens_minted
    print(f"  User token balance: {user_tokens}")
    print()

    # Buy 10 SUI
    virtual_sui, virtual_tokens, tokens_minted = simulate_buy_transaction(
        virtual_sui, virtual_tokens, Decimal("10")
    )
    user_tokens += tokens_minted
    print(f"  User token balance: {user_tokens}")
    print()

    # Buy 20 SUI
    virtual_sui, virtual_tokens, tokens_minted = simulate_buy_transaction(
        virtual_sui, virtual_tokens, Decimal("20")
    )
    user_tokens += tokens_minted
    print(f"  User token balance: {user_tokens}")
    print()

    print("=== Sell Transactions ===")

    # Sell half of tokens
    sell_amount = user_tokens / 2
    virtual_sui, virtual_tokens, sui_received = simulate_sell_transaction(
        virtual_sui, virtual_tokens, sell_amount
    )
    user_tokens -= sell_amount
    print(f"  User token balance: {user_tokens}")
    print()

    # Buy enough to reach transition
    sui_to_transition = LISTING_THRESHOLD - virtual_sui
    if sui_to_transition > Decimal("0"):
        print(f"=== Transition Transaction ===")
        print(f"Buying {sui_to_transition} SUI to reach transition threshold")
        virtual_sui, virtual_tokens, tokens_minted = simulate_buy_transaction(
            virtual_sui, virtual_tokens, sui_to_transition
        )
        user_tokens += tokens_minted
        print(f"  User token balance: {user_tokens}")
        print()

    # Plot the bonding curve
    plot_bonding_curve()


if __name__ == "__main__":
    run_simulation()
