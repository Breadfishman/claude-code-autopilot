def apply_discount(price, pct):
    return max(0.0, price * (1 - pct / 100))
