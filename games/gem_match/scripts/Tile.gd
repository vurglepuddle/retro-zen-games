#Tile.gd
extends Area2D
class_name Tile

# Special gem types. Set after set_level() to mark a gem as powered up.
const SPECIAL_NONE       := 0   # plain gem
const SPECIAL_BOMB       := 1   # 3x3 explosion, ember marker
const SPECIAL_CROSS      := 2   # row+col blast, lightning marker
const SPECIAL_COLOR_BOMB := 3   # destroy all of tier, sp_heart animation

@export var level: int = 1: set = set_level, get = get_level
var row:          int
var col:          int
var game:         Node
var special_type: int = SPECIAL_NONE

# Maps level number to animation name in the SpriteFrames resource.
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

var _effect_phase: float = 0.0

@onready var _anim: AnimatedSprite2D = $Tile


func _ready() -> void:
	input_pickable = true
	# Hide the legacy SVG Sprite2D. Visuals come from the AnimatedSprite2D.
	var sprite := get_node_or_null("Sprite")
	if sprite:
		sprite.visible = false
	_update_animation()
	_idle_timer = randf_range(3.0, 15.0)


func set_level(v: int) -> void:
	level = clamp(v, 1, ANIM_NAMES.size())
	# Upgrading always resets the special type; caller sets it afterwards if needed.
	special_type  = SPECIAL_NONE
	_effect_phase = 0.0
	queue_redraw()
	_update_animation()


func get_level() -> int:
	return level


# Stamp the gem as a special and update the visual marker.
func set_special(type: int) -> void:
	special_type = type
	queue_redraw()
	# COLOR_BOMB shows its own looping animation alongside the void marker.
	if type == SPECIAL_COLOR_BOMB:
		var anim: AnimatedSprite2D = _anim if _anim != null \
			else get_node_or_null("Tile") as AnimatedSprite2D
		if anim != null and anim.sprite_frames != null \
				and anim.sprite_frames.has_animation("sp_heart"):
			anim.animation = "sp_heart"
			anim.play()


# Draw pixel-art special markers behind the gem sprite.
func _draw() -> void:
	match special_type:
		SPECIAL_BOMB:
			_draw_bomb_indicator()
		SPECIAL_CROSS:
			_draw_cross_indicator()
		SPECIAL_COLOR_BOMB:
			_draw_color_bomb_indicator()


func _draw_bomb_indicator() -> void:
	var pulse := sin(_effect_phase * TAU * 1.25) * 0.5 + 0.5
	var ember := Color(1.0, 0.42, 0.04, 0.30 + pulse * 0.10)
	var hot := Color(1.0, 0.86, 0.18, 0.72)
	var dark := Color(0.55, 0.10, 0.02, 0.72)

	_draw_diamond(Vector2.ZERO, 42.0, ember, true)
	_draw_diamond_outline(Vector2.ZERO, 42.0, dark, 4.0)
	_draw_diamond_outline(Vector2.ZERO, 34.0 + pulse * 3.0, hot, 2.0)

	for p in [
		Vector2(-35, -30), Vector2(35, -30),
		Vector2(-35, 30), Vector2(35, 30),
		Vector2(0, -42), Vector2(0, 42)
	]:
		_draw_pixel_rect(p, Vector2(7, 7), hot)

	var lick_color := Color(1.0, 0.58, 0.08, 0.64)
	_draw_triangle(
		Vector2(-22, 37),
		Vector2(-12, 26 + pulse * 5.0),
		Vector2(-4, 37),
		lick_color
	)
	_draw_triangle(
		Vector2(10, 38),
		Vector2(22, 24 + (1.0 - pulse) * 5.0),
		Vector2(30, 38),
		lick_color
	)


func _draw_cross_indicator() -> void:
	var pulse := sin(_effect_phase * TAU * 1.8) * 0.5 + 0.5
	var glow := Color(0.06, 0.50, 1.0, 0.30 + pulse * 0.10)
	var core := Color(0.78, 0.96, 1.0, 0.82)
	var edge := Color(0.06, 0.18, 0.90, 0.68)

	draw_line(Vector2(-46, 0), Vector2(46, 0), glow, 10.0, false)
	draw_line(Vector2(0, -46), Vector2(0, 46), glow, 10.0, false)
	draw_line(Vector2(-46, 0), Vector2(46, 0), edge, 4.0, false)
	draw_line(Vector2(0, -46), Vector2(0, 46), edge, 4.0, false)
	draw_line(Vector2(-36, 0), Vector2(36, 0), core, 2.0, false)
	draw_line(Vector2(0, -36), Vector2(0, 36), core, 2.0, false)

	for p in [Vector2(-42, 0), Vector2(42, 0), Vector2(0, -42), Vector2(0, 42)]:
		_draw_diamond(p, 7.0 + pulse * 2.0, core, true)
	for p in [Vector2(-28, -28), Vector2(28, -28), Vector2(-28, 28), Vector2(28, 28)]:
		_draw_pixel_rect(p, Vector2(5, 5), Color(0.34, 0.74, 1.0, 0.68))


func _draw_color_bomb_indicator() -> void:
	var pulse := sin(_effect_phase * TAU) * 0.5 + 0.5
	var void_color := Color(0.22, 0.02, 0.34, 0.38 + pulse * 0.10)
	var rim := Color(0.78, 0.34, 1.0, 0.72)
	var spark := Color(1.0, 0.86, 1.0, 0.72)

	_draw_starburst(Vector2.ZERO, 43.0, 24.0 + pulse * 4.0, void_color)
	_draw_diamond_outline(Vector2.ZERO, 39.0, rim, 3.0)
	_draw_diamond_outline(Vector2.ZERO, 27.0 + pulse * 3.0, spark, 2.0)

	for p in [
		Vector2(-38, -4), Vector2(38, 4),
		Vector2(-4, -38), Vector2(4, 38),
		Vector2(-28, 28), Vector2(28, -28)
	]:
		_draw_pixel_rect(p, Vector2(6, 6), spark)


func _draw_diamond(center: Vector2, radius: float, color: Color, filled: bool) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -radius),
		center + Vector2(radius, 0),
		center + Vector2(0, radius),
		center + Vector2(-radius, 0)
	])
	if filled:
		draw_colored_polygon(points, color)
	else:
		_draw_closed_lines(points, color, 2.0)


func _draw_diamond_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	_draw_closed_lines(PackedVector2Array([
		center + Vector2(0, -radius),
		center + Vector2(radius, 0),
		center + Vector2(0, radius),
		center + Vector2(-radius, 0)
	]), color, width)


func _draw_starburst(center: Vector2, outer_radius: float, inner_radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(8):
		var angle := -PI * 0.5 + float(i) * TAU / 8.0
		var radius := outer_radius if i % 2 == 0 else inner_radius
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)


func _draw_closed_lines(points: PackedVector2Array, color: Color, width: float) -> void:
	for i in range(points.size()):
		draw_line(points[i], points[(i + 1) % points.size()], color, width, false)


func _draw_pixel_rect(center: Vector2, size: Vector2, color: Color) -> void:
	draw_rect(Rect2(center - size * 0.5, size), color, true)


func _draw_triangle(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([a, b, c]), color)


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
	if special_type != SPECIAL_NONE:
		_effect_phase = fmod(_effect_phase + delta, 4.0)
		queue_redraw()

	if _hinting:
		_hint_phase += delta * TAU * 1.5
		var p := sin(_hint_phase) * 0.5 + 0.5
		scale = Vector2(1.0 + p * 0.15, 1.0 + p * 0.15)

	if _anim == null:
		return

	# COLOR_BOMB: sp_heart loops continuously. Skip idle-spin logic.
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
