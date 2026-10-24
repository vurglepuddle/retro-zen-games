extends HBoxContainer

const Toggle := preload("res://scripts/AudioToggleButton.gd")
# Music on/off, then SFX on/off. Preloads keep every game's sheets in exports.
const GAME_SHEETS := {
	"gem_match": [
		preload("res://games/gem_match/assets/ui/audio/music_on.png"),
		preload("res://games/gem_match/assets/ui/audio/music_off.png"),
		preload("res://games/gem_match/assets/ui/audio/sfx_on.png"),
		preload("res://games/gem_match/assets/ui/audio/sfx_off.png"),
	],
	"tile_chain": [
		preload("res://games/tile_chain/assets/ui/audio/music_on.png"),
		preload("res://games/tile_chain/assets/ui/audio/music_off.png"),
		preload("res://games/tile_chain/assets/ui/audio/sfx_on.png"),
		preload("res://games/tile_chain/assets/ui/audio/sfx_off.png"),
	],
	"alchemical_sort": [
		preload("res://games/alchemical_sort/assets/ui/audio/music_on.png"),
		preload("res://games/alchemical_sort/assets/ui/audio/music_off.png"),
		preload("res://games/alchemical_sort/assets/ui/audio/sfx_on.png"),
		preload("res://games/alchemical_sort/assets/ui/audio/sfx_off.png"),
	],
	"potion_3": [
		preload("res://games/potion_3/assets/ui/audio/music_on.png"),
		preload("res://games/potion_3/assets/ui/audio/music_off.png"),
		preload("res://games/potion_3/assets/ui/audio/sfx_on.png"),
		preload("res://games/potion_3/assets/ui/audio/sfx_off.png"),
	],
	"zen_farm": [
		preload("res://games/zen_farm/assets/ui/audio/music_on.png"),
		preload("res://games/zen_farm/assets/ui/audio/music_off.png"),
		preload("res://games/zen_farm/assets/ui/audio/sfx_on.png"),
		preload("res://games/zen_farm/assets/ui/audio/sfx_off.png"),
	],
}
var _game: CanvasItem

func _ready() -> void:
	name = "AudioControls"
	_game = get_parent()
	z_index = 120
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 12)
	var kind := _game.scene_file_path.get_slice("/", 3)
	var sheets: Array = GAME_SHEETS[kind]
	for channel in range(2):
		var button := Toggle.new()
		button.name = "Music" if channel == 0 else "SFX"
		button.channel = channel
		button.sheet_on = sheets[channel * 2]
		button.sheet_off = sheets[channel * 2 + 1]
		button.tooltip_text = UIFeedback.tooltip("Music" if channel == 0 else "Sound effects")
		if "zen_farm" in _game.scene_file_path:
			button.ignore_texture_size = true
			button.stretch_mode = TextureButton.STRETCH_SCALE
			button.custom_minimum_size = Vector2(48, 52)
		add_child(button)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	var viewport_size := get_viewport_rect().size
	position = Vector2(viewport_size.x - 160, viewport_size.y - 88)
	# The farm has a clear gap between its water gauge and day/night control.
	if "zen_farm" in _game.scene_file_path:
		add_theme_constant_override("separation", 8)
		position = Vector2(viewport_size.x - 202, viewport_size.y - 286)

func blocks_event(event: InputEvent) -> bool:
	if not is_visible_in_tree():
		return false
	if event is InputEventMouseButton or event is InputEventMouseMotion \
			or event is InputEventScreenTouch or event is InputEventScreenDrag:
		return get_global_rect().has_point(event.position)
	return false
