from pricing import order_subtotal, apply_tax


def order_total(order, tax_rate):
    for item in order["items"]:
        if item["qty"] < 0:
            raise ValueError("negative qty")
    return apply_tax(order_subtotal(order), tax_rate)
