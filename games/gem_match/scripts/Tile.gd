#Tile.gd
extends Area2D
class_name Tile

@export var level: int = 1: set = set_level, get = get_level
var row: int
var col: int
var game: Node

# Maps level number to animation name in the SpriteFrames resource.
const ANIM_NAMES := {
	1: "1_pearl",
	2: "2_yellow",
	3: "3_green",
	4: "4_pink",
	5: "5_blue",
	6: "6_star"
}

# Idle-spin state machine (runs in _process).
var _idle_timer: float = 0.0
var _spin_timer: float = 0.0
var _spinning: bool = false

# Hint pulsing — set by Game when this tile is part of a hint pair.
var _hinting: bool = false
var _hint_phase: float = 0.0

@onready var _anim: AnimatedSprite2D = $Tile


func _ready() -> void:
	input_pickable = true
	# Hide the legacy SVG Sprite2D — visuals now come from the AnimatedSprite2D.
	var sprite := get_node_or_null("Sprite")
	if sprite:
		sprite.visible = false
	_update_animation()
	_idle_timer = randf_range(3.0, 15.0)


func set_level(v: int) -> void:
	level = clamp(v, 1, ANIM_NAMES.size())
	_update_animation()


func get_level() -> int:
	return level


func _update_animation() -> void:
	# _anim may be null before _ready (property setter fires at init time).
	var anim: AnimatedSprite2D = _anim
	if anim == null:
		anim = get_node_or_null("Tile") as AnimatedSprite2D
	if anim == null:
		return
	var anim_name: String = ANIM_NAMES.get(level, "1_pearl")
	if anim.sprite_frames != null and anim.sprite_frames.has_animation(anim_name):
		anim.animation = anim_name
	anim.stop()
	anim.frame = 0


# Called by Game to start/stop the hint pulse on this tile.
func start_hint() -> void:
	_hinting = true
	_hint_phase = 0.0


func stop_hint() -> void:
	_hinting = false
	_hint_phase = 0.0
	scale = Vector2.ONE


# Each tile independently decides when to play its spin animation so the board
# looks alive without all gems spinning in sync.
func _process(delta: float) -> void:
	# Hint pulse overrides the idle-spin scale and takes visual priority.
	if _hinting:
		_hint_phase += delta * TAU * 1.5   # 1.5 Hz gentle pulse
		var p := sin(_hint_phase) * 0.5 + 0.5   # 0 → 1
		scale = Vector2(1.0 + p * 0.15, 1.0 + p * 0.15)
		# Still allow the animation to spin during hint for extra liveliness.

	if _anim == null:
		return
	if _spinning:
		_spin_timer -= delta
		if _spin_timer <= 0.0:
			_spinning = false
			_anim.stop()
			_anim.frame = 0
			_idle_timer = randf_range(5.0, 20.0)
	else:
		_idle_timer -= delta
		if _idle_timer <= 0.0:
			_spinning = true
			_spin_timer = 1.1   # ~15 frames at 14 fps = one full rotation
			_anim.play()


func update_position(cell_size: Vector2) -> void:
	position = Vector2(
		col * cell_size.x + cell_size.x / 2.0,
		row * cell_size.y + cell_size.y / 2.0
	)


# On press, tell Game which tile was pressed and where.
# Game._input() tracks the drag globally from there.
func _input_event(_viewport, event, _shape_idx) -> void:
	if game == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		game.start_drag(self, event.position)
	elif event is InputEventScreenTouch and event.pressed:
		game.start_drag(self, event.position)
