#Haptics.gd
# Tiny, sparse touch feedback for phones. Fire-and-forget: calls are safe everywhere.
#   - desktop builds and the editor: silent
#   - "all sound off" (AudioManager mute state 2) also quiets haptics
#   - a shared cooldown keeps it from ever becoming a buzz
# Android needs the VIBRATE permission ticked in the export preset. Godot sends these
# as touch haptics, so Android drops them when the phone's "Touch feedback" is off and
# scales them down at low intensity — which is why pulses under ~15 ms / 0.5 vanish.
class_name Haptics

const TICK := 0    # stone tap, frog poke
const TAP := 1     # snip, small interaction
const THUNK := 2   # something set down / broken

# Close to Android's own TICK (26 ms) / CLICK (45 ms) primitives so they survive system scaling.
const _DURATION_MS := [18, 28, 42]
const _AMPLITUDE := [0.55, 0.75, 1.0]
const DEFAULT_GAP_MS := 70

static var _last_msec: int = -100000


# min_gap_ms: skip this pulse if any pulse fired more recently than this.
static func pulse(kind: int = TAP, min_gap_ms: int = DEFAULT_GAP_MS) -> void:
	if not _enabled():
		return
	var now := Time.get_ticks_msec()
	if now - _last_msec < min_gap_ms:
		return
	_last_msec = now
	var k := clampi(kind, 0, _DURATION_MS.size() - 1)
	Input.vibrate_handheld(_DURATION_MS[k], _AMPLITUDE[k])


static func _enabled() -> bool:
	if not (OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")):
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		var audio := tree.root.get_node_or_null("AudioManager")
		if audio and int(audio.get("mute_state")) == 2:
			return false
	return true
