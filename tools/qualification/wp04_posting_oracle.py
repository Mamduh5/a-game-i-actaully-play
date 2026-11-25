"""Integer-only WP04 reference for grid, rate cursor and equality fixtures."""

from dataclasses import dataclass
import json
from math import gcd


ORDINARY_SCALE = 6
RELATIVE_PRECISION = 100_000


@dataclass(frozen=True)
class Amount:
    count: int
    scale: int

    def __post_init__(self):
        count, scale = self.count, self.scale
        if scale < 0:
            raise ValueError("Scale must be nonnegative")
        while scale and count % 10 == 0:
            count //= 10
            scale -= 1
        object.__setattr__(self, "count", count)
        object.__setattr__(self, "scale", scale)

    def at_scale(self, scale):
        if scale < self.scale:
            raise ValueError("Cannot coarsen an exact amount")
        return self.count * 10 ** (scale - self.scale)

    def __add__(self, other):
        scale = max(self.scale, other.scale)
        return Amount(self.at_scale(scale) + other.at_scale(scale), scale)

    def __sub__(self, other):
        return self + Amount(-other.count, other.scale)

    def fields(self):
        return {"version": 1, "negative": self.count < 0, "scale": self.scale,
                "magnitude": str(abs(self.count))}


def round_quotient(numerator, denominator):
    """Select the nearest signed integer, breaking midpoint ties toward even."""
    if denominator <= 0:
        raise ValueError("Denominator must be positive")
    quotient, remainder = divmod(abs(numerator), denominator)
    if 2 * remainder > denominator or (2 * remainder == denominator and quotient % 2):
        quotient += 1
    return -quotient if numerator < 0 else quotient


def transfer_scale(numerator, denominator):
    if numerator == 0:
        return ORDINARY_SCALE
    scale = ORDINARY_SCALE
    scaled_abs = abs(numerator) * 10 ** scale
    while scaled_abs < denominator * RELATIVE_PRECISION:
        scaled_abs *= 10
        scale += 1
    return scale


def quantize(numerator, denominator):
    scale = transfer_scale(numerator, denominator)
    return Amount(round_quotient(numerator * 10 ** scale, denominator), scale)


class Cursor:
    def __init__(self, numerator, denominator):
        self.numerator = numerator
        self.denominator = denominator
        self.scale = transfer_scale(numerator, denominator)
        self.occurrence = 0
        self.posted = Amount(0, 0)

    def next_debit(self):
        self.occurrence += 1
        scaled_ideal = self.occurrence * self.numerator * 10 ** self.scale
        count = round_quotient(scaled_ideal, self.denominator)
        debit = Amount(count, self.scale) - self.posted
        self.posted = self.posted + debit
        error_numerator = count * self.denominator - scaled_ideal
        if 2 * abs(error_numerator) > self.denominator:
            raise AssertionError("Cumulative rate error exceeded half a quantum")
        return debit


def subtract_exact(left, right):
    left_n, left_d = left
    right_n, right_d = right
    numerator = left_n * right_d - right_n * left_d
    denominator = left_d * right_d
    divisor = gcd(numerator, denominator)
    return numerator // divisor, denominator // divisor


def check(actual, expected, label):
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")


def posting_cases():
    check([round_quotient(n, 2) for n in (1, 3, 5, -1, -3, -5)], [0, 2, 2, 0, -2, -2], "midpoint parity")
    check(Amount(0, 34).fields(), Amount(0, 0).fields(), "canonical zero")
    check(Amount(-13000, 4).fields(), {"version": 1, "negative": True, "scale": 1, "magnitude": "13"},
          "canonical nonzero sign and scale")
    check(transfer_scale(1, 4_000_000), 12, "adaptive grid for quarter-micro")
    quarter = quantize(1, 4_000_000)
    check(quarter, Amount(25, 8), "exact quarter-micro posting")

    cursor = Cursor(1, 3)
    debits = [cursor.next_debit().at_scale(ORDINARY_SCALE) for _ in range(3)]
    check(debits, [333333, 333334, 333333], "one target stream across three transfers")
    check(cursor.posted, Amount(1, 0), "exact cumulative thirds")

    represented = Amount(1, 0)
    exact = (1, 1)
    for transfer in ((2, 9), (3, 9)):
        represented = represented - quantize(*transfer)
        exact = subtract_exact(exact, transfer)
    check(represented, Amount(444445, 6), "represented remaining capacity before equality")
    check(exact, (4, 9), "ideal remaining amount before equality")
    final_proposed = quantize(4, 9)
    check(final_proposed, Amount(444444, 6), "independently rounded final portion")
    check(subtract_exact(exact, (4, 9)), (0, 1), "certified exact equality")
    adjusted = represented - final_proposed
    check(adjusted, Amount(1, 6), "last debit adjustment stays inside the rounding envelope")

    huge = Amount(10 ** 400, 0)
    check(huge - quarter - quarter - quarter - quarter + Amount(1, 6), huge, "exact units survive magnitude widening")
    return {
        "ordinary_scale": ORDINARY_SCALE,
        "quarter_micro": quarter.fields(),
        "thirds_counts": debits,
        "mixed_equality": {
            "provisional_final_debit": final_proposed.fields(),
            "certified_final_debit": represented.fields(),
            "adjustment": adjusted.fields(),
            "ending_hp": Amount(0, 0).fields(),
            "overkill": Amount(0, 0).fields(),
        },
        "huge_after_net_unit_debit": (huge - Amount(1, 0)).fields(),
    }


if __name__ == "__main__":
    print(json.dumps(posting_cases(), indent=2))
