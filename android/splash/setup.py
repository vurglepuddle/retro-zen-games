"""Install Godot 4.3's Android build template and apply the native splash resources."""
from pathlib import Path
import os
import re
import shutil
from zipfile import ZipFile

source = Path(__file__).resolve().parent
root = source.parents[1]
build = root / "android/build"
version = "4.3.stable"
template = Path(os.environ.get("APPDATA", Path.home() / "AppData/Roaming")) / "Godot/export_templates" / version / "android_source.zip"
art = source / "res/drawable-nodpi/zen_splash_art.png"
if not art.is_file() or art.stat().st_size == 0:
    raise SystemExit(f"Export the Aseprite artwork at 4x to {art} first.")
if not template.is_file():
    raise SystemExit(f"Install the Godot {version} export templates first: {template}")

marker = build.parent / ".build_version"
if (build / "build.gradle").is_file():
    if not marker.is_file() or marker.read_text().strip() != version:
        raise SystemExit("Existing Android template has a different version; leaving it unchanged.")
else:
    if build.exists() and any(build.iterdir()):
        raise SystemExit("Android build folder already contains files; leaving it unchanged.")
    build.mkdir(parents=True, exist_ok=True)
    with ZipFile(template) as archive:
        for entry in archive.infolist():
            target = (build / entry.filename).resolve()
            if not target.is_relative_to(build.resolve()):
                raise SystemExit(f"Invalid template path: {entry.filename}")
        archive.extractall(build)
    marker.write_text(version + "\n")
    (build / ".gdignore").write_text("\n")

for path in (source / "res").rglob("*"):
    if path.is_file():
        target = build / path.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)

# Keep machine-specific tool paths in the ignored build folder. Godot 4.3's
# Gradle template requires Java 17, even when the editor uses a newer JDK.
java_roots = [Path(os.environ.get("JAVA_HOME", "__missing__"))]
for parent in [Path("C:/Program Files/Java"), Path("C:/Program Files/Eclipse Adoptium"), Path.home() / ".jdks"]:
    if parent.is_dir():
        java_roots.extend(parent.iterdir())
for jdk in java_roots:
    release = jdk / "release"
    if release.is_file() and re.search(r'JAVA_VERSION="17(?:[.\"]|$)', release.read_text()):
        properties = build / "gradle.properties"
        text = properties.read_text()
        text = re.sub(r"(?m)^org\.gradle\.java\.home=.*\n?", "", text)
        properties.write_text(text.rstrip() + "\norg.gradle.java.home=" + jdk.as_posix() + "\n")
        print("Gradle JDK:", jdk)
        break
else:
    print("Set Godot's Android Java SDK path to a JDK 17 before exporting.")

print("Native splash installed:", build / "res/drawable-nodpi/zen_splash_art.png")
print("Export Android with Gradle Build > Use Gradle Build enabled.")
