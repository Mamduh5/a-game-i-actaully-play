class_name StarterWeapon
extends Resource
## Authored native delivery values for the available main weapons.

enum Delivery { CLEAVE, ARROW, SIGIL, THRUST, DAGGERS }

@export var id: StringName
@export var delivery: Delivery
@export var damage: int
@export var cooldown_ticks: int
@export var reach: float
@export var half_angle_degrees: float
@export var travel_per_tick: float
@export var delay_ticks: int
@export var area_radius: float
@export var thrust_width: float
@export var hand_offset: float


func matches(catalog: DefinitionCatalog) -> bool:
	var entry := catalog.lookup(id)
	if (entry == null or entry.kind != CatalogEntry.Kind.WEAPON or entry.source_family != id
			or damage <= 0 or cooldown_ticks <= 0 or not is_finite(reach) or reach <= 0.0):
		return false
	var unlocked := delivery in [Delivery.THRUST, Delivery.DAGGERS]
	var eligibility := CatalogEntry.Eligibility.OWNERSHIP if unlocked else CatalogEntry.Eligibility.STARTER
	if entry.eligibility != eligibility:
		return false
	match delivery:
		Delivery.CLEAVE: return id == &"W01" and half_angle_degrees > 0.0 and half_angle_degrees < 90.0
		Delivery.ARROW: return id == &"W02" and is_finite(travel_per_tick) and travel_per_tick > 0.0
		Delivery.SIGIL: return id == &"W03" and delay_ticks > 0 and is_finite(area_radius) and area_radius > 0.0
		Delivery.THRUST, Delivery.DAGGERS:
			if not is_finite(thrust_width) or thrust_width <= 0.0 or thrust_width >= reach:
				return false
			if delivery == Delivery.THRUST:
				return id == &"W04"
			return id == &"W06" and is_finite(hand_offset) and hand_offset > 0.0 and hand_offset < thrust_width * 0.5
	return false
