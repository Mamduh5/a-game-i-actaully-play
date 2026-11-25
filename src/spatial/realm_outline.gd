class_name RealmOutline
extends RefCounted
## Bakes a Godot-authored closed polygon into one scalar realm coordinate frame.

class Edge:
	var first: RealmSweep.Point
	var last: RealmSweep.Point
	var bounds: RealmBounds


static func bake(vertices: PackedVector2Array, local_transform: Transform2D,
		module_origin: RealmSweep.Point) -> Array[Edge]:
	if vertices.size() < 3 or module_origin == null:
		return []
	var points: Array[RealmSweep.Point] = []
	for authored: Vector2 in vertices:
		var x := module_origin.x + (local_transform.origin.x + local_transform.x.x * authored.x
			+ local_transform.y.x * authored.y)
		var y := module_origin.y + (local_transform.origin.y + local_transform.x.y * authored.x
			+ local_transform.y.y * authored.y)
		if not is_finite(x) or not is_finite(y):
			return []
		points.append(RealmSweep.Point.new(x, y))
	var edges: Array[Edge] = []
	for index: int in points.size():
		var first: RealmSweep.Point = points[index]
		var last: RealmSweep.Point = points[(index + 1) % points.size()]
		if first.x == last.x and first.y == last.y:
			return []
		var edge := Edge.new()
		edge.first = first
		edge.last = last
		edge.bounds = RealmBounds.from_sweep(first.x, first.y, last.x, last.y, 0)
		edges.append(edge)
	return edges
