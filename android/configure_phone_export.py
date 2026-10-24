"""Configure the local Android preset for smaller ARM phone APKs."""

import argparse
import json
from pathlib import Path
import re
import shutil


def set_option(block: str, key: str, value: str) -> str:
    pattern = re.compile(r"(?m)^" + re.escape(key) + r"=.*$")
    if pattern.search(block):
        return pattern.sub(lambda _: key + "=" + value, block)
    return block.rstrip() + "\n" + key + "=" + value + "\n\n"


def configure(project: Path, preset_name: str) -> None:
    path = project / "export_presets.cfg"
    text = path.read_text(encoding="utf-8")
    sections = re.split(r"(?m)^(\[[^\]\n]+\])\s*$", text)
    found = None
    for index in range(1, len(sections), 2):
        header, block = sections[index:index + 2]
        if (re.fullmatch(r"\[preset\.\d+\]", header)
                and f'name={json.dumps(preset_name)}' in block.splitlines()
                and 'platform="Android"' in block.splitlines()):
            found = index
            break
    if found is None:
        raise SystemExit(f"Android preset {preset_name!r} was not found")
    option_header = sections[found][:-1] + ".options]"
    option_index = next(i for i in range(1, len(sections), 2)
                        if sections[i] == option_header)
    options = sections[option_index + 1]
    if "gradle_build/use_gradle_build=true" not in options.splitlines():
        raise SystemExit("This preset must already have Use Gradle Build enabled")

    backup = project / ".godot/android_size_review/export_presets.before.cfg"
    backup.parent.mkdir(parents=True, exist_ok=True)
    if not backup.exists():
        shutil.copy2(path, backup)

    block = sections[found + 1]
    match = re.search(r"(?m)^exclude_filter=(.*)$", block)
    filters = json.loads(match[1]) if match else ""
    filters = [entry.strip() for entry in filters.split(",") if entry.strip()]
    for entry in ("art_src/*", "docs/*", "tests/*", "assets/social/*", "assets/screenshots/*"):
        if entry not in filters:
            filters.append(entry)
    sections[found + 1] = set_option(block, "exclude_filter", json.dumps(",".join(filters)))
    for key, value in {
        "gradle_build/compress_native_libraries": "true",
        "architectures/armeabi-v7a": "true",
        "architectures/arm64-v8a": "true",
        "architectures/x86": "false",
        "architectures/x86_64": "false",
    }.items():
        options = set_option(options, key, value)
    sections[option_index + 1] = options
    updated = "".join(sections)
    if updated != text:
        path.write_text(updated, encoding="utf-8")
    print(f"Configured {preset_name}: ARM32 + ARM64, compressed native libraries, development assets excluded.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preset", default="Android")
    args = parser.parse_args()
    configure(Path(__file__).resolve().parents[1], args.preset)
