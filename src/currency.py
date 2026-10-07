"""Fixed-rate USD presentation of the checked source amounts assumed to be NGN."""
from decimal import Decimal

NGN_PER_USD = Decimal("158.552641666667")


def to_usd(amount):
    """Keep full Decimal precision until the presentation rounds the result."""
    return Decimal(amount) / NGN_PER_USD
