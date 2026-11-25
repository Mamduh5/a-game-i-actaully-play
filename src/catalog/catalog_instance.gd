class_name CatalogInstance
extends RefCounted
## Per-owner runtime state. Using the same definition does not share counters.

var definition: CatalogDefinition:
	get: return _definition
var owner_id: StringName:
	get: return _owner_id

var activation_count: int

var _definition: CatalogDefinition
var _owner_id: StringName


func _init(compiled: CatalogDefinition, owner: StringName) -> void:
	_definition = compiled
	_owner_id = owner
