class_name CatalogBundle
extends Resource
## The authored entry point for compiling a common versioned snapshot.

@export var revision: StringName
@export var entries: Array[CatalogEntry] = []


func compile() -> DefinitionCatalog:
	return DefinitionCatalog.compile(revision, entries)
