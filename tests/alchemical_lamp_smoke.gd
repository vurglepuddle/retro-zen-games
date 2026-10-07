# Godot --headless --path . --script tests/alchemical_lamp_smoke.gd
# Optional -- --render-review saves idle/tap/hidden previews under .godot/.
extends SceneTree

var failures: Array[String] = []
var checks := 0
var lamp: Node2D
var game: Control

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func advance(seconds: float) -> void:
	for frame in range(roundi(seconds * 60.0)):
		lamp._process(1.0 / 60.0)

func check_group() -> void:
	var visible_count := 0
	for bug in lamp._bugs:
		if bug.wants_return:
			visible_count += 1
			check(bug.state == lamp.Flight.HOVER and bug.visibility == 1.0, "Selected bugs settle into hover")
		else:
			check(bug.state == lamp.Flight.HIDDEN and bug.node.modulate.a == 0.0, "Unselected bugs stay completely hidden")
	check(visible_count >= 1 and visible_count <= 5, "Group contains 1-5 visible bugs")

func click_at(point: Vector2, touch: bool = false, emulated: bool = false) -> void:
	if touch:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.pressed = true
		root.push_input(event, true)
		event.pressed = false
		root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.device = InputEvent.DEVICE_ID_EMULATION if emulated else 0
		event.pressed = true
		root.push_input(event, true)
		event.pressed = false
		root.push_input(event, true)

func capture(label: String) -> void:
	if not "--render-review" in OS.get_cmdline_user_args():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/lamp_%s.png" % label)

func _run() -> void:
	root.size = Vector2i(540, 1200)
	game = load("res://games/alchemical_sort/scenes/Game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	lamp = game.get_node("LampGlow")
	lamp.set_process(false)
	check(lamp._bugs.size() == 5, "Fixed pool of five bugs")
	check_group()
	advance(2.0)
	await capture("idle")
	var lamp_point: Vector2 = lamp.get_global_transform_with_canvas().origin
	click_at(lamp_point)
	check(lamp._tap_heat > 0.0, "Real GUI mouse click reaches the lamp")
	for bug in lamp._bugs:
		check(bug.state == lamp.Flight.FLEE or bug.state == lamp.Flight.HIDDEN, "Tap sends visible bugs fleeing and leaves hidden bugs in cover")
		check(bug.quiet_left >= 5.0 and bug.quiet_left <= 10.0, "Quiet period is 5-10 seconds from tap")
	advance(0.12)
	await capture("tap")
	advance(1.1)
	for bug in lamp._bugs:
		check(bug.state == lamp.Flight.HIDDEN and bug.node.modulate.a == 0.0, "Bugs disappear completely into cover")
	await capture("hidden")
	click_at(lamp_point, true)
	var heat: float = lamp._tap_heat
	var quiet: float = lamp._bugs[0].quiet_left
	click_at(lamp_point, false, true)
	check(lamp._tap_heat == heat and lamp._bugs[0].quiet_left == quiet, "Emulated mouse does not double-trigger touch")
	advance(4.9)
	for bug in lamp._bugs:
		check(bug.state == lamp.Flight.HIDDEN, "Repeated touch restarts the full quiet period")
	var first_return := -1.0
	for frame in range(320):
		advance(1.0 / 60.0)
		for bug in lamp._bugs:
			if bug.state == lamp.Flight.RETURN and first_return < 0.0:
				first_return = 4.9 + (frame + 1) / 60.0
	check(first_return >= 5.0 and first_return <= 10.05, "Shy return begins within the requested window")
	advance(4.3)
	check_group()
	# A tap during a return must flee from the current position, with no jump.
	click_at(lamp_point)
	advance(1.2)
	for bug in lamp._bugs:
		bug.quiet_left = 0.0
	advance(0.6)
	var returning = null
	for bug in lamp._bugs:
		if bug.state == lamp.Flight.RETURN:
			returning = bug
	var before: Vector2 = returning.node.position
	click_at(lamp_point)
	check(returning.state == lamp.Flight.FLEE and returning.node.position == before, "Returning bugs can be shooed without teleporting")
	advance(15.0)
	var outside_heat: float = lamp._tap_heat
	click_at(Vector2(250, 350))
	check(lamp._tap_heat == outside_heat, "Board taps do not trigger the lamp")
	game.get_node("WinPanel").show()
	await process_frame
	click_at(lamp_point)
	check(lamp._tap_heat == outside_heat, "Win overlay blocks lamp interaction")
	game.get_node("WinPanel").hide()
	game.hide()
	click_at(lamp_point)
	check(lamp._tap_heat == outside_heat, "Hidden game cannot respond to lamp taps")
	game.show()
	# Deterministic repeated cycles exercise all group sizes and pool reuse.
	lamp._rng.seed = 73192
	var seen_counts: Dictionary = {}
	var child_count: int = lamp.get_child_count()
	for cycle in range(40):
		click_at(lamp_point)
		advance(15.0)
		check_group()
		var count := 0
		for bug in lamp._bugs:
			if bug.wants_return:
				count += 1
		seen_counts[count] = true
	check(seen_counts.size() == 5, "Return cycles exercise all five group sizes")
	check(lamp.get_child_count() == child_count, "Repeated shoo cycles do not accumulate bug nodes")
	# Extended flight should stay near its home, away from labels and vials.
	var bounded := true
	for frame in range(7200):
		advance(1.0 / 60.0)
		for bug in lamp._bugs:
			if bug.wants_return:
				bounded = bounded and bug.node.position.is_finite() and bug.node.position.distance_to(bug.home) < 40.0
	check(bounded, "Two minutes of hovering stay finite and near the lamp")
	# The new background's shelf alignment accompanies this lamp scene.
	for difficulty in range(5):
		game._difficulty = difficulty
		game.prepare_board()
		check(not game._vials.is_empty(), "Background scene builds a board for difficulty %d" % difficulty)
		for vial in game._vials:
			check(vial.position.is_finite(), "Vial placement remains finite")
	game.queue_free()
	await process_frame
	print("Alchemical lamp: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
