import numpy as np
import matplotlib.pyplot as plt
from decimal import Decimal, getcontext

# Set high precision for decimal calculations
getcontext().prec = 40

# Constants from Move module (normalized for readability)
# Note: In the Move code, these values include 9 decimal places
MAX_SUPPLY = Decimal("1000000000")  # 1 billion tokens
INITIAL_VIRTUAL_SUI = Decimal("30")  # 30 SUI
INITIAL_VIRTUAL_TOKENS = Decimal("1073000191")  # ~1.07B tokens
K = Decimal("32190005730")  # Constant product k
LISTING_THRESHOLD = Decimal("69")  # 69 SUI for transition to AMM

DEBUG = True


class BondingCurve:
    def __init__(self):
        self.total_minted = Decimal("0")
        self.virtual_sui_reserves = INITIAL_VIRTUAL_SUI
        self.virtual_token_reserves = INITIAL_VIRTUAL_TOKENS
        self.sui_reserves = Decimal("0")
        self.transitioned = False

        if DEBUG:
            print(f"Initial state:")
            print(f"  K: {K}")
            print(f"  Virtual SUI reserves: {self.virtual_sui_reserves}")
            print(f"  Virtual token reserves: {self.virtual_token_reserves}")
            print(
                f"  Product: {self.virtual_sui_reserves * self.virtual_token_reserves}"
            )

    def calculate_tokens_to_mint(self, sui_amount):
        """Calculate how many tokens will be minted for a given SUI amount"""
        if DEBUG:
            print(f"\nCalculating tokens for {sui_amount} SUI:")
            print(
                f"  Before: Virtual SUI={self.virtual_sui_reserves}, Virtual Tokens={self.virtual_token_reserves}"
            )

        # From Move code:
        # let x = (bonding_curve.virtual_sui_reserves as u128) + (sui_amount as u128);
        # let y = INITIAL_VIRTUAL_TOKENS as u128 - (K / (INITIAL_VIRTUAL_SUI as u128 + x));
        # (y as u64) - bonding_curve.virtual_token_reserves

        x = self.virtual_sui_reserves + sui_amount

        # Calculate new token supply after purchase
        if x <= Decimal("0"):
            return Decimal("0")

        y = INITIAL_VIRTUAL_TOKENS - (K / (INITIAL_VIRTUAL_SUI + x))

        # Tokens to mint is the difference between new token supply and current virtual reserves
        tokens_to_mint = y - self.virtual_token_reserves

        if DEBUG:
            print(f"  New virtual SUI would be: {x}")
            print(f"  New token supply would be: {y}")
            print(f"  Tokens to mint: {tokens_to_mint}")

        # Ensure we don't return negative tokens
        return max(Decimal("0"), tokens_to_mint)

    def calculate_sui_to_receive(self, token_amount):
        """Calculate how much SUI will be received for a given token amount"""
        if DEBUG:
            print(f"\nCalculating SUI for {token_amount} tokens:")
            print(
                f"  Before: Virtual SUI={self.virtual_sui_reserves}, Virtual Tokens={self.virtual_token_reserves}"
            )

        # From the Move code:
        # let y = (bonding_curve.virtual_token_reserves as u128) + (token_amount as u128);
        # let x = (K / (INITIAL_VIRTUAL_TOKENS as u128 - y)) - (INITIAL_VIRTUAL_SUI as u128);
        # bonding_curve.virtual_sui_reserves - (x as u64)

        y = self.virtual_token_reserves + token_amount

        # Check if we would exceed the initial token supply
        if y >= INITIAL_VIRTUAL_TOKENS:
            return Decimal("0")

        # Calculate how much SUI would be in reserves after the sale
        x = (K / (INITIAL_VIRTUAL_TOKENS - y)) - INITIAL_VIRTUAL_SUI

        # SUI to receive is the difference between current virtual SUI and new SUI amount
        sui_to_receive = self.virtual_sui_reserves - x

        if DEBUG:
            print(f"  New virtual tokens would be: {y}")
            print(f"  New SUI reserves would be: {x}")
            print(f"  SUI to receive: {sui_to_receive}")

        # Ensure we don't return negative SUI
        return max(Decimal("0"), sui_to_receive)

    def calculate_price(self, sui_amount=Decimal("0")):
        """Calculate token price in SUI at current point (or after hypothetical purchase)"""
        # The price at any point is the derivative of the bonding curve
        # For the constant product curve, it's K / y²
        denominator = INITIAL_VIRTUAL_TOKENS - self.virtual_token_reserves

        if denominator <= Decimal("0"):
            return Decimal("0")  # Avoid division by zero

        price = K / (denominator * denominator)
        return price

    def buy(self, sui_amount):
        """Simulate buying tokens with SUI"""
        if self.transitioned:
            print("Bonding curve has transitioned to AMM")
            return Decimal("0")

        sui_amount = Decimal(str(sui_amount))
        tokens_to_mint = self.calculate_tokens_to_mint(sui_amount)

        if tokens_to_mint <= Decimal("0"):
            print("No tokens would be minted for this amount")
            return Decimal("0")

        if self.total_minted + tokens_to_mint > MAX_SUPPLY:
            print("Exceeds max supply")
            return Decimal("0")

        self.total_minted += tokens_to_mint
        self.sui_reserves += sui_amount

        self.virtual_sui_reserves += sui_amount
        self.virtual_token_reserves -= tokens_to_mint

        self.check_transition()

        return tokens_to_mint

    def sell(self, token_amount):
        """Simulate selling tokens for SUI"""
        if self.transitioned:
            print("Bonding curve has transitioned to AMM")
            return Decimal("0")

        token_amount = Decimal(str(token_amount))
        sui_to_receive = self.calculate_sui_to_receive(token_amount)

        if sui_to_receive <= Decimal("0"):
            print("No SUI would be received for this amount")
            return Decimal("0")

        if sui_to_receive > self.sui_reserves:
            print("Insufficient liquidity")
            return Decimal("0")

        self.total_minted -= token_amount
        self.sui_reserves -= sui_to_receive

        self.virtual_sui_reserves -= sui_to_receive
        self.virtual_token_reserves += token_amount

        return sui_to_receive

    def check_transition(self):
        """Check if bonding curve should transition to AMM"""
        if self.virtual_sui_reserves >= LISTING_THRESHOLD and not self.transitioned:
            print(f"Transition triggered at {self.virtual_sui_reserves} SUI reserves")
            self.transitioned = True
            # In a real implementation, would set up AMM pools here

    def get_stats(self):
        """Get current stats"""
        return {
            "total_minted": float(self.total_minted),
            "virtual_sui_reserves": float(self.virtual_sui_reserves),
            "virtual_token_reserves": float(self.virtual_token_reserves),
            "sui_reserves": float(self.sui_reserves),
            "transitioned": self.transitioned,
            "current_price": float(self.calculate_price()),
            "sui_to_transition": (
                float(LISTING_THRESHOLD - self.virtual_sui_reserves)
                if not self.transitioned
                else 0
            ),
        }


def plot_bonding_curve(curve, sui_range=None):
    """Plot the bonding curve price function"""
    if sui_range is None:
        # Default range from 0 to threshold
        sui_range = np.linspace(0, float(LISTING_THRESHOLD) * 1.2, 1000)

    # Create a fresh curve to avoid modifying the passed one
    sim_curve = BondingCurve()

    # Calculate token price at each point
    prices = []
    tokens_minted = []
    token_balance = []

    for sui in sui_range:
        # How many tokens would be minted for this amount of SUI
        tokens = Decimal(str(sim_curve.calculate_tokens_to_mint(Decimal(str(sui)))))

        # Add to our tracking
        tokens_minted.append(float(tokens))
        token_balance.append(
            float(INITIAL_VIRTUAL_TOKENS - sim_curve.virtual_token_reserves - tokens)
        )

        # Update the curve as if purchase happened
        sim_curve.virtual_sui_reserves += Decimal(str(sui))
        sim_curve.virtual_token_reserves -= tokens

        # Get the price after this update
        prices.append(float(sim_curve.calculate_price()))

    # Create the plots
    fig, (ax1, ax2, ax3) = plt.subplots(3, 1, figsize=(12, 16))

    # Price curve
    ax1.plot(sui_range, prices)
    ax1.set_title("Token Price vs. SUI Invested")
    ax1.set_xlabel("SUI Amount")
    ax1.set_ylabel("Token Price (in SUI)")
    ax1.axhline(y=0, color="r", linestyle="-", alpha=0.3)
    ax1.axvline(
        x=float(LISTING_THRESHOLD), color="g", linestyle="--", label="Listing Threshold"
    )
    ax1.grid(True)
    ax1.legend()

    # Tokens minted per buy
    ax2.plot(sui_range, tokens_minted)
    ax2.set_title("Tokens Minted per SUI Purchase")
    ax2.set_xlabel("SUI Purchase Amount")
    ax2.set_ylabel("Tokens Minted")
    ax2.axvline(
        x=float(LISTING_THRESHOLD), color="g", linestyle="--", label="Listing Threshold"
    )
    ax2.grid(True)
    ax2.legend()

    # Cumulative tokens in circulation
    ax3.plot(sui_range, token_balance)
    ax3.set_title("Tokens in Circulation vs. SUI Invested")
    ax3.set_xlabel("Cumulative SUI Invested")
    ax3.set_ylabel("Tokens in Circulation")
    ax3.axvline(
        x=float(LISTING_THRESHOLD), color="g", linestyle="--", label="Listing Threshold"
    )
    ax3.grid(True)
    ax3.legend()

    plt.tight_layout()
    plt.savefig("bonding_curve_analysis.png")
    plt.close()

    return "bonding_curve_analysis.png"


def simulate_transactions():
    """Simulate a series of buy and sell transactions"""
    curve = BondingCurve()

    print("\n=== INITIAL STATE ===")
    print(curve.get_stats())

    # Tracking data
    sui_invested = []
    token_balance = []
    token_price = []
    transaction_types = []

    # Realistic transaction amounts
    transactions = [
        {"type": "buy", "amount": 5.0},  # Buy 5 SUI worth
        {"type": "buy", "amount": 10.0},  # Buy 10 SUI worth
        {"type": "sell", "amount": 1000000},  # Sell 1M tokens
        {"type": "buy", "amount": 20.0},  # Buy 20 SUI worth
        {
            "type": "buy",
            "amount": 30.0,
        },  # Buy 30 SUI worth - should approach transition
        {"type": "sell", "amount": 2000000},  # Sell 2M tokens
        {"type": "buy", "amount": 50.0},  # Should trigger transition
    ]

    print("\n=== TRANSACTION HISTORY ===")

    total_sui_invested = 0
    user_token_balance = 0

    for i, tx in enumerate(transactions):
        print(f"\n--- Transaction {i+1}: {tx['type'].upper()} {tx['amount']} ---")

        if tx["type"] == "buy":
            sui_amount = tx["amount"]
            total_sui_invested += sui_amount
            tokens_received = curve.buy(sui_amount)
            user_token_balance += tokens_received
            print(
                f"Buy {sui_amount} SUI -> Received {float(tokens_received):.2f} tokens at {float(curve.calculate_price()):.8f} SUI/token"
            )
        else:  # Sell
            token_amount = min(
                Decimal(str(tx["amount"])), user_token_balance
            )  # Can't sell more than we have
            print(
                f"Attempting to sell {float(token_amount)} tokens (of {float(user_token_balance)} available)"
            )
            sui_received = curve.sell(token_amount)
            user_token_balance -= token_amount
            total_sui_invested -= float(sui_received)
            print(
                f"Sell {float(token_amount)} tokens -> Received {float(sui_received):.6f} SUI at {float(curve.calculate_price()):.8f} SUI/token"
            )

        # Record data for charts
        sui_invested.append(total_sui_invested)
        token_balance.append(float(user_token_balance))
        token_price.append(float(curve.calculate_price()))
        transaction_types.append(tx["type"])

        # Print state after transaction
        stats = curve.get_stats()
        print(f"\nState after transaction {i+1}:")
        print(
            f"  Virtual SUI: {stats['virtual_sui_reserves']:.6f}, Virtual Tokens: {stats['virtual_token_reserves']:.2f}"
        )
        print(
            f"  SUI Reserves: {stats['sui_reserves']:.6f}, Token Price: {stats['current_price']:.8f} SUI/token"
        )
        print(
            f"  User Balance: {float(user_token_balance):.2f} tokens, {total_sui_invested:.2f} SUI net invested"
        )

        # Check product
        current_product = curve.virtual_sui_reserves * (
            INITIAL_VIRTUAL_TOKENS - curve.virtual_token_reserves
        )
        print(f"  Current K product: {current_product} (original K: {K})")

        if stats["transitioned"]:
            print("  Status: Transitioned to AMM")
        else:
            print(
                f"  Status: Bonding Curve ({stats['sui_to_transition']:.2f} SUI to transition)"
            )

    # Plot transaction history
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 10))

    # Price history
    ax1.plot(range(len(token_price)), token_price, marker="o")
    for i, tx_type in enumerate(transaction_types):
        if tx_type == "buy":
            ax1.plot(i, token_price[i], "go", markersize=10)
        else:
            ax1.plot(i, token_price[i], "ro", markersize=10)
    ax1.set_title("Token Price History")
    ax1.set_xlabel("Transaction Number")
    ax1.set_ylabel("Token Price (SUI)")
    ax1.grid(True)

    # Token balance
    ax2.plot(range(len(token_balance)), token_balance, marker="o")
    for i, tx_type in enumerate(transaction_types):
        if tx_type == "buy":
            ax2.plot(i, token_balance[i], "go", markersize=10)
        else:
            ax2.plot(i, token_balance[i], "ro", markersize=10)
    ax2.set_title("User Token Balance")
    ax2.set_xlabel("Transaction Number")
    ax2.set_ylabel("Token Balance")
    ax2.grid(True)

    plt.tight_layout()
    plt.savefig("transaction_history.png")
    plt.close()

    return "transaction_history.png"


if __name__ == "__main__":
    # Simulate and analyze the bonding curve
    print("=== Bonding Curve Analysis ===")
    print(f"Initial Virtual SUI: {float(INITIAL_VIRTUAL_SUI)}")
    print(f"Initial Virtual Tokens: {float(INITIAL_VIRTUAL_TOKENS)}")
    print(f"Constant K: {float(K)}")
    print(f"Listing Threshold: {float(LISTING_THRESHOLD)}")
    print("")

    # Plot bonding curve
    curve_plot = plot_bonding_curve(BondingCurve())
    print(f"Bonding curve plot saved as {curve_plot}")

    # Simulate transactions
    print("\n=== Transaction Simulation ===")
    tx_plot = simulate_transactions()
    print(f"Transaction history plot saved as {tx_plot}")
