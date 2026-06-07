def apply_discount(price, pct):
    # BUG: adds the percentage instead of subtracting it, and never clamps.
    return price * (1 + pct / 100)
