class_name StarterCombatRules
extends Resource

const CHRONOMANCER := &"H04"
const TIME_FRACTURE := &"H04.time_fracture"
const TEMPORAL_ECHO := &"H04.temporal_echo"

@export var fracture_reach: float = 180.0
@export var fracture_radius: float = 48.0
@export var fracture_duration: int = 90
@export var fracture_cooldown: int = 240
@export var echo_delay: int = 30
@export var echo_radius: float = 12.0
## Stable C01 tuning and source IDs. Running combatants keep detached values.

const UNDYING := &"H01"
const HARVEST := &"H01.life_harvest"
const SIPHON := &"H01.siphon_pulse"
const ACROBAT := &"H02"
const VAULT := &"H02.vault"
const CLOSE_CALL := &"H02.close_call"
const GRAVITY_WEAVER := &"H05"
const SINGULARITY := &"H05.singularity"
const BLOODBOUND := &"H07"
const CRIMSON_OFFERING := &"H07.crimson_offering"
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
@export var vault_distance: float = 64.0
@export var vault_steps: int = 14
@export var vault_cooldown: int = 240
@export var close_call_margin: float = 8.0
@export var close_call_duration: int = 180
@export var close_call_basis_points: int = 2000
@export var gravity_force_scale: float = 1.3
@export var gravity_reach: float = 150.0
@export var gravity_radius: float = 64.0
@export var gravity_pull: float = 16.0
@export var gravity_push: float = 14.0
@export var gravity_damage: int = 22
@export var gravity_delay: int = 24
@export var gravity_cooldown: int = 420
@export var blood_pact_basis_points: int = 4000
@export var crimson_cost_basis_points: int = 2500
@export var crimson_cap_basis_points: int = 3000
@export var crimson_hp_for_cap: int = 30
@export var crimson_duration: int = 180
@export var crimson_cooldown: int = 360
@export var harmonic_reach: float = 96.0
@export var harmonic_damage: int = 18
@export var harmonic_cooldown: int = 240
@export var resonance_cap: int = 5
@export var force_distance: float = 20.0
@export var lightning_reach: float = 64.0
@export var lightning_damage: int = 10
@export var bleed_damage: int = 3
@export var bleed_capacity: int = 3
@export var bleed_duration: int = 180
@export var bleed_period: int = 60
@export var rupture_per_stack: int = 6
@export var wake_radius: float = 5.0
@export var wake_period: int = 15
@export var wake_duration: int = 45
@export var wake_damage: int = 4


func is_valid_for(catalog: DefinitionCatalog) -> bool:
	if (catalog == null or not catalog.is_valid() or revision <= 0 or weapons.size() != 3
			or not is_finite(fracture_reach) or fracture_reach <= 0.0
			or not is_finite(fracture_radius) or fracture_radius <= 0.0
			or fracture_duration <= 0 or fracture_cooldown < fracture_duration
			or echo_delay <= 0 or not is_finite(echo_radius) or echo_radius <= 0.0
			or not is_finite(harmonic_reach) or harmonic_reach <= 0.0 or harmonic_damage <= 0 or harmonic_cooldown <= 0
			or not is_finite(vault_distance) or vault_distance <= 0.0 or vault_steps <= 0 or vault_cooldown < vault_steps
			or not is_finite(close_call_margin) or close_call_margin <= 0.0 or close_call_duration <= 0
			or close_call_basis_points <= 0 or close_call_basis_points > RunPreparation.BASIS_POINTS
			or not is_finite(gravity_force_scale) or gravity_force_scale < 1.0
			or not is_finite(gravity_reach) or gravity_reach <= 0.0 or not is_finite(gravity_radius) or gravity_radius <= 0.0
			or not is_finite(gravity_pull) or gravity_pull <= 0.0 or not is_finite(gravity_push) or gravity_push <= 0.0
			or not is_finite(gravity_pull * gravity_force_scale) or not is_finite(gravity_push * gravity_force_scale)
			or gravity_damage <= 0 or gravity_delay <= 0 or gravity_delay > RunAuthority.MAX_TICK - 10
			or gravity_cooldown < gravity_delay
			or blood_pact_basis_points <= 0 or blood_pact_basis_points > RunPreparation.BASIS_POINTS
			or crimson_cost_basis_points <= 0 or crimson_cost_basis_points >= RunPreparation.BASIS_POINTS
			or crimson_cap_basis_points <= 0 or crimson_cap_basis_points > RunPreparation.BASIS_POINTS
			or crimson_hp_for_cap <= 0 or crimson_duration <= 0 or crimson_cooldown < crimson_duration
			or not is_finite(force_distance) or force_distance <= 0.0
			or not is_finite(lightning_reach) or lightning_reach <= 0.0 or lightning_damage <= 0
			or bleed_damage <= 0 or bleed_capacity <= 0 or bleed_period <= 0 or bleed_duration < bleed_period or rupture_per_stack <= 0
			or not is_finite(wake_radius) or wake_radius <= 0 or wake_period <= 0 or wake_duration < wake_period or wake_damage <= 0
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


func bleed_application(bonuses: Array[QuantityFormula.BonusCategory]) -> CombatBleedLedger.Application:
	var application := CombatBleedLedger.Application.new()
	application.offense = CombatAction.Component.new()
	application.offense.base = Quantity.from_count(bleed_damage)
	application.offense.categories = bonuses
	application.capacity = bleed_capacity
	application.duration = bleed_duration
	application.period = bleed_period
	return application


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
