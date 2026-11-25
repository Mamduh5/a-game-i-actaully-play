class_name CatalogRecipeValidator
extends RefCounted
## Checks whether authored exact forms and Fusions can share an attainable build.
## Inputs have already passed the catalog's structural reference checks.

const POWER_SLOTS := 10
const RUNE_SLOTS := 2

var _definitions: Dictionary[StringName, CatalogDefinition]


func _init(definitions: Dictionary[StringName, CatalogDefinition]) -> void:
	_definitions = definitions


func can_build(goals: Array[StringName], evolution_order: Array[StringName]) -> bool:
	var forms: Dictionary[StringName, CatalogDefinition] = {}
	var fusions: Array[CatalogDefinition] = []
	var fused_slots: Dictionary[StringName, CatalogDefinition] = {}
	var seen: Dictionary[StringName, bool] = {}
	for id: StringName in goals:
		var definition: CatalogDefinition = _definitions.get(id)
		if definition == null or seen.has(id):
			return false
		seen[id] = true
		match definition.kind:
			CatalogEntry.Kind.EVOLUTION:
				if not _add_form(forms, definition):
					return false
			CatalogEntry.Kind.FUSION:
				fusions.append(definition)
				for link: CatalogDefinition.Reference in definition.components:
					var form: CatalogDefinition = _definitions[link.id]
					if fused_slots.has(form.base.id) or not _add_form(forms, form):
						return false
					fused_slots[form.base.id] = definition
			_:
				return false
	return _complete(forms, fusions, fused_slots, evolution_order)


func _add_form(forms: Dictionary[StringName, CatalogDefinition], form: CatalogDefinition) -> bool:
	if forms.has(form.base.id) and forms[form.base.id] != form:
		return false
	forms[form.base.id] = form
	return true


func _complete(
		forms: Dictionary[StringName, CatalogDefinition],
		fusions: Array[CatalogDefinition],
		fused_slots: Dictionary[StringName, CatalogDefinition],
		order: Array[StringName]
) -> bool:
	var bases: Dictionary[StringName, bool] = {}
	var runes: Dictionary[StringName, bool] = {}
	var missing: CatalogDefinition
	for form: CatalogDefinition in forms.values():
		bases[form.base.id] = true
		var catalyst: CatalogDefinition = _definitions[form.catalyst.id]
		if catalyst.kind == CatalogEntry.Kind.RUNE:
			runes[catalyst.id] = true
			continue
		bases[catalyst.id] = true
		if form.catalyst_capability in catalyst.capabilities:
			continue
		var provider: CatalogDefinition = forms.get(catalyst.id)
		if provider == null:
			missing = form
		elif form.catalyst_capability not in provider.capabilities:
			return false
	if bases.size() > POWER_SLOTS or runes.size() > RUNE_SLOTS:
		return false
	if missing != null:
		for provider: CatalogDefinition in _definitions.values():
			if provider.kind != CatalogEntry.Kind.EVOLUTION or provider.base.id != missing.catalyst.id:
				continue
			if missing.catalyst_capability not in provider.capabilities:
				continue
			var expanded := forms.duplicate()
			expanded[provider.base.id] = provider
			if _complete(expanded, fusions, fused_slots, order):
				return true
		return false
	if not _retains_external_catalysts(forms, fusions, fused_slots):
		return false
	var active: Dictionary[StringName, CatalogDefinition] = {}
	if not order.is_empty():
		return _matches_order(forms, order, active)
	var candidates: Array[CatalogDefinition] = []
	candidates.assign(forms.values())
	return _find_order(candidates, active, 0, {})


func _matches_order(
		forms: Dictionary[StringName, CatalogDefinition],
		order: Array[StringName],
		active: Dictionary[StringName, CatalogDefinition]
) -> bool:
	if order.size() != forms.size():
		return false
	for id: StringName in order:
		var form: CatalogDefinition = _definitions.get(id)
		if form == null or form.kind != CatalogEntry.Kind.EVOLUTION:
			return false
		if forms.get(form.base.id) != form or active.has(form.base.id) or not _eligible(form, active):
			return false
		active[form.base.id] = form
	return true


## Each subset determines the active capabilities. Cache failed subsets.
func _find_order(
		forms: Array[CatalogDefinition],
		active: Dictionary[StringName, CatalogDefinition],
		mask: int,
		dead_ends: Dictionary[int, bool]
) -> bool:
	if active.size() == forms.size():
		return true
	if dead_ends.has(mask):
		return false
	for index: int in forms.size():
		var bit := 1 << index
		var form: CatalogDefinition = forms[index]
		if mask & bit or not _eligible(form, active):
			continue
		active[form.base.id] = form
		if _find_order(forms, active, mask | bit, dead_ends):
			return true
		active.erase(form.base.id)
	dead_ends[mask] = true
	return false


func _eligible(form: CatalogDefinition, active: Dictionary[StringName, CatalogDefinition]) -> bool:
	if form.catalyst_capability.is_empty():
		return true # Required runes were reserved before acquisition.
	var provider: CatalogDefinition = active.get(form.catalyst.id, _definitions[form.catalyst.id])
	return form.catalyst_capability in provider.capabilities


func _retains_external_catalysts(
		forms: Dictionary[StringName, CatalogDefinition],
		fusions: Array[CatalogDefinition],
		fused_slots: Dictionary[StringName, CatalogDefinition]
) -> bool:
	for fusion: CatalogDefinition in fusions:
		for link: CatalogDefinition.Reference in fusion.components:
			var form: CatalogDefinition = _definitions[link.id]
			if form.catalyst_capability.is_empty():
				continue
			var catalyst_base: StringName = form.catalyst.id
			var occupying_fusion: CatalogDefinition = fused_slots.get(catalyst_base)
			if occupying_fusion == fusion:
				continue # Reciprocal component catalysts are consumed by this selection.
			if occupying_fusion == null:
				if not _eligible(form, forms):
					return false
				continue
			var first: CatalogDefinition = _definitions[occupying_fusion.components[0].id]
			var retained := occupying_fusion.first_component_capabilities
			if first.base.id != catalyst_base:
				retained = occupying_fusion.second_component_capabilities
			if form.catalyst_capability not in retained:
				return false
	return true
