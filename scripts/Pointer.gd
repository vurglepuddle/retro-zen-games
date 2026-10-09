# Pointer.gd
# Autoload: an in-game pointer, so gameplay recordings show where you tap.
# A hardware cursor records oddly, so the OS cursor is hidden inside the window
# and this sprite is drawn instead, on a canvas layer above every fade and splash.
#   Mouse: follows the cursor; hidden while the cursor is outside the window.
#   Touch: no pointer at all (a finger is its own pointer), just the ripple.
# Every press leaves a small pixel-art ripple so taps read in a video.
# Art: art_src/main/pointer.aseprite → assets/UI/pointer.png (1x, tip at 0,0).
extends CanvasLayer

const TEXTURE := preload("res://assets/UI/pointer.png")
const ART_SCALE := 2.0
const PRESSED_TINT := Color(0.82, 0.82, 0.82)

## Set false to give the OS cursor back (e.g. from a settings toggle).
var enabled := true:
	set = set_enabled

var _sprite: Sprite2D
var _mouse_inside := true
var _touch_mode := false


func _ready() -> void:
	layer = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sprite = Sprite2D.new()
	_sprite.texture = TEXTURE
	_sprite.centered = false
	_sprite.offset = Vector2(-0.5, -0.5)   # tip pixel centred on the hotspot
	_sprite.scale = Vector2(ART_SCALE, ART_SCALE)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.z_index = 1
	add_child(_sprite)
	_touch_mode = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	_sprite.visible = false
	_sprite.position = get_viewport().get_mouse_position()
	var window := get_tree().root
	window.mouse_entered.connect(_on_mouse_inside.bind(true))
	window.mouse_exited.connect(_on_mouse_inside.bind(false))
	_refresh()


func _on_mouse_inside(inside: bool) -> void:
	_mouse_inside = inside
	_refresh()


func set_enabled(value: bool) -> void:
	enabled = value
	if is_inside_tree():
		_refresh()


func _refresh() -> void:
	# Touch screens never show an OS cursor, and never show this one either.
	if _touch_mode:
		_sprite.visible = false
		return
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if enabled else Input.MOUSE_MODE_VISIBLE
	_sprite.visible = enabled and _mouse_inside


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		if event.index == 0 and event.pressed:
			if not _touch_mode:
				_touch_mode = true
				_refresh()
			_ripple(event.position)
		return
	if event is InputEventMouse:
		# Godot can synthesize mouse events from touch; the touch branch has it.
		if event.device == InputEvent.DEVICE_ID_EMULATION or _touch_mode:
			return
		_sprite.position = event.position
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_sprite.self_modulate = PRESSED_TINT if event.pressed else Color.WHITE
			if event.pressed:
				_ripple(event.position)


func _ripple(pos: Vector2) -> void:
	var ring := Ripple.new()
	ring.position = pos.round()
	add_child(ring)


## A ring of square pixels (at the pointer's own pixel size) that steps
## outward a pixel at a time, cools from cream to tan, then dithers away.
class Ripple:
	extends Node2D
	const STEP := 0.045   # seconds per frame of the ripple
	const RADII := [2, 3, 4, 5, 6, 7, 8]
	const CREAM := Color8(239, 216, 161)   # #efd8a1
	const TAN := Color8(239, 183, 117)     # #efb775
	var _age := 0.0
	var _frame := -1

	func _process(delta: float) -> void:
		_age += delta
		var frame := int(_age / STEP)
		if frame >= RADII.size():
			queue_free()
			return
		if frame != _frame:
			_frame = frame
			queue_redraw()

	func _draw() -> void:
		if _frame < 0:
			return
		var px := ART_SCALE
		var colour := CREAM if _frame < 3 else TAN
		for p in _circle(RADII[_frame]):
			# Last frames thin out to a checkerboard, then every third pixel.
			if _frame >= RADII.size() - 2 and (p.x + p.y) % 2 != 0:
				continue
			if _frame == RADII.size() - 1 and (p.x + 2 * p.y) % 3 != 0:
				continue
			draw_rect(Rect2(Vector2(p) * px - Vector2(px, px) * 0.5, Vector2(px, px)), colour)

	static func _circle(r: int) -> Array[Vector2i]:
		# Midpoint circle: a clean one-pixel ring with no doubled corners.
		var seen := {}
		var points: Array[Vector2i] = []
		var x := r
		var y := 0
		var err := 1 - r
		while x >= y:
			for p in [Vector2i(x, y), Vector2i(y, x), Vector2i(-y, x), Vector2i(-x, y),
					Vector2i(-x, -y), Vector2i(-y, -x), Vector2i(y, -x), Vector2i(x, -y)]:
				if not seen.has(p):
					seen[p] = true
					points.append(p)
			y += 1
			if err < 0:
				err += 2 * y + 1
			else:
				x -= 1
				err += 2 * (y - x) + 1
		return points
