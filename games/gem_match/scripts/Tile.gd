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

# Maps level (tier) to animation name in the SpriteFrames resource. The
# animation names are historical; with the v3 art the tiers run moonstone ->
# emerald -> sapphire -> topaz -> teal star -> heart -> sun. Tiers 1-6 spawn;
# the sun is only reached by upgrading and explodes when matched (max tier),
# which keeps hearts and suns rarer on the board.
const ANIM_NAMES := {
	1: "1_pearl",    # moonstone diamond
	2: "3_green",    # emerald drop
	3: "5_blue",     # sapphire egg
	4: "6_red",      # fire topaz
	5: "7_star",     # teal (aqua) star
	6: "4_pink",     # rose heart
	7: "2_yellow"    # citrine sun: max tier
}

# Idle-spin state machine.
var _idle_timer: float = 0.0
var _spin_timer: float = 0.0
var _spinning:   bool  = false

# Hint pulsing.
var _hinting:    bool  = false
var _hint_phase: float = 0.0

const FX_FRAMES := preload("res://games/gem_match/assets/fx/fx_frames.tres")
var _aura: AnimatedSprite2D = null
var _star_drift_timer: float = 3.0

# Timed mode: matching this gem adds `time_bonus` seconds to the clock.
var time_bonus: int = 0
var _bonus_label: Label = null

# Locked gems: can't be swapped or matched until a neighbouring match or a
# special blast breaks the lock. Animations "locked", "glint" and "break" live
# in lock_frames.tres over lock_4x.png. Source art: art_src/gem_match/locks/.
const LOCK_FRAMES := preload("res://games/gem_match/assets/locks/lock_frames.tres")
var locked: bool = false
var _lock_sprite: AnimatedSprite2D = null
var _lock_glint_timer: float = 0.0

@onready var _anim: AnimatedSprite2D = $Tile


func _ready() -> void:
	input_pickable = true
	# Hide the legacy SVG Sprite2D. Visuals come from the AnimatedSprite2D.
	var sprite := get_node_or_null("Sprite")
	if sprite:
		sprite.visible = false
	_update_animation()
	_idle_timer = randf_range(3.0, 15.0)
	if _anim:
		# End an idle spin exactly when one turn completes, so it lands on
		# frame 1 instead of flashing frame 2 before a timer snaps it back.
		_anim.animation_looped.connect(_on_spin_cycle_done)
		_anim.animation_finished.connect(_on_spin_cycle_done)


func _on_spin_cycle_done() -> void:
	if _spinning and special_type != SPECIAL_COLOR_BOMB:
		_end_spin()


func _end_spin() -> void:
	_spinning = false
	_anim.stop()
	_anim.frame = 0
	_idle_timer = randf_range(5.0, 20.0)


# ----- Lock overlay ---------------------------------------------------------

func set_locked(v: bool) -> void:
	locked = v
	if v:
		if _lock_sprite == null:
			_lock_sprite = AnimatedSprite2D.new()
			_lock_sprite.name = "Lock"
			_lock_sprite.sprite_frames = LOCK_FRAMES
			_lock_sprite.z_index = 2
			_lock_sprite.animation_finished.connect(_on_lock_animation_finished)
			add_child(_lock_sprite)
		_lock_sprite.visible = true
		_lock_sprite.rotation = 0.0
		_lock_sprite.play("locked")
		_lock_glint_timer = randf_range(2.0, 8.0)
		if _spinning and _anim:
			_end_spin()
		set_time_bonus(0)
	elif _lock_sprite != null:
		_lock_sprite.visible = false


# The lock breaks with its own animation; the gem is free immediately.
func unlock_animated() -> void:
	if not locked:
		return
	locked = false
	if _lock_sprite != null:
		_lock_sprite.rotation = 0.0
		_lock_sprite.play("break")


# A match close by (but not touching) startles the padlock: a little hop.
func flinch_lock(delay: float = 0.0) -> void:
	if _lock_sprite == null or not locked:
		return
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(_lock_sprite, "position:y", -8.0, 0.07) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_lock_sprite, "rotation", -0.12, 0.07)
	tw.tween_property(_lock_sprite, "position:y", 0.0, 0.18) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_lock_sprite, "rotation", 0.0, 0.18)


# Feedback when the player tries to move a locked gem.
func rattle_lock() -> void:
	if _lock_sprite == null or not locked:
		return
	var tw := create_tween()
	for a in [0.16, -0.13, 0.09, -0.05, 0.0]:
		tw.tween_property(_lock_sprite, "rotation", a, 0.045)


func _on_lock_animation_finished() -> void:
	if _lock_sprite == null:
		return
	if _lock_sprite.animation == &"break":
		_lock_sprite.visible = false
	elif locked:
		_lock_sprite.play("locked")


func set_level(v: int) -> void:
	level = clamp(v, 1, ANIM_NAMES.size())
	# Upgrading always resets the special type; caller sets it afterwards if needed.
	special_type  = SPECIAL_NONE
	_update_animation()
	_update_aura()


func get_level() -> int:
	return level


# Stamp the gem as a special and update the visual marker.
func set_special(type: int) -> void:
	special_type = type
	_update_aura()
	# COLOR_BOMB shows its own looping animation alongside the void marker.
	if type == SPECIAL_COLOR_BOMB:
		var anim: AnimatedSprite2D = _anim if _anim != null \
			else get_node_or_null("Tile") as AnimatedSprite2D
		if anim != null and anim.sprite_frames != null \
				and anim.sprite_frames.has_animation("sp_heart"):
			anim.animation = "sp_heart"
			anim.play()


# Timed mode: stamp a "+N" seconds bonus on this gem — golden vetka text
# with a dark outline, gently pulsing until the gem is matched.
func set_time_bonus(v: int) -> void:
	time_bonus = v
	if v <= 0:
		if _bonus_label:
			_bonus_label.visible = false
		return
	if _bonus_label == null:
		_bonus_label = Label.new()
		var ls := LabelSettings.new()
		ls.font = load("res://assets/font/vetka.ttf")
		ls.font_size = 36
		ls.font_color = Color(1.0, 0.85, 0.25)
		ls.outline_size = 9
		ls.outline_color = Color(0.28, 0.13, 0.0, 0.95)
		_bonus_label.label_settings = ls
		_bonus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_bonus_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_bonus_label.size = Vector2(100, 44)
		_bonus_label.position = Vector2(-50, -22)
		_bonus_label.pivot_offset = Vector2(50, 22)
		_bonus_label.z_index = 6
		add_child(_bonus_label)
		var tw := create_tween().set_loops()
		tw.tween_property(_bonus_label, "scale", Vector2(1.18, 1.18), 0.55) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(_bonus_label, "scale", Vector2.ONE, 0.55) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bonus_label.text = "+%d" % v
	_bonus_label.visible = true


# Special gems wear a looping pixel-art aura drawn behind the gem: flames for
# BOMB, crackling arcs for CROSS, a violet halo with orbiting stars for the
# COLOR_BOMB moon. Art: assets/fx/fx_frames.tres (source art_src/gem_match/fx/).
func _update_aura() -> void:
	var anim_name := ""
	# Suns (max tier) ARE bombs by nature: no aura on them, they still detonate when matched.
	if not (level == 7 and special_type == SPECIAL_BOMB):
		match special_type:
			SPECIAL_BOMB:
				anim_name = "aura_fire"
			SPECIAL_CROSS:
				anim_name = "aura_spark"
			SPECIAL_COLOR_BOMB:
				anim_name = "aura_void"
	if anim_name == "":
		if _aura != null:
			_aura.visible = false
			_aura.stop()
		return
	if _aura == null:
		_aura = AnimatedSprite2D.new()
		_aura.name = "Aura"
		_aura.sprite_frames = FX_FRAMES
		_aura.z_index = -1          # behind every gem, above the board art
		add_child(_aura)
	_aura.visible = true
	if _aura.animation != anim_name or not _aura.is_playing():
		_aura.play(anim_name)
		_aura.frame = randi() % _aura.sprite_frames.get_frame_count(anim_name)


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

	# COLOR_BOMB: sp_heart loops continuously. Skip idle-spin logic. Now and
	# then the moon sheds a star that drifts onto a neighbouring gem.
	if special_type == SPECIAL_COLOR_BOMB:
		if not _anim.is_playing():
			_anim.play()
		_star_drift_timer -= delta
		if _star_drift_timer <= 0.0:
			_star_drift_timer = randf_range(2.5, 6.0)
			if game != null and game.has_method("moon_star_drift"):
				game.moon_star_drift(self)
		return

	# A locked gem holds still; its padlock glints now and then instead.
	if locked:
		_lock_glint_timer -= delta
		if _lock_glint_timer <= 0.0 and _lock_sprite != null:
			_lock_sprite.play("glint")
			_lock_glint_timer = randf_range(4.0, 10.0)
		return

	if _spinning:
		# Fallback only: the loop/finish signal normally ends the spin first.
		_spin_timer -= delta
		if _spin_timer <= 0.0:
			_end_spin()
	else:
		_idle_timer -= delta
		if _idle_timer <= 0.0:
			_spinning  = true
			_spin_timer = 1.6
			_anim.frame = 0
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
