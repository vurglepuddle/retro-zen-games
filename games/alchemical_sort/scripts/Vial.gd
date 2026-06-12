#Vial.gd (alchemical_sort)
# Represents one alchemical bottle.  Instantiated purely in code — no .tscn.
class_name Vial
extends Control

signal tapped(vial: Vial)

# ---- configuration ----------------------------------------------------------
const MAX_LAYERS      := 5   # color layers each vial can hold
const SHEET_COLS      := 7   # columns in liquid_colors_all.png
const SHEET_ROWS      := 2   # rows    in liquid_colors_all.png
const BOTTLE_PAD_TOP  := 14  # pixels bottle art covers above the liquid
var VIAL_W: int       = 72   # derived from bottle.png in _build_visuals()
var VIAL_H: int       = 176  # derived from bottle.png in _build_visuals()

# ---- state ------------------------------------------------------------------
# _layers[0] = bottom-most color id, _layers[top_index()] = topmost.
# Color id 0 = empty slot.  IDs 1..N correspond to the game's color palette.
var _layers: Array[int] = []
var _palette: Array[Color] = []

# ---- fog-of-war state -------------------------------------------------------
# When _fog_mode is true, only layers at index >= _fog_reveal_from are visible;
# everything below is drawn in a neutral gray ("unknown").
# _fog_reveal_from only ever decreases — once a layer is revealed it stays so.
var _fog_mode: bool = false
var _fog_reveal_from: int = 0

# ---- visuals (built in setup) -----------------------------------------------
var _layer_rects:    Array[TextureRect]   = []
var _atlas_textures: Array[AtlasTexture]  = []   # one entry per color id (0-based)
var _outline: Panel = null
var _cell_h: float = 32.0   # liquid layer height; derived from the sheet in _build_visuals()

# ---- magic visuals ------------------------------------------------------------
var _select_motes:   CPUParticles2D = null  # essence pixels rising while selected
var _complete_motes: CPUParticles2D = null  # sparse sparkle on completed vials
var _gleam: TextureRect = null              # additive bottle flash (masked by bottle art)
var _outline_tween: Tween = null
var _gleam_tween: Tween = null
var _mote_tex: ImageTexture = null
var _completed: bool = false

# ---- capacity / cauldron ------------------------------------------------------
# Slots at index >= capacity are permanently blocked (always 0). The Zen
# cauldron is a capacity-1 vessel that accepts any color, one layer at a time.
var capacity: int = MAX_LAYERS
var is_cauldron: bool = false

# Per-color-id modulate tints (alchemical batch variation); empty = no tint.
var _tints: Array[Color] = []

# Catalyst rune: rarely, a vial bears a faint glowing sigil; completing it
# releases the catalyst (Game.gd handles the gift).
var has_rune: bool = false
var _rune: Control = null


func _init() -> void:
	custom_minimum_size = Vector2(VIAL_W, VIAL_H)
	size = Vector2(VIAL_W, VIAL_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = Vector2(VIAL_W * 0.5, VIAL_H * 0.5)


func _ready() -> void:
	# Re-apply size after Godot's layout pass, which can overwrite the value
	# set in _init() for Control children added via code.  This ensures the
	# full bottle rect is the tap target, not just the rendered outline.
	# Also future-proofs against transparent bottle sprites: the outer Control
	# owns all input so transparent pixels never leak clicks to the background.
	size = Vector2(VIAL_W, VIAL_H)
	mouse_filter = Control.MOUSE_FILTER_STOP


# Call after adding to scene tree; configures layers and builds visuals.
func setup(initial_layers: Array[int], color_palette: Array[Color]) -> void:
	_palette = color_palette.duplicate()
	_layers.clear()
	for v in initial_layers:
		_layers.append(v)
	while _layers.size() < MAX_LAYERS:
		_layers.append(0)
	_build_visuals()


# ---- public data API --------------------------------------------------------

func is_empty() -> bool:
	return top_index() < 0


func is_full() -> bool:
	return _layers[capacity - 1] != 0


func is_pure() -> bool:
	# True if all non-zero slots share the same color id (empty counts as pure).
	var first := 0
	for v in _layers:
		if v != 0:
			if first == 0:
				first = v
			elif v != first:
				return false
	return true


# Index of the highest occupied slot, or -1 if completely empty.
func top_index() -> int:
	for i in range(MAX_LAYERS - 1, -1, -1):
		if _layers[i] != 0:
			return i
	return -1


func top_color() -> int:
	var i := top_index()
	return _layers[i] if i >= 0 else 0


# How many consecutive same-color layers sit at the very top.
func top_run_count() -> int:
	var tc := top_color()
	if tc == 0:
		return 0
	var count := 0
	for i in range(MAX_LAYERS - 1, -1, -1):
		if _layers[i] == tc:
			count += 1
		elif _layers[i] == 0:
			continue   # skip empty slots above the run
		else:
			break
	return count


func free_slots() -> int:
	var count := 0
	for i in range(capacity):
		if _layers[i] == 0:
			count += 1
	return count


# Local Y of the current liquid surface — where a poured drop should land.
# Empty vial → the glass bottom.
func surface_y() -> float:
	return BOTTLE_PAD_TOP + (MAX_LAYERS - 1 - top_index()) * _cell_h


# ---- fog of war -------------------------------------------------------------

# Call after setup() to activate fog mode.  Only the current top color-run is
# visible; layers below it are rendered as an opaque gray until uncovered.
func enable_fog() -> void:
	_fog_mode = true
	_fog_reveal_from = _top_run_start()
	_refresh_visuals()


# Call from Game.gd after animate_pour_out() completes so the newly exposed
# layer becomes visible.  _fog_reveal_from only ever decreases.
func reveal_top() -> void:
	if not _fog_mode:
		return
	_fog_reveal_from = mini(_fog_reveal_from, _top_run_start())
	_refresh_visuals()


# Catalyst gift in Mystery mode: peel one extra fog layer.
func reveal_one_more() -> void:
	if not _fog_mode:
		return
	_fog_reveal_from = maxi(0, _fog_reveal_from - 1)
	_refresh_visuals()


# Index of the first layer in the current top color-run (the lowest layer that
# shares the same color as the topmost occupied slot, with no gap in between).
func _top_run_start() -> int:
	var ti := top_index()
	if ti < 0:
		return 0          # vial is empty — everything "revealed"
	var tc := _layers[ti]
	var i := ti
	while i > 0 and _layers[i - 1] == tc:
		i -= 1
	return i


# ---- alchemical tints ---------------------------------------------------------

func _tint_for(cid: int) -> Color:
	if cid >= 1 and cid <= _tints.size():
		return _tints[cid - 1]
	return Color.WHITE


# Tinted palette color for particle effects, so droplets/motes match the
# liquid as currently displayed.
func tinted_color(cid: int) -> Color:
	var base := _palette[cid - 1] if cid >= 1 and cid <= _palette.size() else Color.WHITE
	return base * _tint_for(cid)


# Apply per-color-id tints to all visible liquid layers. Called every frame
# while Zen drift is active, so it only touches RGB — the alpha channel
# belongs to the pour fade animations.
func set_tints(tints: Array[Color]) -> void:
	_tints = tints
	if _layer_rects.is_empty():
		return  # before _build_visuals(); _set_layer_color applies tints later
	for i in range(MAX_LAYERS):
		if _layers[i] == 0:
			continue
		if _fog_mode and i < _fog_reveal_from:
			continue
		var t := _tint_for(_layers[i])
		var rect := _layer_rects[i]
		rect.modulate = Color(t.r, t.g, t.b, rect.modulate.a)


# ---- snapshot / undo --------------------------------------------------------

func snapshot() -> Array[int]:
	var snap: Array[int] = []
	for v in _layers:
		snap.append(v)
	return snap


func get_layers() -> Array[int]:
	return _layers.duplicate()


func restore(snap: Array[int]) -> void:
	for i in range(MAX_LAYERS):
		_layers[i] = snap[i]
	_refresh_visuals()


# ---- animated pour ----------------------------------------------------------

func animate_pour_out(amount: int) -> void:
	# Identify the top `amount` occupied layer indices.
	var indices: Array[int] = []
	for i in range(MAX_LAYERS - 1, -1, -1):
		if _layers[i] != 0 and indices.size() < amount:
			indices.append(i)

	var tw := create_tween()
	tw.set_parallel(true)
	for idx in indices:
		tw.tween_property(_layer_rects[idx], "modulate:a", 0.0, 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished

	for idx in indices:
		_layers[idx] = 0
		_layer_rects[idx].modulate.a = 0.0


func animate_pour_in(color_id: int, amount: int) -> void:
	# Identify the lowest `amount` empty slots (blocked slots never qualify).
	var indices: Array[int] = []
	for i in range(capacity):
		if _layers[i] == 0 and indices.size() < amount:
			indices.append(i)

	for idx in indices:
		_layers[idx] = color_id
		if color_id >= 1 and color_id <= _atlas_textures.size():
			_layer_rects[idx].texture = _atlas_textures[color_id - 1]
		_layer_rects[idx].modulate = _tint_for(color_id)
		_layer_rects[idx].modulate.a = 0.0
		if _layer_rects[idx].get_child_count() > 0:
			_layer_rects[idx].get_child(0).visible = true

	var tw := create_tween()
	tw.set_parallel(true)
	for idx in indices:
		tw.tween_property(_layer_rects[idx], "modulate:a", 1.0, 0.14) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished


# Scale-bounce + glass gleam + golden burst when a vial becomes pure and full.
func celebrate() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.14, 1.14), 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if _gleam:
		_kill_gleam_tween()
		_gleam_tween = create_tween()
		_gleam_tween.tween_property(_gleam, "modulate:a", 0.55, 0.10) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_gleam_tween.tween_property(_gleam, "modulate:a", 0.0, 0.32) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	_spawn_burst(Color(1.0, 0.9, 0.55))


# One-shot sparkle burst from the mouth (celebration / catalyst wave).
func _spawn_burst(color: Color) -> void:
	var burst := _make_motes()
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 12
	burst.lifetime = 0.7
	burst.spread = 40.0
	burst.initial_velocity_min = 30.0
	burst.initial_velocity_max = 85.0
	burst.color = color
	add_child(burst)
	burst.emitting = true
	burst.finished.connect(burst.queue_free)


# Delayed public burst — used by Game.gd to sweep a sparkle wave across vials.
func sparkle_burst(color: Color, delay: float = 0.0) -> void:
	var tw := create_tween()
	tw.tween_interval(maxf(delay, 0.001))
	tw.tween_callback(_spawn_burst.bind(color))


# One-shot soft glass glint (catalyst wave). Skipped on completed vials,
# whose gleam is owned by the set_completed() pulse loop.
func gleam_flash(strength: float = 0.35, delay: float = 0.0) -> void:
	if _gleam == null or _completed:
		return
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(_gleam, "modulate:a", strength, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_gleam, "modulate:a", 0.0, 0.30) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# ---- catalyst rune ------------------------------------------------------------

func set_rune(enabled: bool) -> void:
	has_rune = enabled
	if not enabled:
		if _rune:
			_rune.visible = false
		return
	if _rune == null:
		_rune = Control.new()
		_rune.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_rune.material = mat
		_rune.position = Vector2(VIAL_W * 0.5, VIAL_H * 0.46)
		_rune.draw.connect(_draw_rune)
		add_child(_rune)
		# Faint slow breathing — present but never loud.
		_rune.modulate.a = 0.75
		var tw := create_tween().set_loops()
		tw.tween_property(_rune, "modulate:a", 0.30, 1.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(_rune, "modulate:a", 0.75, 1.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_rune.visible = true
	_rune.queue_redraw()


# Algiz — an angular protective sigil in chunky gold strokes.
func _draw_rune() -> void:
	var gold := Color(1.0, 0.85, 0.35, 0.9)
	_rune.draw_line(Vector2(0, 10), Vector2(0, -10), gold, 2.0, false)
	_rune.draw_line(Vector2(0, -2), Vector2(-7, -10), gold, 2.0, false)
	_rune.draw_line(Vector2(0, -2), Vector2(7, -10), gold, 2.0, false)


# Persistent "finished potion" state: sparse motes of the vial's own color
# drift up from the mouth, and the glass glints softly every few seconds.
func set_completed(done: bool) -> void:
	if done == _completed:
		return
	_completed = done
	if done:
		if _complete_motes == null:
			_complete_motes = _make_motes()
			_complete_motes.amount = 3
			_complete_motes.lifetime = 1.6
			_complete_motes.initial_velocity_min = 6.0
			_complete_motes.initial_velocity_max = 16.0
			add_child(_complete_motes)
		var cid := top_color()
		if cid >= 1 and cid <= _palette.size():
			_complete_motes.color = tinted_color(cid).lightened(0.5)
		_complete_motes.color.a = 0.6
		_complete_motes.emitting = true
		# Occasional soft glass glint — the leading interval also keeps it
		# from fighting the celebrate() flash on the same property.
		_kill_gleam_tween()
		if _gleam:
			_gleam_tween = create_tween().set_loops()
			_gleam_tween.tween_interval(2.2)
			_gleam_tween.tween_property(_gleam, "modulate:a", 0.12, 0.8) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_gleam_tween.tween_property(_gleam, "modulate:a", 0.0, 0.8) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		if _complete_motes:
			_complete_motes.emitting = false
		_kill_gleam_tween()
		if _gleam:
			_gleam.modulate.a = 0.0


func _kill_gleam_tween() -> void:
	if _gleam_tween and is_instance_valid(_gleam_tween):
		_gleam_tween.kill()
	_gleam_tween = null


# Base emitter for essence motes: tiny squares rising from the bottle mouth.
func _make_motes() -> CPUParticles2D:
	if _mote_tex == null:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_mote_tex = ImageTexture.create_from_image(img)
	var fx := CPUParticles2D.new()
	fx.texture = _mote_tex
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.position = Vector2(VIAL_W * 0.5, 10.0)   # bottle mouth
	fx.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	fx.emission_rect_extents = Vector2(9.0, 3.0)
	fx.direction = Vector2.UP
	fx.spread = 14.0
	fx.gravity = Vector2(0, -14)                # gentle upward drift
	fx.initial_velocity_min = 10.0
	fx.initial_velocity_max = 26.0
	fx.amount = 6
	fx.lifetime = 1.1
	fx.scale_amount_min = 1.0
	fx.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.9))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	fx.color_ramp = ramp
	fx.emitting = false
	return fx


# ---- selection --------------------------------------------------------------

func show_selected(v: bool) -> void:
	if _outline:
		_outline.visible = v
		if _outline_tween and is_instance_valid(_outline_tween):
			_outline_tween.kill()
			_outline_tween = null
		_outline.modulate.a = 1.0
		if v:
			# Slow breathing pulse on the golden outline.
			_outline_tween = create_tween().set_loops()
			_outline_tween.tween_property(_outline, "modulate:a", 0.45, 0.55) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_outline_tween.tween_property(_outline, "modulate:a", 1.0, 0.55) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Essence motes: stray pixels of the potion's color drift off the mouth
	# while the vial is "held".
	if v and not is_empty():
		if _select_motes == null:
			_select_motes = _make_motes()
			add_child(_select_motes)
		var cid := top_color()
		if cid >= 1 and cid <= _palette.size():
			_select_motes.color = tinted_color(cid).lightened(0.45)
		_select_motes.emitting = true
	elif _select_motes:
		_select_motes.emitting = false


# ---- visuals (placeholder — swap with sprite art) ---------------------------

func _build_visuals() -> void:
	var sheet       := load("res://games/alchemical_sort/assets/liquid_colors_all.png") as Texture2D
	var bottle_tex  := load("res://games/alchemical_sort/assets/bottle.png") as Texture2D
	var inside_tex  := load("res://games/alchemical_sort/assets/bottle_inside.png") as Texture2D

	# Vial size comes from the bottle artwork.
	VIAL_W = bottle_tex.get_width()    # 72
	VIAL_H = bottle_tex.get_height()   # 176
	custom_minimum_size = Vector2(VIAL_W, VIAL_H)
	size               = Vector2(VIAL_W, VIAL_H)
	pivot_offset       = Vector2(VIAL_W * 0.5, VIAL_H * 0.5)

	# Liquid cell size from the sprite sheet.
	var cell_w: int = sheet.get_width()  / SHEET_COLS   # 64
	var cell_h: int = sheet.get_height() / SHEET_ROWS   # 32
	_cell_h = float(cell_h)
	# Horizontal offset to center the 64-wide liquid inside the 72-wide bottle.
	var pad_x: int  = (VIAL_W - cell_w) / 2             # 4

	# Pre-build one AtlasTexture per color slot (row-major: left→right, top→bottom).
	_atlas_textures.clear()
	for r in range(SHEET_ROWS):
		for c in range(SHEET_COLS):
			var at := AtlasTexture.new()
			at.atlas  = sheet
			at.region = Rect2(c * cell_w, r * cell_h, cell_w, cell_h)
			_atlas_textures.append(at)

	# --- draw order: background → inside glass → liquid layers → bottle overlay → outline ---

	# 1. Inner glass texture at 70% opacity (behind the liquid).
	var inside := TextureRect.new()
	inside.texture      = inside_tex
	inside.stretch_mode = TextureRect.STRETCH_KEEP
	inside.size         = Vector2(VIAL_W, VIAL_H)
	inside.modulate.a   = 0.7
	inside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(inside)

	# 3. Liquid layer rects — bottom (index 0) to top (index MAX_LAYERS-1).
	#    Offset by (pad_x, BOTTLE_PAD_TOP) so they sit inside the bottle's glass window.
	#    TEXTURE_FILTER_NEAREST prevents linear-filter edge bleeding (dark fringe at atlas
	#    region boundaries) that shows as a gap between layers in both editor and APK.
	_layer_rects.clear()

	# Build shared SpriteFrames for the shimmer overlay (colors_anim.png, 5-frame horizontal strip).
	var anim_tex    := load("res://games/alchemical_sort/assets/colors_anim.png") as Texture2D
	var anim_frames := SpriteFrames.new()
	anim_frames.set_animation_speed("default", 5.0)
	anim_frames.set_animation_loop("default", true)
	for f in range(5):
		var fat := AtlasTexture.new()
		fat.atlas  = anim_tex
		fat.region = Rect2(f * cell_w, 0, cell_w, cell_h)
		anim_frames.add_frame("default", fat)
	var anim_mat := CanvasItemMaterial.new()
	anim_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	# One random start frame shared by all layers in this vial → layers animate in sync.
	# Different vials each call _build_visuals() separately, so they still desync.
	var start_frame := randi() % 5

	for i in range(MAX_LAYERS):
		var rect := TextureRect.new()
		rect.stretch_mode  = TextureRect.STRETCH_KEEP
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.size          = Vector2(cell_w, cell_h)
		rect.position      = Vector2(pad_x, BOTTLE_PAD_TOP + (MAX_LAYERS - 1 - i) * cell_h)
		rect.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		_set_layer_color(rect, _layers[i], _fog_mode and i < _fog_reveal_from)
		add_child(rect)
		_layer_rects.append(rect)

		# Shimmer overlay — ADD blend, 50% opacity, synced start frame within vial.
		# Child of rect so it inherits modulate; pour fade-in/out cascades for free.
		var shimmer := AnimatedSprite2D.new()
		shimmer.sprite_frames = anim_frames
		shimmer.centered      = false
		shimmer.frame         = start_frame
		shimmer.material      = anim_mat
		shimmer.modulate.a    = 0.05
		shimmer.visible       = _layers[i] != 0 and not (_fog_mode and i < _fog_reveal_from)
		shimmer.play("default")
		rect.add_child(shimmer)

	# 4. Bottle overlay — goes on top of the liquid so the glass frame is always visible.
	var overlay := TextureRect.new()
	overlay.texture      = bottle_tex
	overlay.stretch_mode = TextureRect.STRETCH_KEEP
	overlay.size         = Vector2(VIAL_W, VIAL_H)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	# 4b. Gleam — additive copy of the bottle art, flashed on completion and
	#     softly pulsed afterwards. The art doubles as its own mask, so the
	#     glow never spills outside the glass.
	var gleam_mat := CanvasItemMaterial.new()
	gleam_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_gleam = TextureRect.new()
	_gleam.texture      = bottle_tex
	_gleam.stretch_mode = TextureRect.STRETCH_KEEP
	_gleam.size         = Vector2(VIAL_W, VIAL_H)
	_gleam.material     = gleam_mat
	_gleam.modulate.a   = 0.0
	_gleam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gleam)

	# 5. Selection outline — topmost so it's never obscured.
	var out_style := StyleBoxFlat.new()
	out_style.bg_color = Color(0, 0, 0, 0)
	out_style.border_color = Color(1.0, 0.85, 0.20, 1.0)
	out_style.set_border_width_all(2)
	out_style.set_corner_radius_all(4)
	_outline = Panel.new()
	_outline.add_theme_stylebox_override("panel", out_style)
	_outline.size = Vector2(VIAL_W, VIAL_H)
	_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline.visible = false
	add_child(_outline)


# Assigns the correct atlas region and modulate for a layer.
# fog=true → dark-teal tint so the actual color isn't revealed.
func _set_layer_color(rect: TextureRect, cid: int, fog: bool) -> void:
	if cid > 0 and cid <= _atlas_textures.size():
		rect.texture  = _atlas_textures[cid - 1]
		rect.modulate = Color(0, 0, 0, 1) if fog else _tint_for(cid)
	else:
		rect.texture    = null
		rect.modulate.a = 0.0
	# Show shimmer only on visible, occupied layers.
	if rect.get_child_count() > 0:
		rect.get_child(0).visible = cid > 0 and not fog


func _refresh_visuals() -> void:
	for i in range(MAX_LAYERS):
		var rect: TextureRect = _layer_rects[i]
		_set_layer_color(rect, _layers[i], _fog_mode and i < _fog_reveal_from)
		if _layers[i] != 0:
			rect.modulate.a = 1.0


# ---- input ------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			tapped.emit(self)
