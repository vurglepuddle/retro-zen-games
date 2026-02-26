#Tile.gd
extends Area2D
class_name Tile

# Special gem types — set after set_level() to mark a gem as powered-up.
const SPECIAL_NONE       := 0   # plain gem
const SPECIAL_BOMB       := 1   # 3×3 explosion  — orange indicator
const SPECIAL_CROSS      := 2   # row+col blast   — blue indicator
const SPECIAL_COLOR_BOMB := 3   # destroy all of tier — sp_heart animation

const INDICATOR_COLORS: Array[Color] = [
	Color(0.0,  0.0,  0.0,  0.0 ),  # NONE       — invisible
	Color(1.0,  0.52, 0.08, 0.70),  # BOMB       — orange
	Color(0.18, 0.52, 1.0,  0.70),  # CROSS      — blue
	Color(0.0,  0.0,  0.0,  0.0 ),  # COLOR_BOMB — no rect; uses sp_heart anim
]

@export var level: int = 1: set = set_level, get = get_level
var row:          int
var col:          int
var game:         Node
var special_type: int = SPECIAL_NONE

# Maps level number → animation name in the SpriteFrames resource.
const ANIM_NAMES := {
	1: "1_pearl",
	2: "2_yellow",
	3: "3_green",
	4: "4_pink",
	5: "5_blue",
	6: "6_red",
	7: "7_star"
}

# Idle-spin state machine.
var _idle_timer: float = 0.0
var _spin_timer: float = 0.0
var _spinning:   bool  = false

# Hint pulsing.
var _hinting:    bool  = false
var _hint_phase: float = 0.0

# Current indicator colour (driven by special_type).
var _indicator_color: Color = Color(0, 0, 0, 0)

@onready var _anim: AnimatedSprite2D = $Tile


func _ready() -> void:
	input_pickable = true
	# Hide the legacy SVG Sprite2D — visuals come from the AnimatedSprite2D.
	var sprite := get_node_or_null("Sprite")
	if sprite:
		sprite.visible = false
	_update_animation()
	_idle_timer = randf_range(3.0, 15.0)


func set_level(v: int) -> void:
	level = clamp(v, 1, ANIM_NAMES.size())
	# Upgrading always resets the special type; caller sets it afterwards if needed.
	special_type     = SPECIAL_NONE
	_indicator_color = Color(0, 0, 0, 0)
	queue_redraw()
	_update_animation()


func get_level() -> int:
	return level


# Stamp the gem as a special and update the visual indicator tile.
func set_special(type: int) -> void:
	special_type = type
	_indicator_color = INDICATOR_COLORS[type] if type < INDICATOR_COLORS.size() \
		else Color(0, 0, 0, 0)
	queue_redraw()
	# COLOR_BOMB shows its own looping animation instead of an indicator square.
	if type == SPECIAL_COLOR_BOMB:
		var anim: AnimatedSprite2D = _anim if _anim != null \
			else get_node_or_null("Tile") as AnimatedSprite2D
		if anim != null and anim.sprite_frames != null \
				and anim.sprite_frames.has_animation("sp_heart"):
			anim.animation = "sp_heart"
			anim.play()


# Draw the coloured indicator square behind the gem sprite.
func _draw() -> void:
	if _indicator_color.a > 0.01:
		draw_rect(Rect2(-34, -34, 68, 68), _indicator_color, true)


func _update_animation() -> void:
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


func start_hint() -> void:
	_hinting    = true
	_hint_phase = 0.0


func stop_hint() -> void:
	_hinting    = false
	_hint_phase = 0.0
	scale       = Vector2.ONE


func _process(delta: float) -> void:
	if _hinting:
		_hint_phase += delta * TAU * 1.5
		var p := sin(_hint_phase) * 0.5 + 0.5
		scale = Vector2(1.0 + p * 0.15, 1.0 + p * 0.15)

	if _anim == null:
		return

	# COLOR_BOMB: sp_heart loops continuously — skip idle-spin logic.
	if special_type == SPECIAL_COLOR_BOMB:
		if not _anim.is_playing():
			_anim.play()
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
			_spinning  = true
			_spin_timer = 1.1
			_anim.play()


func update_position(cell_size: Vector2) -> void:
	position = Vector2(
		col * cell_size.x + cell_size.x / 2.0,
		row * cell_size.y + cell_size.y / 2.0
	)


func _input_event(_viewport, event, _shape_idx) -> void:
	if game == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		game.start_drag(self, event.position)
	elif event is InputEventScreenTouch and event.pressed:
		game.start_drag(self, event.position)
