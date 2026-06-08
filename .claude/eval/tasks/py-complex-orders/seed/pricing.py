def line_total(item):
    # BUG: ignores the discount.
    return item["qty"] * item["unit_price"]


def order_subtotal(order):
    # BUG: returns the item count, not the summed line totals.
    return len(order["items"])


def apply_tax(subtotal, rate):
    # BUG: doesn't round to cents.
    return subtotal + subtotal * rate
