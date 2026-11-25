class_name VisualAsset
extends Resource
## Presentation-only bindings. Gameplay owns footprints, contact and timing.

enum Layer { GROUND, ACTOR, OVERHEAD }
enum Facing { FIXED, RIGHT }

@export var visual_id: StringName
@export var frames: SpriteFrames
@export var frame_size: Vector2i
@export var foot_pixel: Vector2
@export var pixels_per_unit: float = 1.0
@export var facing: Facing
@export var sockets: Dictionary[StringName, Vector2] = {} # Relative to the foot in logical units.
@export var layer: Layer
@export var occludes_actor: bool


## Apply to a dedicated view whose origin is the authoritative foot position.
func bind_view(view: AnimatedSprite2D) -> void:
	view.sprite_frames = frames
	view.centered = false
	view.offset = -foot_pixel
	view.scale = Vector2.ONE / pixels_per_unit
