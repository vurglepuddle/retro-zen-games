extends RefCounted

# Keep the existing file until the replacement has been written successfully.
# The backup is the previous readable save, never a partial/corrupt primary.
static func load_config(cfg: ConfigFile, path: String) -> Error:
	cfg.clear()
	var result := cfg.load(path)
	if result == OK and not cfg.get_sections().is_empty():
		return OK
	cfg.clear()
	result = cfg.load(path + ".bak")
	if result == OK and cfg.get_sections().is_empty():
		result = ERR_FILE_CORRUPT
	if result != OK:
		cfg.clear()
	return result


static func copy_file(source: String, destination: String) -> Error:
	var result := DirAccess.copy_absolute(source, destination + ".tmp")
	if result == OK:
		var source_hash := FileAccess.get_sha256(source)
		if source_hash.is_empty() or source_hash != FileAccess.get_sha256(destination + ".tmp"):
			result = ERR_FILE_CORRUPT
	if result == OK:
		result = DirAccess.rename_absolute(destination + ".tmp", destination)
	return result


static func save_config(cfg: ConfigFile, path: String, required_section: String = "", required_keys: Array[String] = []) -> Error:
	var serialized := cfg.encode_to_text()
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	var result: Error = FileAccess.get_open_error()
	if file:
		file.store_string(serialized)
		file.flush()
		result = file.get_error()
		file.close()
		if result == OK and FileAccess.get_file_as_string(path + ".tmp") != serialized:
			result = ERR_FILE_CORRUPT
	if result == OK:
		var previous := ConfigFile.new()
		var readable := previous.load(path) == OK and not previous.get_sections().is_empty()
		if readable and not required_section.is_empty():
			readable = previous.has_section(required_section)
			for key in required_keys:
				readable = readable and previous.has_section_key(required_section, key)
		if readable:
			result = copy_file(path, path + ".bak")
	if result == OK:
		result = DirAccess.rename_absolute(path + ".tmp", path)
	if result != OK:
		push_warning("Could not save %s (error %d); the previous save was kept." % [path, result])
	return result
