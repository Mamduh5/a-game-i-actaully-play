extends GutTest

const FixturePath := "res://dev/fixtures/catalog_reciprocal.tres"
const Kind := CatalogEntry.Kind
const ErrorCode := DefinitionCatalog.IssueCode


func test_text_resources_compile_and_two_owners_share_only_the_definition() -> void:
	var source := _fixture()
	var catalog := source.compile()
	assert_true(catalog.is_valid(), str(catalog.issues()))
	var form := catalog.lookup(&"E07A")
	assert_eq(catalog.resolve(form.base).id, &"P07")
	assert_eq(catalog.resolve(form.catalyst).id, &"P12")
	assert_eq(catalog.resolve(form.base).ranks[2], &"survival_instinct")
	assert_true(form.capabilities.is_read_only())
	assert_true(catalog.lookup(&"F06").components.is_read_only())
	var first := CatalogInstance.new(form, &"seat-a")
	var second := CatalogInstance.new(form, &"seat-b")
	first.activation_count += 1
	assert_same(first.definition, second.definition)
	assert_eq(first.activation_count, 1)
	assert_eq(second.activation_count, 0)
	assert_eq(second.owner_id, &"seat-b")
	_source(source, &"E07A").capabilities.clear()
	_source(source, &"E07A").catalyst.target_id = &"other"
	assert_eq(form.capabilities, [&"vital_exchange"])
	assert_eq(form.catalyst.id, &"P12")


func test_reciprocal_catalysts_work_in_both_orders_from_acquired_capabilities() -> void:
	var catalog := _fixture().compile()
	assert_true(catalog.can_build([&"F06"], [&"E07A", &"E12A"]))
	assert_true(catalog.can_build([&"F06"], [&"E12A", &"E07A"]))
	assert_false(catalog.can_build([&"F06"], [&"E07A", &"E07A"]))


func test_losing_capability_changes_order_and_two_losses_block_the_recipe() -> void:
	var source := _fixture()
	_source(source, &"E07A").capabilities.clear()
	var catalog := source.compile()
	assert_true(catalog.is_valid(), str(catalog.issues()))
	assert_false(catalog.can_build([&"F06"], [&"E07A", &"E12A"]))
	assert_true(catalog.can_build([&"F06"], [&"E12A", &"E07A"]))
	_source(source, &"E12A").capabilities.clear()
	catalog = source.compile()
	assert_false(catalog.is_valid())
	_assert_issue(catalog, &"F06", ErrorCode.UNREACHABLE_RECIPE, [&"E07A", &"E12A"])


func test_missing_duplicate_mismatched_and_incompatible_links_name_the_entries() -> void:
	var source := _fixture()
	var p07 := _source(source, &"P07")
	var form := _source(source, &"E12A")
	p07.revision = 2
	p07.references = [_ref(&"missing"), _ref(&"missing")]
	form.catalyst = _ref(&"F06")
	source.entries.append(p07)
	var catalog := source.compile()
	assert_false(catalog.is_valid())
	assert_null(catalog.lookup(&"P12"), "An invalid catalog is not published")
	_assert_issue(catalog, &"P07", ErrorCode.DUPLICATE_ID, [])
	_assert_issue(catalog, &"P07", ErrorCode.MISSING_REFERENCE, [&"missing"])
	_assert_issue(catalog, &"P07", ErrorCode.DUPLICATE_VALUE, [&"missing"])
	_assert_issue(catalog, &"E07A", ErrorCode.REVISION_MISMATCH, [&"P07"])
	_assert_issue(catalog, &"E12A", ErrorCode.INCOMPATIBLE_KIND, [&"F06"])


func test_circular_ownership_gates_are_distinct_from_mutual_content_references() -> void:
	var first := _entry(&"fixture.a", Kind.OTHER)
	var second := _entry(&"fixture.b", Kind.OTHER)
	first.references = [_ref(second.id)]
	second.references = [_ref(first.id)]
	assert_true(DefinitionCatalog.compile(&"test", [first, second]).is_valid())
	first.prerequisites = [_ref(second.id)]
	second.prerequisites = [_ref(first.id)]
	var catalog := DefinitionCatalog.compile(&"test", [first, second])
	_assert_issue(catalog, first.id, ErrorCode.CIRCULAR_PREREQUISITE, [first.id, second.id, first.id])


func test_two_legal_fusions_can_conflict_over_a_third_rune() -> void:
	var entries: Array[CatalogEntry] = [
		_entry(&"rune.one", Kind.RUNE), _entry(&"rune.two", Kind.RUNE), _entry(&"rune.three", Kind.RUNE),
	]
	var catalyst_ids: Array[StringName] = [&"rune.one", &"rune.one", &"rune.two", &"rune.three"]
	for index: int in catalyst_ids.size():
		var base := _entry(StringName("power.%d" % index), Kind.POWER)
		var form := _rune_form(StringName("form.%d" % index), base.id, catalyst_ids[index])
		entries.append(base)
		entries.append(form)
	entries.append(_fusion(&"fusion.a", &"form.0", &"form.1"))
	entries.append(_fusion(&"fusion.b", &"form.2", &"form.3"))
	var catalog := DefinitionCatalog.compile(&"test", entries)
	assert_true(catalog.is_valid(), str(catalog.issues()))
	assert_true(catalog.can_build([&"fusion.a"]))
	assert_true(catalog.can_build([&"fusion.b"]))
	assert_false(catalog.can_build([&"fusion.a", &"fusion.b"]))
	entries[10].catalyst.target_id = &"rune.one"
	catalog = DefinitionCatalog.compile(&"test", entries)
	assert_true(catalog.can_build([&"fusion.a", &"fusion.b"]))
	entries[11].fusion_runes = [_ref(&"rune.three")]
	catalog = DefinitionCatalog.compile(&"test", entries)
	assert_true(catalog.is_valid(), str(catalog.issues()))
	assert_true(catalog.can_build([&"fusion.a"]))
	assert_true(catalog.can_build([&"fusion.b"]))
	assert_false(catalog.can_build([&"fusion.a", &"fusion.b"]))


func test_build_cannot_select_two_forms_of_one_power_or_reuse_a_fused_slot() -> void:
	var source := _fixture()
	var rune := _entry(&"rune.control", Kind.RUNE)
	source.entries.append(rune)
	source.entries.append(_rune_form(&"E07B", &"P07", rune.id))
	source.entries.append(_fusion(&"fixture.overlap", &"E07B", &"E12A"))
	var catalog := source.compile()
	assert_true(catalog.is_valid(), str(catalog.issues()))
	assert_false(catalog.can_build([&"E07A", &"E07B"]))
	assert_false(catalog.can_build([&"F06", &"fixture.overlap"]))
	source.entries.append(_fusion(&"fixture.incompatible", &"E07A", &"E07B"))
	catalog = source.compile()
	_assert_issue(catalog, &"fixture.incompatible", ErrorCode.INCOMPATIBLE_KIND, [&"E07A", &"E07B", &"P07"])


func test_capability_introduced_by_a_form_requires_that_form_first() -> void:
	var source := _fixture()
	_source(source, &"P12").capabilities.clear()
	var catalog := source.compile()
	assert_true(catalog.is_valid(), str(catalog.issues()))
	assert_true(catalog.can_build([&"E07A"], [&"E12A", &"E07A"]))
	assert_false(catalog.can_build([&"E07A"], [&"E07A", &"E12A"]))
	_source(source, &"P07").capabilities.clear()
	catalog = source.compile()
	assert_false(catalog.is_valid(), "Both forms depending on the other's new capability has no starting move")


func test_fusion_requires_external_catalyst_to_survive_a_disjoint_fusion() -> void:
	var source := _fixture()
	var rune := _entry(&"rune.control", Kind.RUNE)
	var third := _entry(&"power.external", Kind.POWER)
	var fourth := _entry(&"power.fourth", Kind.POWER)
	third.capabilities = [&"external"]
	var external_form := _rune_form(&"form.external", third.id, rune.id)
	external_form.capabilities = [&"external"]
	var fourth_form := _rune_form(&"form.fourth", fourth.id, rune.id)
	var consuming := _fusion(&"fusion.external", external_form.id, fourth_form.id)
	var dependent := _source(source, &"E07A")
	dependent.catalyst = _ref(third.id)
	dependent.catalyst_capability = &"external"
	source.entries.append_array([rune, third, fourth, external_form, fourth_form, consuming])
	var catalog := source.compile()
	assert_true(catalog.is_valid(), str(catalog.issues()))
	assert_false(catalog.can_build([&"F06", consuming.id]))
	consuming.first_component_capabilities = [&"external"]
	catalog = source.compile()
	assert_true(catalog.can_build([&"F06", consuming.id]))
	external_form.capabilities.clear()
	catalog = source.compile()
	_assert_issue(catalog, consuming.id, ErrorCode.INVALID_FIELDS, [external_form.id, &"external"])


func test_five_distinct_rank_steps_are_required_from_a_power() -> void:
	var source := _fixture()
	var power := _source(source, &"P07")
	power.ranks.pop_back()
	var catalog := source.compile()
	_assert_issue(catalog, power.id, ErrorCode.INVALID_RANKS, [])
	power.ranks.append(power.ranks[2])
	catalog = source.compile()
	_assert_issue(catalog, power.id, ErrorCode.INVALID_RANKS, [])


func _fixture() -> CatalogBundle:
	return ResourceLoader.load(FixturePath, "", ResourceLoader.CACHE_MODE_IGNORE)


func _source(bundle: CatalogBundle, id: StringName) -> CatalogEntry:
	for entry: CatalogEntry in bundle.entries:
		if entry.id == id:
			return entry
	return null


func _entry(id: StringName, kind: CatalogEntry.Kind) -> CatalogEntry:
	var entry := CatalogEntry.new()
	entry.id = id
	entry.kind = kind
	entry.lifetime = CatalogEntry.Lifetime.RUN
	entry.targeting = CatalogEntry.Targeting.NONE
	entry.eligibility = CatalogEntry.Eligibility.OWNERSHIP
	entry.source_family = id
	if kind == Kind.POWER:
		entry.ranks = [&"base", &"rank_2", &"milestone_3", &"rank_4", &"milestone_5"]
	return entry


func _ref(id: StringName) -> CatalogReference:
	var link := CatalogReference.new()
	link.target_id = id
	return link


func _rune_form(id: StringName, base: StringName, rune: StringName) -> CatalogEntry:
	var form := _entry(id, Kind.EVOLUTION)
	form.eligibility = CatalogEntry.Eligibility.RUN_RECIPE
	form.base = _ref(base)
	form.catalyst = _ref(rune)
	return form


func _fusion(id: StringName, first: StringName, second: StringName) -> CatalogEntry:
	var definition := _entry(id, Kind.FUSION)
	definition.eligibility = CatalogEntry.Eligibility.RUN_RECIPE
	definition.components = [_ref(first), _ref(second)]
	return definition


func _assert_issue(catalog: DefinitionCatalog, id: StringName, code: DefinitionCatalog.IssueCode, related: Array) -> void:
	assert_has(catalog.issues(), {"id": id, "code": code, "related": related})
