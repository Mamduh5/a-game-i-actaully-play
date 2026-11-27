class_name EncounterViewCodec
extends RefCounted
## Presentation fields extend a scoped snapshot. Actor positions and hostile
## warnings come from RecipientView, including its independent filtering.

const MAX_RECORDS := 32
const MAX_QUANTITY_HEX := 512
const POINT_FIELDS := [&"mines", &"darts", &"lances", &"familiars"]
const CUES := [&"W01", &"W02", &"W03", &"W04", &"W06", &"W09", StarterCombatRules.SIPHON, StarterCombatRules.HARMONIC_BURST,
	StarterCombatRules.TIME_FRACTURE, StarterCombatRules.TEMPORAL_ECHO, StarterCombatRules.CLOSE_CALL,
	StarterCombatRules.SINGULARITY, StarterCombatRules.CRIMSON_OFFERING,
	&"R02.lightning", &"RP02.blood_wake", &"RP03.storm_relay"]
const DIRECTIONAL := [&"W01", &"W02", &"W04", &"W06", &"W09", StarterCombatRules.HARMONIC_BURST,
	&"R02.lightning", &"RP02.blood_wake", &"RP03.storm_relay"]


static func fields(view: StarterEncounter.View, visible: Dictionary) -> Dictionary:
	if view.barrier == null or not visible.has(String(view.player.id)):
		return {}
	var roster := {}
	var fighters: Array[StarterEncounter.Fighter] = [view.player]
	fighters.append_array(view.others)
	for fighter: StarterEncounter.Fighter in fighters:
		var id := String(fighter.id)
		if not visible.has(id):
			continue
		if fighter.hp == null or fighter.maximum == null or roster.has(id):
			return {}
		roster[id] = [fighter.radius, QuantityCodec.encode(fighter.hp).hex_encode(),
			QuantityCodec.encode(fighter.maximum).hex_encode(), fighter.enemy]
	if roster.size() != visible.size() or roster.size() > MAX_RECORDS:
		return {}
	var effects: Array[Array] = []
	for cue: StarterCombat.Cue in view.cues:
		effects.append([String(cue.id), _coordinates(cue.position), _coordinates(cue.heading),
			cue.reach, cue.radius, cue.half_angle, str(cue.impact), str(cue.ends)])
	if effects.size() > MAX_RECORDS or view.tethers.size() > MAX_RECORDS:
		return {}
	var links: Array[Array] = []
	for segment: Array in view.tethers:
		if segment.size() != 2:
			return {}
		links.append([_coordinates(segment[0]), _coordinates(segment[1])])
	var points: Array[Array] = []
	for name: StringName in POINT_FIELDS:
		var source: Array[RealmSweep.Point] = view.get(name)
		if source.size() > MAX_RECORDS:
			return {}
		var row: Array[Array] = []
		for at: RealmSweep.Point in source:
			row.append(_coordinates(at))
		points.append(row)
	return {"seat": String(view.player.id), "selected": String(view.selected) if visible.has(String(view.selected)) else "",
		"ready": view.manual_ready, "defeated": view.defeated, "cleared": view.cleared,
		"roster": roster, "barrier": QuantityCodec.encode(view.barrier).hex_encode(),
		"cues": effects, "points": points, "links": links}


static func read(fields_value: Variant, sample: RecipientView.Snapshot) -> StarterEncounter.View:
	if not fields_value is Dictionary or fields_value.size() != 10:
		return null
	var seat: Variant = fields_value.get("seat")
	var selected: Variant = fields_value.get("selected")
	var roster: Variant = fields_value.get("roster")
	if (not seat is String or not sample.party.has(seat) or not sample.actors.has(seat)
			or not selected is String or (not selected.is_empty() and (selected == seat or not sample.actors.has(selected)))
			or not roster is Dictionary or roster.size() != sample.actors.size() or roster.size() > MAX_RECORDS
			or not fields_value.get("ready") is bool or not fields_value.get("defeated") is bool
			or not fields_value.get("cleared") is bool):
		return null
	var view := StarterEncounter.View.new()
	view.tick = sample.tick
	view.selected = StringName(selected)
	view.manual_ready = fields_value["ready"]
	view.defeated = fields_value["defeated"]
	view.cleared = fields_value["cleared"]
	view.barrier = _amount(fields_value.get("barrier"))
	if view.barrier == null:
		return null
	for id: String in sample.actors:
		var fighter := _read_fighter(id, sample.actors[id], roster.get(id))
		if fighter == null or fighter.enemy == sample.party.has(id):
			return null
		if id == seat:
			view.player = fighter
		else:
			view.others.append(fighter)
	for warning: RecipientView.Warning in sample.warnings.values():
		if warning.activation >= warning.impact:
			return null
		var tell := WorldEnemy.Threat.new()
		tell.center = warning.end
		tell.radius = warning.radius
		tell.start_tick = warning.activation
		tell.impact_tick = warning.impact
		view.threats.append(tell)
	if (not _read_cues(view, fields_value.get("cues"))
			or not _read_points(view, fields_value.get("points"))
			or not _read_links(view, fields_value.get("links"))):
		return null
	return view


static func _read_fighter(id: String, at: RealmSweep.Point, row: Variant) -> StarterEncounter.Fighter:
	if not row is Array or row.size() != 4 or not _size(row[0]) or row[0] <= 0.0 or not row[3] is bool:
		return null
	var hp := _amount(row[1])
	var maximum := _amount(row[2])
	if hp == null or maximum == null or maximum.sign_value <= 0 or hp.compare(maximum) > 0:
		return null
	var fighter := StarterEncounter.Fighter.new()
	fighter.id = StringName(id)
	fighter.at = at
	fighter.radius = row[0]
	fighter.hp = hp
	fighter.maximum = maximum
	fighter.enemy = row[3]
	return fighter


static func _read_cues(view: StarterEncounter.View, rows: Variant) -> bool:
	if not rows is Array or rows.size() > MAX_RECORDS:
		return false
	for row: Variant in rows:
		if (not row is Array or row.size() != 8 or not row[0] is String or row[0] not in CUES
				or not _size(row[3]) or not _size(row[4]) or not _size(row[5]) or row[5] > PI):
			return false
		var cue := StarterCombat.Cue.new()
		cue.id = StringName(row[0])
		cue.position = _point(row[1])
		cue.heading = _point(row[2])
		cue.reach = row[3]
		cue.radius = row[4]
		cue.half_angle = row[5]
		cue.impact = RecipientView._unsigned(row[6], RunAuthority.MAX_TICK)
		cue.ends = RecipientView._unsigned(row[7], RunAuthority.MAX_TICK)
		if (cue.position == null or (cue.heading == null and (cue.id in DIRECTIONAL or row[2] != []))
				or (cue.heading != null and (absf(cue.heading.x) > 1.0 or absf(cue.heading.y) > 1.0))
				or cue.impact < 0 or cue.ends < cue.impact):
			return false
		view.cues.append(cue)
	return true


static func _read_points(view: StarterEncounter.View, rows: Variant) -> bool:
	if not rows is Array or rows.size() != POINT_FIELDS.size():
		return false
	for i: int in POINT_FIELDS.size():
		var row: Variant = rows[i]
		if not row is Array or row.size() > MAX_RECORDS:
			return false
		var points: Array[RealmSweep.Point] = []
		for pair: Variant in row:
			var point := _point(pair)
			if point == null:
				return false
			points.append(point)
		view.set(POINT_FIELDS[i], points)
	return true


static func _read_links(view: StarterEncounter.View, rows: Variant) -> bool:
	if not rows is Array or rows.size() > MAX_RECORDS:
		return false
	for row: Variant in rows:
		if not row is Array or row.size() != 2:
			return false
		var start := _point(row[0])
		var end := _point(row[1])
		if start == null or end == null:
			return false
		view.tethers.append([start, end])
	return true


static func _amount(encoded: Variant) -> Quantity:
	if (not encoded is String or encoded.length() > MAX_QUANTITY_HEX or encoded.length() % 2 != 0
			or not encoded.is_valid_hex_number()):
		return null
	var value := QuantityCodec.decode(encoded.hex_decode())
	if value == null or value.sign_value < 0 or QuantityCodec.encode(value).hex_encode() != encoded:
		return null
	return value


static func _size(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0.0 and value <= 1000000.0


static func _point(pair: Variant) -> RealmSweep.Point:
	if not pair is Array or pair.size() != 2:
		return null
	var point := RecipientView._read_point(pair[0], pair[1])
	return point if point != null and absf(point.x) <= 1000000.0 and absf(point.y) <= 1000000.0 else null


static func _coordinates(at: RealmSweep.Point) -> Array:
	return [at.x, at.y] if at != null else []
