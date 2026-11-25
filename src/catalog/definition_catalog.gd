class_name DefinitionCatalog
extends RefCounted
## One versioned catalog snapshot. A validation error blocks publication.

enum IssueCode {
	INVALID_REVISION, INVALID_ID, DUPLICATE_ID, INCOMPLETE_METADATA, DUPLICATE_VALUE,
	INVALID_FIELDS, INVALID_RANKS, MISSING_REFERENCE, REVISION_MISMATCH,
	INCOMPATIBLE_KIND, CIRCULAR_PREREQUISITE, TOO_MANY_FORMS, UNREACHABLE_RECIPE,
}

var revision: StringName:
	get: return _revision

var _revision: StringName
var _entries: Dictionary[StringName, CatalogDefinition] = {}
var _issues: Array[Dictionary] = []


static func compile(catalog_revision: StringName, sources: Array[CatalogEntry]) -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	catalog._revision = catalog_revision
	catalog._load(sources)
	return catalog


func is_valid() -> bool:
	return not _revision.is_empty() and _issues.is_empty()


func issues() -> Array[Dictionary]:
	return _issues.duplicate(true)


func lookup(id: StringName) -> CatalogDefinition:
	return _entries.get(id) if is_valid() else null


func ids_of_kind(kind: CatalogEntry.Kind) -> Array[StringName]:
	var ids: Array[StringName] = []
	if not is_valid():
		return ids
	for definition: CatalogDefinition in _entries.values():
		if definition.kind == kind:
			ids.append(definition.id)
	ids.sort()
	return ids


func resolve(reference: CatalogDefinition.Reference) -> CatalogDefinition:
	if reference == null:
		return null
	var definition := lookup(reference.id)
	return definition if definition != null and definition.revision == reference.revision else null


## Static reachability only. Reward timing, rank payment and ownership remain run rules.
func can_build(goals: Array[StringName], evolution_order: Array[StringName] = []) -> bool:
	return is_valid() and CatalogRecipeValidator.new(_entries).can_build(goals, evolution_order)


func _load(sources: Array[CatalogEntry]) -> void:
	if _revision.is_empty():
		_issue(&"", IssueCode.INVALID_REVISION)
	for source: CatalogEntry in sources:
		if source == null or not _is_id(source.id):
			_issue(&"" if source == null else source.id, IssueCode.INVALID_ID)
			continue
		if _entries.has(source.id):
			_issue(source.id, IssueCode.DUPLICATE_ID)
			continue
		_entries[source.id] = CatalogDefinition.new(source)

	var forms_by_base: Dictionary[StringName, Array] = {}
	for definition: CatalogDefinition in _entries.values():
		_validate_fields(definition)
		_check_links(definition.id, definition.prerequisites)
		_check_links(definition.id, definition.references)
		match definition.kind:
			CatalogEntry.Kind.EVOLUTION:
				_validate_evolution(definition, forms_by_base)
			CatalogEntry.Kind.FUSION:
				_validate_fusion(definition)
	if not _issues.is_empty():
		return
	var visited: Dictionary[StringName, bool] = {}
	for id: StringName in _entries:
		_visit(id, visited, [])
	if not _issues.is_empty():
		return
	var recipes := CatalogRecipeValidator.new(_entries)
	for definition: CatalogDefinition in _entries.values():
		if definition.kind in [CatalogEntry.Kind.EVOLUTION, CatalogEntry.Kind.FUSION]:
			if not recipes.can_build([definition.id], []):
				_issue(definition.id, IssueCode.UNREACHABLE_RECIPE, _recipe_ids(definition))


func _validate_fields(definition: CatalogDefinition) -> void:
	var id: StringName = definition.id
	if definition.revision < 1:
		_issue(id, IssueCode.INVALID_REVISION)
	if definition.lifetime == CatalogEntry.Lifetime.UNSET or definition.targeting == CatalogEntry.Targeting.UNSET:
		_issue(id, IssueCode.INCOMPLETE_METADATA)
	if definition.eligibility == CatalogEntry.Eligibility.UNSET:
		_issue(id, IssueCode.INCOMPLETE_METADATA)
	if definition.kind in [CatalogEntry.Kind.EVOLUTION, CatalogEntry.Kind.FUSION] \
			and not definition.prerequisites.is_empty():
		_issue(id, IssueCode.INVALID_FIELDS)
	for values: Array[StringName] in [
		definition.capabilities, definition.first_component_capabilities, definition.second_component_capabilities,
	]:
		if not _unique_values(values):
			_issue(id, IssueCode.DUPLICATE_VALUE, values)
	if definition.kind == CatalogEntry.Kind.POWER:
		if definition.ranks.size() != 5 or not _unique_values(definition.ranks):
			_issue(id, IssueCode.INVALID_RANKS)
	elif not definition.ranks.is_empty():
		_issue(id, IssueCode.INVALID_FIELDS)
	if definition.kind != CatalogEntry.Kind.EVOLUTION:
		if definition.base != null or definition.catalyst != null or not definition.catalyst_capability.is_empty():
			_issue(id, IssueCode.INVALID_FIELDS)
	if definition.kind != CatalogEntry.Kind.FUSION:
		if not definition.components.is_empty() or not definition.first_component_capabilities.is_empty() \
				or not definition.second_component_capabilities.is_empty():
			_issue(id, IssueCode.INVALID_FIELDS)
	if definition.kind in [CatalogEntry.Kind.POWER, CatalogEntry.Kind.WEAPON, +			CatalogEntry.Kind.EVOLUTION, CatalogEntry.Kind.FUSION] and definition.source_family.is_empty():
		_issue(id, IssueCode.INCOMPLETE_METADATA)


func _validate_evolution(form: CatalogDefinition, forms_by_base: Dictionary[StringName, Array]) -> void:
	var base := _check_link(form.id, form.base, [CatalogEntry.Kind.POWER])
	var catalyst := _check_link(form.id, form.catalyst, [CatalogEntry.Kind.POWER, CatalogEntry.Kind.RUNE])
	if form.eligibility != CatalogEntry.Eligibility.RUN_RECIPE:
		_issue(form.id, IssueCode.INCOMPLETE_METADATA)
	if base != null:
		if not forms_by_base.has(base.id):
			forms_by_base[base.id] = []
		var alternatives: Array = forms_by_base[base.id]
		alternatives.append(form.id)
		if alternatives.size() > 2:
			_issue(base.id, IssueCode.TOO_MANY_FORMS, alternatives)
	if catalyst != null and (
		(catalyst.kind == CatalogEntry.Kind.POWER and (form.catalyst_capability.is_empty() or catalyst == base))
		or (catalyst.kind == CatalogEntry.Kind.RUNE and not form.catalyst_capability.is_empty())
	):
		_issue(form.id, IssueCode.INVALID_FIELDS, [catalyst.id])


func _validate_fusion(fusion: CatalogDefinition) -> void:
	if fusion.eligibility != CatalogEntry.Eligibility.RUN_RECIPE:
		_issue(fusion.id, IssueCode.INCOMPLETE_METADATA)
	if fusion.components.size() != 2:
		_issue(fusion.id, IssueCode.INVALID_FIELDS, _recipe_ids(fusion))
		return
	var first := _check_link(fusion.id, fusion.components[0], [CatalogEntry.Kind.EVOLUTION])
	var second := _check_link(fusion.id, fusion.components[1], [CatalogEntry.Kind.EVOLUTION])
	_check_retained(fusion.id, first, fusion.first_component_capabilities)
	_check_retained(fusion.id, second, fusion.second_component_capabilities)
	if first != null and second != null and first.base != null and second.base != null:
		if first.base.id == second.base.id:
			_issue(fusion.id, IssueCode.INCOMPATIBLE_KIND, [first.id, second.id, first.base.id])


func _check_retained(id: StringName, component: CatalogDefinition, retained: Array[StringName]) -> void:
	if component == null:
		return
	for capability: StringName in retained:
		if capability not in component.capabilities:
			_issue(id, IssueCode.INVALID_FIELDS, [component.id, capability])


func _visit(id: StringName, visited: Dictionary[StringName, bool], path: Array[StringName]) -> void:
	if visited.has(id):
		return
	if id in path:
		var cycle := path.slice(path.find(id))
		cycle.append(id)
		_issue(id, IssueCode.CIRCULAR_PREREQUISITE, cycle)
		return
	path.append(id)
	var definition: CatalogDefinition = _entries[id]
	for link: CatalogDefinition.Reference in definition.prerequisites:
		_visit(link.id, visited, path)
	for required: StringName in _recipe_ids(definition):
		_visit(required, visited, path)
	path.pop_back()
	visited[id] = true


func _check_links(source_id: StringName, links: Array[CatalogDefinition.Reference]) -> void:
	var seen: Dictionary[StringName, bool] = {}
	for link: CatalogDefinition.Reference in links:
		_check_link(source_id, link)
		if seen.has(link.id):
			_issue(source_id, IssueCode.DUPLICATE_VALUE, [link.id])
		seen[link.id] = true


func _check_link(
		source_id: StringName,
		link: CatalogDefinition.Reference,
		kinds: Array[CatalogEntry.Kind] = []
) -> CatalogDefinition:
	if link == null:
		_issue(source_id, IssueCode.MISSING_REFERENCE)
		return null
	var target: CatalogDefinition = _entries.get(link.id)
	if target == null:
		_issue(source_id, IssueCode.MISSING_REFERENCE, [link.id])
		return null
	if link.revision != target.revision:
		_issue(source_id, IssueCode.REVISION_MISMATCH, [link.id])
	if not kinds.is_empty() and target.kind not in kinds:
		_issue(source_id, IssueCode.INCOMPATIBLE_KIND, [link.id])
		return null
	return target


func _recipe_ids(definition: CatalogDefinition) -> Array[StringName]:
	var ids: Array[StringName] = []
	if definition.base != null:
		ids.append(definition.base.id)
	if definition.catalyst != null:
		ids.append(definition.catalyst.id)
	for link: CatalogDefinition.Reference in definition.components:
		ids.append(link.id)
	return ids


func _issue(id: StringName, code: IssueCode, related: Array = []) -> void:
	_issues.append({"id": id, "code": code, "related": related.duplicate()})


func _unique_values(values: Array[StringName]) -> bool:
	var seen: Dictionary[StringName, bool] = {}
	for value: StringName in values:
		if value.is_empty() or seen.has(value):
			return false
		seen[value] = true
	return true


func _is_id(id: StringName) -> bool:
	if id.is_empty():
		return false
	for character: String in String(id):
		if character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-":
			return false
	return true
