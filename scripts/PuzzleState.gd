extends RefCounted

# Only plain values go into round saves. Scene objects and item textures stay
# outside the file; Potion undo identities are translated to stable indices.
static func stamp(game: Node, kind: String) -> Array:
	# Check the small live board before copying/encoding a long undo history.
	# Cosmetic tint drift alone doesn't require another disk write.
	match kind:
		"potion_3":
			var order := []
			for row in game._cells:
				for cell in row: order.append(cell.get_instance_id())
			for cell in game._disp_scroll_cells: order.append(cell.get_instance_id())
			return [game._game_generation, game._move_count, game._undo_stack.size(), order, game._reshuffle_btn.visible]
		"alchemical_sort":
			var vials := []
			for vial in game._vials: vials.append([vial.get_layers(), vial._fog_reveal_from])
			return [game._game_generation, game._move_count, game._undo_stack.size(), vials,
				game._rune_fired, game._reshuffle_btn.visible]
		"tile_chain":
			var cells := []
			for row in game._cells:
				for cell in row: cells.append([cell.a_id, cell.b_id, cell.c_id])
			return [game._game_generation, cells, game._current_combo,
				game._selected.get_instance_id() if is_instance_valid(game._selected) else 0]
		"gem_match":
			var cells := []
			for row in game.board:
				for tile in row:
					cells.append([tile.level, tile.special_type, tile.locked, tile.time_bonus] if tile else [])
			return [game._game_generation, cells, game.score, int(game._time_remaining), game._timed_level]
	return []

static func capture(game: Node, kind: String) -> Dictionary:
	match kind:
		"potion_3":
			var cells: Array = game._all_cells()
			var snapshots := []
			for cell in cells: snapshots.append(cell.get_snapshot())
			var undo := []
			for step in game._undo_stack:
				var saved := []
				saved.resize(cells.size())
				for entry in step: saved[cells.find(entry[0])] = entry[1]
				undo.append(saved)
			var item_paths := {}
			var initial: Array = snapshots + (undo.front() if not undo.is_empty() else [])
			for cell in initial:
				for layer in [cell.slots] + cell.z_stack:
					for id in layer:
						if id != 0: item_paths[id] = game._item_textures[id].resource_path
			return {"kind": kind, "mode": game._difficulty, "actual": game._actual_difficulty,
				"scroll": game._scrolling_rows.duplicate(), "dispensers": game._dispenser_count,
				"belt": game._hazard_disp_scroll, "cells": snapshots, "undo": undo,
				"moves": game._move_count, "item_paths": item_paths, "dead": game._reshuffle_btn.visible}
		"alchemical_sort":
			var vials := []
			for vial in game._vials:
				vials.append({"layers": vial.get_layers(), "fog": vial._fog_reveal_from})
			return {"kind": kind, "mode": game._difficulty, "actual": game._actual_difficulty,
				"fog": game._fog_mode, "vials": vials, "moves": game._move_count,
				"undo": game._undo_stack.duplicate(true), "rune": game._vials.find(game._rune_vial),
				"fired": game._rune_fired, "tints": game._color_tints.duplicate(),
				"phases": game._tint_phases.duplicate(), "tint_time": game._tint_time,
				"dead": game._reshuffle_btn.visible}
		"tile_chain":
			var cells := []
			var selected := -1
			for row in game._cells:
				for cell in row:
					if cell == game._selected: selected = cells.size()
					cells.append([cell.a_id, cell.b_id, cell.c_id])
			return {"kind": kind, "mode": 0, "cells": cells, "selected": selected,
				"set": int(game._z_path.get_base_dir().get_file().trim_prefix("Set_")),
				"combo": game._current_combo}
		"gem_match":
			var cells := []
			for row in game.board:
				for tile in row:
					cells.append([tile.level, tile.special_type, tile.locked, tile.time_bonus] if tile else [])
			return {"kind": kind, "mode": 2 if game._level_mode else (1 if game._timed_mode else 0),
				"cells": cells, "score": game.score, "time": game._time_remaining,
				"level": game._timed_level, "level_start": game._level_score_start}
	return {}

static func valid(data: Variant, kind: String) -> bool:
	if not data is Dictionary or data.get("kind") != kind or not _integer(data.get("mode"), 0, 4):
		return false
	match kind:
		"potion_3":
			if data.mode > 3 or not data.get("item_paths") is Dictionary or not data.get("dead") is bool: return false
			for id in data.item_paths:
				if not _integer(id, 1, 1000000) or not data.item_paths[id] is String \
						or not data.item_paths[id].begins_with("res://games/potion_3/assets/items/"): return false
			if not _integer(data.get("actual"), 0, 2) or not _integer(data.get("dispensers"), 0, 4) \
					or not data.get("belt") is bool or not _integer(data.get("moves"), 0, 10000000): return false
			var cols: int = data.actual + 3
			if data.mode != 3 and data.mode != data.actual: return false
			if data.actual == 0 and (data.dispensers > 0 or data.belt): return false
			if data.belt and data.actual != 2: return false
			if not data.get("scroll") is Array or data.scroll.size() > 1: return false
			for row in data.scroll:
				if not _integer(row, 0, 2): return false
			var count: int = cols * 3 + data.scroll.size() + data.dispensers + (7 if data.belt else 0)
			if not _array(data.get("cells"), count) or not data.get("undo") is Array: return false
			for cell in data.cells:
				if not _potion_cell(cell): return false
			if not _potion_triples(data.cells, data.item_paths): return false
			for step in data.undo:
				if not _array(step, count): return false
				for cell in step:
					if not _potion_cell(cell): return false
				if not _potion_triples(step, data.item_paths): return false
		"alchemical_sort":
			if not _integer(data.get("actual"), 0, 4) or not data.get("fog") is bool or not data.get("dead") is bool \
					or not data.get("vials") is Array or not _integer(data.get("moves"), 0, 10000000): return false
			var colors: int = 5 if data.fog else [6, 8, 12][mini(data.actual, 2)]
			if data.vials.size() != colors + 2 + (1 if data.mode == 3 else 0): return false
			for i in range(data.vials.size()):
				var vial = data.vials[i]
				var capacity := 1 if data.mode == 3 and i == data.vials.size() - 1 else 5
				if not vial is Dictionary or not _liquid_layers(vial.get("layers"), colors, capacity) \
						or not _integer(vial.get("fog"), 0, 5): return false
			var layers := []
			for vial in data.vials: layers.append(vial.layers)
			if not _liquid_counts(layers, colors): return false
			if not data.get("undo") is Array or not _integer(data.get("rune"), -1, data.vials.size() - 1) \
					or not data.get("fired") is bool: return false
			for step in data.undo:
				if not _array(step, data.vials.size()): return false
				for i in range(step.size()):
					if not _liquid_layers(step[i], colors, 1 if data.mode == 3 and i == step.size() - 1 else 5): return false
				if not _liquid_counts(step, colors): return false
			if not _array(data.get("tints"), 14) or not _array(data.get("phases"), 14) \
					or not data.get("tint_time") is float or not is_finite(data.tint_time): return false
			for color in data.tints:
				if not color is Color: return false
			for phase in data.phases:
				if not phase is Vector3: return false
		"tile_chain":
			if data.mode != 0 or not _array(data.get("cells"), 30) or not _integer(data.get("set"), 1, 19) \
					or not _integer(data.get("combo"), 0, 10000000) or not _integer(data.get("selected"), -1, 29): return false
			for cell in data.cells:
				if not _ids(cell, 3, 29): return false
		"gem_match":
			if data.mode > 2 or not _array(data.get("cells"), 77) or not _integer(data.get("score"), 0, 1000000000) \
					or not _integer(data.get("level"), 1, 128) or not _integer(data.get("level_start"), 0, 1000000000): return false
			if not (data.get("time") is float or data.get("time") is int) or not is_finite(float(data.time)) \
					or data.time < 0 or data.time > 100000: return false
			for i in range(77):
				var cell = data.cells[i]
				if i in [70, 76]:
					if not _array(cell, 0): return false
				elif not _array(cell, 4) or not _integer(cell[0], 1, 8) \
						or not _integer(cell[1], 0, 3) or not cell[2] is bool or not _integer(cell[3], 0, 60): return false
		_:
			return false
	return true

static func restore(game: Node, data: Dictionary) -> bool:
	var kind: String = data.get("kind", "")
	if not valid(data, kind): return false
	match kind:
		"potion_3":
			# Resolve artwork paths before touching the running board. Numeric IDs
			# may change when a later build adds images to the local item sets.
			game._load_textures()
			var available := {}
			for id in game._item_textures:
				available[game._item_textures[id].resource_path] = id
			var mapping := {0: 0}
			for id in data.item_paths:
				if not available.has(data.item_paths[id]): return false
				mapping[id] = available[data.item_paths[id]]
			data = data.duplicate(true)
			var all_snapshots: Array = data.cells.duplicate()
			for step in data.undo: all_snapshots.append_array(step)
			for snapshot in all_snapshots:
				for layer in [snapshot.slots] + snapshot.z_stack:
					for i in range(3): layer[i] = mapping[layer[i]]
			game.stop_game()
			game._clear_cells()
			game.set_difficulty(data.mode)
			game._actual_difficulty = data.actual
			game._cols_per_row = data.actual + 3
			game._rows = 3
			game._max_depth = data.actual + 3
			game._item_type_count = [12, 22, 32][data.actual]
			game._scrolling_rows.assign(data.scroll)
			game._dispenser_count = data.dispensers
			game._hazard_disp_scroll = data.belt
			game._special_lock = false
			game._build_cells()
			var cells: Array = game._all_cells()
			for i in range(cells.size()):
				if data.cells[i].is_locked: cells[i].set_as_locked(data.cells[i].unlock_counter)
				cells[i].restore(data.cells[i])
				# start_game expects the prepared drop-in offset.
				if not cells[i] in game._buffer_cells and cells[i] != game._disp_scroll_buffer:
					cells[i].position.y -= 160.0
					cells[i].modulate.a = 0.0
			game._undo_stack.clear()
			for saved in data.undo:
				var step := []
				for i in range(cells.size()): step.append([cells[i], saved[i]])
				game._undo_stack.append(step)
			game._move_count = data.moves
			game._load_save()
			game._win_panel.hide()
			game._reshuffle_btn.hide()
			game._reshuffle_lbl.hide()
			game._update_ui()
		"alchemical_sort":
			game.stop_game()
			game._clear_vials()
			game.set_difficulty(data.mode)
			game._actual_difficulty = data.actual
			game._fog_mode = data.fog
			game._zen_drift = data.mode == 3
			game._color_count = 5 if data.fog else [6, 8, 12][mini(data.actual, 2)]
			game._empty_vials = 2
			game._vials_per_row = 5 if not data.fog and data.actual == 2 else 4
			game._color_tints.assign(data.tints)
			game._active_tints.assign(data.tints)
			game._tint_phases.assign(data.phases)
			game._tint_time = data.tint_time
			game._build_vials()
			for i in range(game._vials.size()):
				var layers: Array[int] = []
				layers.assign(data.vials[i].layers)
				game._vials[i].restore(layers)
				game._vials[i]._fog_reveal_from = data.vials[i].fog
				game._vials[i]._refresh_visuals()
				game._vials[i].set_rune(i == data.rune and not data.fired)
			game._rune_vial = game._vials[data.rune] if data.rune >= 0 else null
			game._rune_fired = data.fired
			game._undo_stack = data.undo.duplicate(true)
			game._move_count = data.moves
			game._win_panel.hide()
			game._reshuffle_btn.hide()
			game._reshuffle_lbl.hide()
			game._mystery_label.hide()
			game._refresh_completed_states()
			game._update_ui()
		"tile_chain":
			if not ResourceLoader.exists("res://games/tile_chain/assets/Set_%d/z-1.png" % data.set): return false
			game.stop_game()
			game._load_textures(data.set)
			if game._a_textures.size() < 2 or game._b_textures.size() < 2 or game._c_textures.size() < 2: return false
			game._clear_board()
			game._build_board()
			var i := 0
			game._selected = null
			for row in game._cells:
				for cell in row:
					var ids: Array = data.cells[i]
					var banks := [game._a_textures, game._b_textures, game._c_textures]
					for layer in range(3):
						if ids[layer] >= banks[layer].size(): return false
					cell.a_id = ids[0]; cell.b_id = ids[1]; cell.c_id = ids[2]
					for layer in range(3):
						var rect: TextureRect = [cell._a_rect, cell._b_rect, cell._c_rect][layer]
						rect.texture = banks[layer][ids[layer]]
					if i == data.selected:
						game._selected = cell
						cell.show_outline(true)
					i += 1
			game._current_combo = data.combo
			game._reshuffling = false
			game._clear_panel.hide()
			game._update_ui()
		"gem_match":
			if data.mode == 2: game.set_level_mode(true)
			else: game.set_timed_mode(data.mode == 1)
			game.prepare_board()
			var i := 0
			for row in game.board:
				for tile in row:
					var saved: Array = data.cells[i]
					if tile:
						tile.set_level(saved[0])
						tile.set_special(saved[1])
						tile.set_time_bonus(saved[3])
						tile.set_locked(saved[2])
					i += 1
			game.score = data.score
			game._displayed_score = data.score
			game.score_label.text = "Score: %d" % data.score
			game._time_remaining = data.time
			game._timed_level = data.level
			game._level_score_start = data.level_start
			game._level_target = game._level_target_for(data.level)
			game._next_milestone = (data.score / 1000 + 1) * 1000
			game._update_timer_display()
			game._update_level_label()
			game._update_score_bar()
	return true

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return value is int and value >= minimum and value <= maximum

static func _array(value: Variant, count: int) -> bool:
	return value is Array and value.size() == count

static func _ids(value: Variant, count: int, maximum: int) -> bool:
	if not _array(value, count): return false
	for id in value:
		if not _integer(id, 0, maximum): return false
	return true

static func _potion_cell(cell: Variant) -> bool:
	if not cell is Dictionary or not _ids(cell.get("slots"), 3, 1000000) \
			or not _array(cell.get("slot_mystery"), 3) or not cell.get("is_locked") is bool \
			or not _integer(cell.get("unlock_counter"), 0, 3): return false
	if not cell.get("z_stack") is Array or cell.z_stack.size() > 5 \
			or not _array(cell.get("z_stack_mystery"), cell.z_stack.size()): return false
	if cell.is_locked and cell.unlock_counter == 0: return false
	for layer in cell.z_stack:
		if not _ids(layer, 3, 1000000): return false
	for flags in [cell.slot_mystery] + cell.z_stack_mystery:
		if not _array(flags, 3): return false
		for flag in flags:
			if not flag is bool: return false
	return true

static func _potion_triples(cells: Array, paths: Dictionary) -> bool:
	var counts := {}
	for cell in cells:
		for layer in [cell.slots] + cell.z_stack:
			for id in layer:
				if id != 0:
					if not paths.has(id): return false
					counts[id] = counts.get(id, 0) + 1
	for count in counts.values():
		if count != 3: return false
	return true

static func _liquid_layers(layers: Variant, colors: int, capacity: int) -> bool:
	if not _ids(layers, 5, colors): return false
	var empty := false
	for i in range(5):
		if layers[i] == 0: empty = true
		elif empty or i >= capacity: return false
	return true

static func _liquid_counts(vials: Array, colors: int) -> bool:
	var counts := {}
	for layers in vials:
		for color in layers:
			if color != 0: counts[color] = counts.get(color, 0) + 1
	if counts.size() != colors: return false
	for count in counts.values():
		if count != 5: return false
	return true
