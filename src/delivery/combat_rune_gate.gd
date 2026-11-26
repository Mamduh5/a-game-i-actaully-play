class_name CombatRuneGate
extends RefCounted
## The prepared owner and exact catalog rune IDs gate runtime pair effects.

var _owner: StringName
var _runes: Array[StringName] = []


static func create(catalog: DefinitionCatalog, owner: StringName, equipped: Array[StringName]) -> CombatRuneGate:
	if catalog == null or not catalog.is_valid() or owner.is_empty() or equipped.size() > 2:
		return null
	var gate := CombatRuneGate.new()
	gate._owner = owner
	for id: StringName in equipped:
		var definition := catalog.lookup(id)
		if definition == null or definition.kind != CatalogEntry.Kind.RUNE or id in gate._runes:
			return null
		gate._runes.append(id)
	return gate


func allows(hit: CombatKernel.Hit, first_rune: StringName, second_rune: StringName, source_compatible: bool) -> bool:
	return (source_compatible and first_rune != second_rune and first_rune in _runes and second_rune in _runes
		and hit != null and hit.accepted and hit.origin != null and hit.origin.owner == _owner
		and hit.origin.provenance == CombatOrigin.Provenance.SEAT)


## PR10 uses the earlier set only on the parent's original target life.
static func lightning_prestate(parent: CombatKernel.Hit, child: CombatKernel.Hit,
		pre_parent: CombatBleedLedger.Prestate, pre_child: CombatBleedLedger.Prestate) -> CombatBleedLedger.Prestate:
	if (parent == null or child == null or not parent.accepted or parent.event <= 0 or child.parent != parent.event
			or child.wave <= parent.wave or not child.accepted):
		return null
	return pre_parent if child.target == parent.target and child.target_life == parent.target_life else pre_child
