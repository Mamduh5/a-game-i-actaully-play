class_name CatalogEntry
extends Resource
## Editable source for one stable definition. Compile before consumer use.

enum Kind { HERO, WEAPON, RUNE, POWER, EVOLUTION, FUSION, OTHER }
enum Lifetime { UNSET, PREPARATION, RUN, INSTANCE, PROFILE }
enum Targeting { UNSET, NONE, SELF, AUTOMATIC, DELIBERATE }
enum Eligibility { UNSET, STARTER, DISCOVERY, OWNERSHIP, RUN_RECIPE }

@export var id: StringName
@export var revision: int = 1
@export var kind: Kind = Kind.OTHER
@export var lifetime: Lifetime
@export var targeting: Targeting
@export var eligibility: Eligibility
@export var source_family: StringName

## Hard ownership gates and ordinary references have different cycle rules.
@export var prerequisites: Array[CatalogReference] = []
@export var references: Array[CatalogReference] = []

## Ordered rank entries. Rank 3 and 5 IDs identify their authored milestones.
@export var ranks: Array[StringName] = []
## The full set of capabilities this slot offers in this form.
@export var capabilities: Array[StringName] = []

@export var base: CatalogReference
@export var catalyst: CatalogReference
@export var catalyst_capability: StringName

## Fusion components are ordered to scope their retained capabilities.
@export var components: Array[CatalogReference] = []
@export var fusion_runes: Array[CatalogReference] = []
@export var first_component_capabilities: Array[StringName] = []
@export var second_component_capabilities: Array[StringName] = []
