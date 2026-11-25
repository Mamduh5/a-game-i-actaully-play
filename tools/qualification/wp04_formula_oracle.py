"""Evaluate ideal GDS formula fixtures without any native posting or rounding code."""

from dataclasses import asdict, dataclass
from fractions import Fraction as F
import json
from math import prod


def incoming(base, flat_terms, bonus_categories, defense, reduction, penetration, k, vulnerability, immune=False):
    """GDS §3.5 for one eligible physical or magical component."""
    if immune:
        return F(0)
    offense = (F(base) + sum(flat_terms)) * prod(1 + sum(category) for category in bonus_categories)
    effective_defense = max(F(0), F(defense) * (1 - reduction) * (1 - penetration))
    return offense * k / (effective_defense + k) * vulnerability


@dataclass(frozen=True)
class Barrier:
    id: str
    capacity: F
    remaining_ms: int | None
    created: int


def resolve_damage(amount, hp, barriers=()):
    """GDS §§3.5 and 4.3 after contact and compatibility have been established."""
    remaining = amount
    layers = {}
    order = sorted(barriers, key=lambda b: (b.remaining_ms is None, b.remaining_ms or 0, b.created))
    for layer in order:
        absorbed = min(remaining, layer.capacity)
        remaining -= absorbed
        layers[layer.id] = (absorbed, layer.capacity - absorbed, absorbed > 0 and absorbed == layer.capacity)
    actual = min(remaining, hp)
    return {"layers": layers, "hp_lost": actual, "hp_after": hp - actual, "overkill": remaining - actual,
            "lethal": hp > 0 and hp == actual}


def recover(base, source_limit, amplification, hp, maximum):
    """GDS §4.4 with one declared source limit and compatible amplification."""
    if hp == 0:
        return F(0), F(0)
    available = min(base, source_limit) * amplification
    restored = min(available, maximum - hp)
    return restored, available - restored


def adjust_current_hp(current, new_maximum):
    """An adjustment changes the cap and can clamp absolute HP."""
    return min(current, new_maximum)


def collapse_at(elapsed_seconds):
    """GDS §23.1–2 exact integral-tier factors relative to time zero."""
    elapsed_seconds = F(elapsed_seconds)
    if elapsed_seconds < 1500:
        growth = (elapsed_seconds / 1500) ** 2
        return 0, 1 + 2 * growth, 1 + growth
    tier = 1 + (elapsed_seconds - 1500) // 120
    return tier, 3 * F(7, 5) ** tier, 2 * F(5, 4) ** tier


def enemy_factors(elapsed_seconds, region, party_size, challenge=(F(1), F(1)), final_arena=False):
    """GDS §23.5–6. The caller supplies the enemy's assigned region and locked party size."""
    region_factors = {
        "wilds": (F(1), F(1)),
        "expanse": (F(5, 4), F(23, 20)),
        "forgotten": (F(3, 2), F(13, 10)),
        None: (F(1), F(1)),
    }
    party_hp = 1 + F(party_size - 1, 2)
    party_damage = 1 + F(party_size - 1, 10)
    if final_arena:
        return party_hp * challenge[0], party_damage * challenge[1]
    _, time_hp, time_damage = collapse_at(elapsed_seconds)
    regional_hp, regional_damage = region_factors[region]
    return regional_hp * party_hp * time_hp * challenge[0], regional_damage * party_damage * time_damage * challenge[1]


def hazard_factor(elapsed_seconds, neutral_collapse, final_arena=False):
    if neutral_collapse and not final_arena:
        return F(5, 4) ** collapse_at(elapsed_seconds)[0]
    return F(1)


def root_floor(value, degree):
    """Integer binary search, used only for an outward ideal-formula bound."""
    low = 0
    high = 1 << ((value.bit_length() + degree - 1) // degree)
    while low + 1 < high:
        middle = (low + high) // 2
        if middle ** degree <= value:
            low = middle
        else:
            high = middle
    return low


def power_bounds(base, exponent, decimal_places):
    """Bounds for a nonnegative rational input raised to a positive rational exponent."""
    power, root = exponent.numerator, exponent.denominator
    radicand = F(base) ** power
    if root == 1:
        return radicand, radicand
    scale = 10 ** decimal_places
    scaled = radicand * scale ** root
    lower = F(root_floor(scaled.numerator // scaled.denominator, root), scale)
    return (lower, lower) if lower ** root == radicand else (lower, lower + F(1, scale))


@dataclass(frozen=True)
class XpCurve:
    base: F
    coefficient: F
    exponent: F
    transition: int
    multiplier: F

    def bounds(self, level, decimal_places):
        """GDS §21.2 with supplied fixture coefficients and directed bounds."""
        polynomial_level = min(level, self.transition)
        powers = power_bounds(polynomial_level - 1, self.exponent, decimal_places)
        growth = self.multiplier ** max(0, level - self.transition)
        return tuple((self.base + self.coefficient * power) * growth for power in powers)


def check(actual, expected, label):
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")


def formula_cases():
    cases = {}
    offense = (100, [F(20)], [[F(1, 10), F(1, 5)], [F(1, 4)]], 80, F(1, 4), F(1, 2), 100, F(13, 10))
    cases["incoming"] = incoming(*offense)
    check(cases["incoming"], F(195), "categorized offense and staged defense")
    check(incoming(*offense, immune=True), F(0), "explicit immunity")

    barriers = [
        Barrier("persistent", F(5), None, 0), Barrier("new", F(4), 30, 2),
        Barrier("old", F(6), 30, 1), Barrier("soon", F(2), 10, 3),
    ]
    cases["layers"] = resolve_damage(F(20), F(2), barriers)
    check(list(cases["layers"]["layers"]), ["soon", "old", "new", "persistent"], "barrier order")
    check(cases["layers"]["hp_lost"], F(2), "actual enemy HP loss")
    check(cases["layers"]["overkill"], F(1), "exact overkill")
    check(cases["layers"]["lethal"], True, "exact terminal threshold")

    huge = F(10 ** 400)
    after_hits = resolve_damage(F(1), resolve_damage(F(1), huge)["hp_after"])["hp_after"]
    healing, excess = recover(F(1), F(1), F(1), after_hits, huge + 100)
    cases["huge_hp"] = after_hits + healing
    check(cases["huge_hp"], huge - 1, "unit debits remain meaningful at 10^400")
    check(excess, F(0), "huge heal excess")
    cases["limited_recovery"] = recover(F(10), F(4), F(3, 2), F(98), F(100))
    check(cases["limited_recovery"], (F(2), F(4)), "source limit before amplification and excess")
    check(recover(F(10), F(4), F(3, 2), F(0), F(100)), (F(0), F(0)), "ordinary healing after death")
    check(adjust_current_hp(F(80), F(70)), F(70), "clamp preserves the remaining HP")
    check(adjust_current_hp(F(80), F(140)), F(80), "higher maximum preserves absolute HP")

    tiny = F(1, 4_000_000)
    cases["tiny_damage"] = [resolve_damage(tiny, F(1, 1_000_000) - i * tiny) for i in range(4)]
    check(sum(hit["hp_lost"] for hit in cases["tiny_damage"]), F(1, 1_000_000), "four tiny hits")
    check([hit["lethal"] for hit in cases["tiny_damage"]], [False, False, False, True], "tiny lethal boundary")
    cases["changing_rates"] = [
        resolve_damage(F(4, 9) + offset, 1 - F(2, 9) - F(3, 9)) for offset in (-tiny, 0, tiny)
    ]
    check([hit["lethal"] for hit in cases["changing_rates"]], [False, True, True], "mixed exact lethal equality")
    check([hit["overkill"] for hit in cases["changing_rates"]], [F(0), F(0), tiny], "mixed exact overkill")

    cases["collapse"] = [collapse_at(time) for time in (0, 300, F(1499_999, 1000), 1500, 1620, 1740)]
    check(cases["collapse"][1], (0, F(27, 25), F(26, 25)), "pre-Collapse at five minutes")
    check(cases["collapse"][2][0], 0, "just before Collapse")
    check(cases["collapse"][3], (1, F(21, 5), F(5, 2)), "exact 25-minute boundary")
    check(cases["collapse"][4], (2, F(147, 25), F(25, 8)), "exact 27-minute boundary")
    check(collapse_at(1500 + 119 * 120)[1], 3 * F(7, 5) ** 120, "computed directly at high tier")
    cases["expanse_two_players"] = enemy_factors(1500, "expanse", 2)
    check(cases["expanse_two_players"], (F(63, 8), F(253, 80)), "QAS regional party fixture")
    check(enemy_factors(11_000, "forgotten", 2, final_arena=True), (F(3, 2), F(11, 10)), "final arena excludes time and region")
    check((hazard_factor(1620, True), hazard_factor(1620, False), hazard_factor(1620, True, True)),
          (F(25, 16), F(1), F(1)), "neutral hazard, player-owned impact and final arena")

    curve = XpCurve(F(40), F(3), F(2), 6, F(5, 4))
    cases["xp_fixture_parameters"] = asdict(curve)
    cases["xp_transition"] = [curve.bounds(level, 24) for level in (1, 2, 6, 7)]
    check(cases["xp_transition"], [(F(n), F(n)) for n in (40, 43, 115, F(575, 4))], "polynomial and exponential XP")
    check(F(85) - curve.bounds(1, 24)[0] - curve.bounds(2, 24)[0], F(2), "two XP thresholds and carry")
    lower, upper = power_bounds(2, F(5, 2), 24)
    check(lower ** 2 < 32 < upper ** 2, True, "outward bound for a nonintegral XP exponent")
    cases["xp_fractional_power_bounds"] = (lower, upper)
    return cases


if __name__ == "__main__":
    print(json.dumps(formula_cases(), indent=2, default=str))
