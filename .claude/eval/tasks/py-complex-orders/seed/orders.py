from pricing import order_subtotal, apply_tax


def order_total(order, tax_rate):
    # BUG: no negative-qty validation.
    return apply_tax(order_subtotal(order), tax_rate)
