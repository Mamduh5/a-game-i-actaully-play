class_name CatalogDefinition
extends RefCounted
## A detached, read-only definition compiled from a typed authored Resource.

class Reference:
	var id: StringName:
		get: return _fields[0]
	var revision: int:
		get: return _fields[1]
	var _fields: Array

	func _init(source: CatalogReference) -> void:
		_fields = [source.target_id, source.target_revision] if source != null else [&"", 0]
		_fields.make_read_only()


var id: StringName:
	get: return _fields.id
var revision: int:
	get: return _fields.revision
var kind: CatalogEntry.Kind:
	get: return _fields.kind
var lifetime: CatalogEntry.Lifetime:
	get: return _fields.lifetime
var targeting: CatalogEntry.Targeting:
	get: return _fields.targeting
var eligibility: CatalogEntry.Eligibility:
	get: return _fields.eligibility
var source_family: StringName:
	get: return _fields.source_family
var prerequisites: Array[Reference]:
	get: return _fields.prerequisites
var references: Array[Reference]:
	get: return _fields.references
var ranks: Array[StringName]:
	get: return _fields.ranks
var capabilities: Array[StringName]:
	get: return _fields.capabilities
var base: Reference:
	get: return _fields.base
var catalyst: Reference:
	get: return _fields.catalyst
var catalyst_capability: StringName:
	get: return _fields.catalyst_capability
var components: Array[Reference]:
	get: return _fields.components
var first_component_capabilities: Array[StringName]:
	get: return _fields.first_component_capabilities
var second_component_capabilities: Array[StringName]:
	get: return _fields.second_component_capabilities

var _fields: Dictionary


func _init(source: CatalogEntry) -> void:
	var rank_ids := source.ranks.duplicate()
	rank_ids.make_read_only()
	var provided := source.capabilities.duplicate()
	provided.make_read_only()
	var retained_first := source.first_component_capabilities.duplicate()
	retained_first.make_read_only()
	var retained_second := source.second_component_capabilities.duplicate()
	retained_second.make_read_only()
	_fields = {
		"id": source.id,
		"revision": source.revision,
		"kind": source.kind,
		"lifetime": source.lifetime,
		"targeting": source.targeting,
		"eligibility": source.eligibility,
		"source_family": source.source_family,
		"prerequisites": _compile_links(source.prerequisites),
		"references": _compile_links(source.references),
		"ranks": rank_ids,
		"capabilities": provided,
		"base": Reference.new(source.base) if source.base != null else null,
		"catalyst": Reference.new(source.catalyst) if source.catalyst != null else null,
		"catalyst_capability": source.catalyst_capability,
		"components": _compile_links(source.components),
		"first_component_capabilities": retained_first,
		"second_component_capabilities": retained_second,
	}
	_fields.make_read_only()


func _compile_links(links: Array[CatalogReference]) -> Array[Reference]:
	var compiled: Array[Reference] = []
	for link: CatalogReference in links:
		compiled.append(Reference.new(link))
	compiled.make_read_only()
	return compiled
