# Android launch artwork (Godot 4.3)

The Android system splash uses `res/drawable-nodpi/zen_splash_art.png` separately
from the launcher icon. The PNG is exported at 4x with nearest-neighbor scaling.
Its `drawable-nodpi` location prevents density resampling when Android loads it,
and the bitmap drawable disables filtering when Android draws it.

Run from the project folder in **cmd.exe** after installing/reinstalling the
Godot 4.3 Android build template, or after changing these splash resources:

```bat
python android\splash\setup.py
```

The script installs the local Godot 4.3 template if needed and copies `res/`
into `android/build/res/`. The generated build folder is ignored by Git. It
also selects an installed Java 17 for this project's Gradle daemon; the
editor's Java SDK setting remains separate.

In **Project > Export > Android > Gradle Build**, enable **Use Gradle Build**.
Re-export and install the new APK to see the change. Godot's Application > Boot
Splash settings control a later screen and do not configure this native screen.

Android controls the native splash's placement and size. This changes the
artwork and filtering within that system screen.

For smaller phone APKs while keeping this Gradle splash, run
`python android/configure_phone_export.py` from the project root. It enables
native-library compression, keeps ARM32/ARM64, disables Intel engine copies,
and excludes development folders. Package identity and signing settings stay
intact; the original local preset is backed up under `.godot/android_size_review/`.
