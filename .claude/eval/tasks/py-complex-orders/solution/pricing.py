def line_total(item):
    gross = item["qty"] * item["unit_price"]
    return max(0.0, gross * (1 - item.get("discount_pct", 0) / 100))


def order_subtotal(order):
    return float(sum(line_total(i) for i in order["items"]))


def apply_tax(subtotal, rate):
    return round(subtotal * (1 + rate), 2)
