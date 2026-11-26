class_name StarterCombatRules
extends Resource
## Stable C01 tuning and source IDs. Running combatants keep detached values.

const UNDYING := &"H01"
const HARVEST := &"H01.life_harvest"
const SIPHON := &"H01.siphon_pulse"
const CONDUCTOR := &"H03"
const HARMONIC_BURST := &"H03.harmonic_burst"

@export var revision: int = 1
@export var weapons: Array[StarterWeapon] = []
@export var harvest_per_kill: int = 2
@export var harvest_cap: int = 30
@export var siphon_radius: float = 90.0
@export var siphon_damage: int = 24
@export var siphon_ratio_percent: int = 75
@export var siphon_cap: int = 40
@export var siphon_lifetime: int = 240
@export var siphon_decay_interval: int = 12
@export var siphon_cooldown: int = 600
@export var harmonic_reach: float = 96.0
@export var harmonic_damage: int = 18
@export var harmonic_cooldown: int = 240
@export var resonance_cap: int = 5
@export var force_distance: float = 20.0
@export var lightning_reach: float = 64.0
@export var lightning_damage: int = 10


func is_valid_for(catalog: DefinitionCatalog) -> bool:
	if (catalog == null or not catalog.is_valid() or revision <= 0 or weapons.size() != 3
			or not is_finite(harmonic_reach) or harmonic_reach <= 0.0 or harmonic_damage <= 0 or harmonic_cooldown <= 0
			or not is_finite(force_distance) or force_distance <= 0.0
			or not is_finite(lightning_reach) or lightning_reach <= 0.0 or lightning_damage <= 0
			or resonance_cap <= 0 or harvest_per_kill <= 0 or harvest_cap < harvest_per_kill
			or not is_finite(siphon_radius) or siphon_radius <= 0.0 or siphon_damage <= 0
			or siphon_ratio_percent <= 0 or siphon_ratio_percent > 100 or siphon_cap <= 0
			or siphon_decay_interval <= 0 or siphon_lifetime <= siphon_decay_interval or siphon_cooldown <= 0):
		return false
	var hero := catalog.lookup(UNDYING)
	if hero == null or hero.kind != CatalogEntry.Kind.HERO or hero.eligibility != CatalogEntry.Eligibility.STARTER:
		return false
	var seen: Dictionary[StringName, bool] = {}
	for weapon: StarterWeapon in weapons:
		if weapon == null or seen.has(weapon.id) or not weapon.matches(catalog):
			return false
		seen[weapon.id] = true
	return true


func weapon_for(id: StringName) -> StarterWeapon:
	for weapon: StarterWeapon in weapons:
		if weapon.id == id:
			return weapon
	return null


func prepare_hero(actor: CombatantState, preparation: RunPreparation) -> bool:
	if actor == null or preparation == null:
		return false
	if preparation.hero == UNDYING:
		var grant := _barrier(HARVEST, harvest_per_kill, 0, CombatAction.BarrierRule.ACCUMULATE)
		grant.cap = Quantity.from_count(harvest_cap)
		actor.barrier_on_elimination = grant
	return true


func siphon_conversion() -> CombatAction.BarrierConversion:
	var rule := CombatAction.BarrierConversion.new()
	rule.grant = _barrier(SIPHON, siphon_cap, siphon_lifetime, CombatAction.BarrierRule.STRONGEST)
	rule.rate = Quantity.from_count(siphon_ratio_percent, 2)
	return rule


static func _barrier(id: StringName, capacity: int, ticks: int,
		rule: CombatAction.BarrierRule) -> CombatAction.BarrierGrant:
	var grant := CombatAction.BarrierGrant.new()
	grant.id = id
	grant.mask = CombatAction.Damage.PHYSICAL | CombatAction.Damage.MAGICAL
	grant.capacity = Quantity.from_count(capacity)
	grant.duration_ticks = ticks
	grant.rule = rule
	return grant
