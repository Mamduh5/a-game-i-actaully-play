class_name StarterWeapon
extends Resource
## Authored native delivery values for the three C01 weapon IDs.

enum Delivery { CLEAVE, ARROW, SIGIL }

@export var id: StringName
@export var delivery: Delivery
@export var damage: int
@export var cooldown_ticks: int
@export var reach: float
@export var half_angle_degrees: float
@export var travel_per_tick: float
@export var delay_ticks: int
@export var area_radius: float


func matches(catalog: DefinitionCatalog) -> bool:
	var entry := catalog.lookup(id)
	if (entry == null or entry.kind != CatalogEntry.Kind.WEAPON or entry.source_family != id
			or entry.eligibility != CatalogEntry.Eligibility.STARTER
			or damage <= 0 or cooldown_ticks <= 0 or not is_finite(reach) or reach <= 0.0):
		return false
	match delivery:
		Delivery.CLEAVE: return id == &"W01" and half_angle_degrees > 0.0 and half_angle_degrees < 90.0
		Delivery.ARROW: return id == &"W02" and is_finite(travel_per_tick) and travel_per_tick > 0.0
		Delivery.SIGIL: return id == &"W03" and delay_ticks > 0 and is_finite(area_radius) and area_radius > 0.0
	return false
