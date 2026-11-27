class_name RunPreparation
extends RefCounted
## Captures one seat's legal equipment and candidate pool at preparation.
## The authority supplies permanent access from the owner's profile.

const RUNE_SLOTS := 2
const CANDIDATE_SLOTS := 10
const BASIS_POINTS := 10000
const UPGRADE_CAP_BASIS_POINTS := 2500
const UPGRADE_STATS := [&"maximum_hp", &"base_damage", &"physical_defense", &"magical_defense", &"movement",
	&"automatic_attack_frequency", &"manual_cooldown_recovery"]

var catalog_revision: StringName:
	get: return _catalog.revision if _catalog != null else &""
var catalog: DefinitionCatalog:
	get: return _catalog
var hero: StringName:
	get: return _hero
var weapon: StringName:
	get: return _weapon

var _catalog: DefinitionCatalog
var _hero: StringName
var _weapon: StringName
var _runes: Array[StringName] = []
var _candidates: Array[StringName] = []
var _eligible_powers: Array[StringName] = []
var _unlocked: Array[StringName] = []
var _upgrades: Dictionary[StringName, int] = {}


static func select(catalog: DefinitionCatalog, hero_id: StringName, weapon_id: StringName,
		rune_slots: Array[StringName], candidate_slots: Array[StringName],
		unlocked: Dictionary[StringName, bool], upgrades: Dictionary[StringName, int] = {}) -> RunPreparation:
	if (catalog == null or not catalog.is_valid() or rune_slots.size() != RUNE_SLOTS
			or candidate_slots.size() != CANDIDATE_SLOTS):
		return null
	if not hero_id in available(catalog, CatalogEntry.Kind.HERO, unlocked):
		return null
	if not weapon_id in available(catalog, CatalogEntry.Kind.WEAPON, unlocked):
		return null
	var eligible_runes := available(catalog, CatalogEntry.Kind.RUNE, unlocked)
	var eligible_powers := available(catalog, CatalogEntry.Kind.POWER, unlocked)
	if not _valid_slots(rune_slots, eligible_runes) or not _valid_slots(candidate_slots, eligible_powers):
		return null
	for stat: StringName in upgrades:
		if stat not in UPGRADE_STATS or upgrades[stat] <= 0 or upgrades[stat] > UPGRADE_CAP_BASIS_POINTS:
			return null
	var result := RunPreparation.new()
	result._catalog = catalog
	result._hero = hero_id
	result._weapon = weapon_id
	result._runes = rune_slots.duplicate()
	result._candidates = candidate_slots.duplicate()
	result._eligible_powers = eligible_powers
	for id: StringName in unlocked:
		if not id.is_empty() and unlocked[id]:
			result._unlocked.append(id)
	result._unlocked.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	for stat: StringName in UPGRADE_STATS:
		if upgrades.has(stat):
			result._upgrades[stat] = upgrades[stat]
	return result


static func available(catalog: DefinitionCatalog, kind: CatalogEntry.Kind,
		unlocked: Dictionary[StringName, bool]) -> Array[StringName]:
	var eligible: Array[StringName] = []
	if catalog == null:
		return eligible
	for id: StringName in catalog.ids_of_kind(kind):
		if _allows(catalog, catalog.lookup(id), unlocked):
			eligible.append(id)
	return eligible


func runes() -> Array[StringName]:
	return _runes.duplicate()


func candidates() -> Array[StringName]:
	return _candidates.duplicate()


func eligible_powers() -> Array[StringName]:
	return _eligible_powers.duplicate()


func upgrade_basis_points(stat: StringName) -> int:
	return _upgrades.get(stat, 0)


func checkpoint() -> Array:
	var result := [_hero, _weapon, runes(), candidates(), _unlocked.duplicate()]
	if not _upgrades.is_empty():
		result.append(_upgrades.duplicate())
	return result


static func reopen(catalog: DefinitionCatalog, image: Variant) -> RunPreparation:
	if (not image is Array or image.size() not in [5, 6] or not image[0] is StringName or not image[1] is StringName
			or not image[2] is Array or not image[3] is Array or not image[4] is Array):
		return null
	for slots: Array in [image[2], image[3], image[4]]:
		for id: Variant in slots:
			if not id is StringName:
				return null
	var unlocked: Dictionary[StringName, bool] = {}
	for id: StringName in image[4]:
		if id.is_empty() or unlocked.has(id):
			return null
		unlocked[id] = true
	var rune_slots: Array[StringName] = []
	rune_slots.assign(image[2])
	var candidate_slots: Array[StringName] = []
	candidate_slots.assign(image[3])
	var upgrades: Dictionary[StringName, int] = {}
	if image.size() == 6:
		var saved: Variant = image[5]
		if not saved is Dictionary or saved.size() > UPGRADE_STATS.size():
			return null
		for stat: Variant in saved:
			if not stat is StringName or not saved[stat] is int:
				return null
			upgrades[stat] = saved[stat]
	return select(catalog, image[0], image[1], rune_slots, candidate_slots, unlocked, upgrades)


static func _valid_slots(slots: Array[StringName], eligible: Array[StringName]) -> bool:
	var seen: Dictionary[StringName, bool] = {}
	for id: StringName in slots:
		if id.is_empty():
			continue
		if seen.has(id) or not id in eligible:
			return false
		seen[id] = true
	return true


static func _allows(catalog: DefinitionCatalog, definition: CatalogDefinition,
		unlocked: Dictionary[StringName, bool]) -> bool:
	if definition == null:
		return false
	match definition.eligibility:
		CatalogEntry.Eligibility.STARTER:
			pass
		CatalogEntry.Eligibility.DISCOVERY, CatalogEntry.Eligibility.OWNERSHIP:
			if not unlocked.get(definition.id, false):
				return false
		_:
			return false
	for prerequisite: CatalogDefinition.Reference in definition.prerequisites:
		if not _allows(catalog, catalog.resolve(prerequisite), unlocked):
			return false
	return true
