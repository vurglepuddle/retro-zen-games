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
	# Stars ARE bombs by nature — no aura marker on them; they still
	# detonate with the full BOOM when matched.
	if level == 7 and special_type == SPECIAL_BOMB:
		return
	match special_type:
		SPECIAL_BOMB:
			_draw_bomb_indicator()
		SPECIAL_CROSS:
			_draw_cross_indicator()
		SPECIAL_COLOR_BOMB:
			_draw_color_bomb_indicator()


# Smoldering ember: breathing core, three orbiting sparks with fading
# tails, and embers drifting up off the gem.
func _draw_bomb_indicator() -> void:
	var t := _effect_phase
	var pulse := sin(t * TAU * 1.1) * 0.5 + 0.5

	var ember := Color(1.0, 0.45, 0.06, 0.20 + pulse * 0.12)
	_draw_diamond(Vector2.ZERO, 40.0 + pulse * 3.0, ember, true)
	_draw_diamond_outline(Vector2.ZERO, 44.0, Color(0.62, 0.14, 0.02, 0.55), 3.0)

	for s in range(3):
		var ang := t * TAU * 0.35 + float(s) * TAU / 3.0
		for k in range(3):
			var trail_ang := ang - float(k) * 0.22
			var p := Vector2(cos(trail_ang), sin(trail_ang)) * 40.0
			var size := 6.0 - float(k) * 1.5
			_draw_pixel_rect(p, Vector2(size, size),
				Color(1.0, 0.8, 0.25, 0.85 - float(k) * 0.3))

	for e in range(3):
		var cycle := fmod(t * 0.9 + float(e) * 0.33, 1.0)
		var ex := sin((t + float(e) * 1.7) * 2.1) * 10.0 + (float(e) - 1.0) * 14.0
		var ey := 30.0 - cycle * 52.0
		_draw_pixel_rect(Vector2(ex, ey), Vector2(4, 4),
			Color(1.0, 0.55, 0.1, (1.0 - cycle) * 0.7))


# Charged lightning: jagged arcs along both axes that re-roll their shape
# several times a second, with pulsing diamond caps at the four ends.
func _draw_cross_indicator() -> void:
	var t := _effect_phase
	var pulse := sin(t * TAU * 1.8) * 0.5 + 0.5
	var tick := floorf(t * 9.0)

	var glow := Color(0.10, 0.45, 1.0, 0.30 + pulse * 0.12)
	var core := Color(0.85, 0.97, 1.0, 0.85)

	_draw_lightning(Vector2(-46, 0), Vector2(46, 0), tick, glow, core)
	_draw_lightning(Vector2(0, -46), Vector2(0, 46), tick + 31.0, glow, core)

	for p in [Vector2(-46, 0), Vector2(46, 0), Vector2(0, -46), Vector2(0, 46)]:
		_draw_diamond(p, 5.0 + pulse * 3.0, Color(0.55, 0.85, 1.0, 0.8), true)


# A jagged 5-segment bolt between two points; `seed_t` re-rolls the jitter.
func _draw_lightning(a: Vector2, b: Vector2, seed_t: float, glow: Color, core: Color) -> void:
	var points := PackedVector2Array()
	points.append(a)
	var dir := b - a
	var norm := Vector2(-dir.y, dir.x).normalized()
	for i in range(1, 5):
		var f := float(i) / 5.0
		var jitter := (_hash01(Vector2(seed_t, float(i))) - 0.5) * 14.0
		points.append(a + dir * f + norm * jitter)
	points.append(b)
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], glow, 5.0, false)
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], core, 2.0, false)


func _hash01(p: Vector2) -> float:
	return fposmod(sin(p.dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0)


# Void aura: breathing violet glow, a slowly counter-rotating constellation
# of arcane motes with faint trails, and sparkle pixels drifting upward.
func _draw_color_bomb_indicator() -> void:
	var t := _effect_phase
	var pulse := sin(t * TAU * 0.55) * 0.5 + 0.5

	var void_outer := Color(0.45, 0.10, 0.70, 0.16 + pulse * 0.10)
	var void_inner := Color(0.72, 0.30, 1.00, 0.20 + pulse * 0.10)
	_draw_diamond(Vector2.ZERO, 44.0 + pulse * 3.0, void_outer, true)
	_draw_diamond(Vector2.ZERO, 32.0 + pulse * 4.0, void_inner, true)
	_draw_diamond_outline(Vector2.ZERO, 46.0, Color(0.55, 0.18, 0.85, 0.5), 2.0)

	# Orbits opposite to the bomb's sparks, with a gentle radius wobble.
	for s in range(4):
		var ang := -t * TAU * 0.22 + float(s) * TAU / 4.0
		var radius := 40.0 + sin(t * TAU * 0.4 + float(s) * 1.3) * 4.0
		var p := Vector2(cos(ang), sin(ang)) * radius
		_draw_diamond(p, 4.0 + pulse * 1.5, Color(0.95, 0.7, 1.0, 0.8), true)
		var trail := Vector2(cos(ang + 0.3), sin(ang + 0.3)) * radius
		_draw_pixel_rect(trail, Vector2(3, 3), Color(0.8, 0.45, 1.0, 0.45))

	for e in range(4):
		var cycle := fmod(t * 0.7 + float(e) * 0.25, 1.0)
		var ex := sin(t * 0.9 + float(e) * 2.3) * 26.0
		var ey := 24.0 - cycle * 48.0
		_draw_pixel_rect(Vector2(ex, ey), Vector2(3, 3),
			Color(0.9, 0.6, 1.0, (1.0 - cycle) * 0.6))


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


func _draw_closed_lines(points: PackedVector2Array, color: Color, width: float) -> void:
	for i in range(points.size()):
		draw_line(points[i], points[(i + 1) % points.size()], color, width, false)


func _draw_pixel_rect(center: Vector2, size: Vector2, color: Color) -> void:
	draw_rect(Rect2(center - size * 0.5, size), color, true)


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
		# Unbounded on purpose: wrapping (the old fmod 4.0) snapped the
		# orbiting sparks backward every 4 s because the orbit angle isn't
		# periodic over that window.
		_effect_phase += delta
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
