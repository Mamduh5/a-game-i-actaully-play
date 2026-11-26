class_name ProfileProgression
extends RefCounted
## Personal progression from the opened profile's durable claims. Claims for
## discovery or knowledge are recorded by the authoritative award producer.

enum Access { UNAVAILABLE, LOCKED, DISCOVERED, OWNED, STARTER }
enum Knowledge { UNKNOWN, RUMORED, PARTIAL, IDENTIFIED, VERIFIED }

class Recipe:
	var id: StringName
	var stage: Knowledge
	var base: StringName
	var catalyst: StringName
	var catalyst_capability: StringName
	var components: Array[StringName] = []
	var runes: Array[StringName] = []

const PREPARATION_KINDS := [CatalogEntry.Kind.HERO, CatalogEntry.Kind.WEAPON, CatalogEntry.Kind.RUNE,
	CatalogEntry.Kind.POWER]

var _store: ProfileStore
var _identity: String
var _catalog: DefinitionCatalog


static func open(store: ProfileStore, catalog: DefinitionCatalog) -> ProfileProgression:
	if store == null or store.identity().is_empty() or catalog == null or not catalog.is_valid():
		return null
	var result := ProfileProgression.new()
	result._store = store
	result._identity = store.identity()
	result._catalog = catalog
	return result


func definition(id: StringName) -> CatalogDefinition:
	return _catalog.lookup(id)


func discovery_claim(id: StringName) -> String:
	var content := definition(id)
	if (content == null or content.kind not in PREPARATION_KINDS
			or content.eligibility not in [CatalogEntry.Eligibility.DISCOVERY, CatalogEntry.Eligibility.OWNERSHIP]):
		return ""
	return "progression/discovery/%s" % id


func ownership_claim(id: StringName) -> String:
	var content := definition(id)
	if content == null or content.kind not in PREPARATION_KINDS or content.eligibility != CatalogEntry.Eligibility.OWNERSHIP:
		return ""
	return "progression/ownership/%s" % id


func recipe_claim(id: StringName, stage: Knowledge) -> String:
	var form := definition(id)
	if (form == null or stage not in [Knowledge.RUMORED, Knowledge.PARTIAL, Knowledge.IDENTIFIED, Knowledge.VERIFIED]
			or form.kind not in [CatalogEntry.Kind.EVOLUTION, CatalogEntry.Kind.FUSION]
			or (form.kind == CatalogEntry.Kind.EVOLUTION and stage == Knowledge.IDENTIFIED)):
		return ""
	return "progression/recipe/%s/%d" % [id, stage]


func access_to(id: StringName) -> Access:
	var content := definition(id)
	if content == null or content.kind not in PREPARATION_KINDS or not ready():
		return Access.UNAVAILABLE
	if content.eligibility == CatalogEntry.Eligibility.STARTER:
		return Access.STARTER
	if has_claim(ownership_claim(id)):
		return Access.OWNED
	if has_claim(discovery_claim(id)):
		return Access.DISCOVERED
	return Access.LOCKED


func preparation_unlocks() -> Dictionary[StringName, bool]:
	var result: Dictionary[StringName, bool] = {}
	if not ready():
		return result
	for kind: CatalogEntry.Kind in PREPARATION_KINDS:
		for id: StringName in _catalog.ids_of_kind(kind):
			var access := access_to(id)
			if access == Access.OWNED or (access == Access.DISCOVERED
					and definition(id).eligibility == CatalogEntry.Eligibility.DISCOVERY):
				result[id] = true
	return result


func prepare(hero: StringName, weapon: StringName, runes: Array[StringName],
		candidates: Array[StringName]) -> RunPreparation:
	if not ready():
		return null
	return RunPreparation.select(_catalog, hero, weapon, runes, candidates, preparation_unlocks())


## Unknown forms are absent from the projection. The catalog contains full
## requirements for validation. Only earned knowledge exposes those fields.
func recipe(id: StringName) -> Recipe:
	for value: int in range(Knowledge.VERIFIED, Knowledge.UNKNOWN, -1):
		var stage := value as Knowledge
		if not has_claim(recipe_claim(id, stage)):
			continue
		var seen := Recipe.new()
		seen.id = id
		seen.stage = stage
		if stage >= Knowledge.IDENTIFIED:
			var form := definition(id)
			if form.kind == CatalogEntry.Kind.EVOLUTION:
				seen.base = form.base.id
				seen.catalyst = form.catalyst.id
				seen.catalyst_capability = form.catalyst_capability
			else:
				for component: CatalogDefinition.Reference in form.components:
					seen.components.append(component.id)
				for rune: CatalogDefinition.Reference in form.fusion_runes:
					seen.runes.append(rune.id)
		return seen
	return null


func same_profile() -> bool:
	return _store.identity() == _identity


func ready() -> bool:
	return same_profile() and not _store.checkpoint().is_empty()


func has_claim(key: String) -> bool:
	return not key.is_empty() and same_profile() and _store.lookup_claim(key).status == ProfileStore.CommitResult.COMMITTED
