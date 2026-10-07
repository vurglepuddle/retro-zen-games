# Android launch artwork (Godot 4.3)

The Android system splash now uses `app_icon_2.aseprite` separately from the
launcher icon. The PNG is exported at 4x with nearest-neighbor scaling. Its
`drawable-nodpi` location prevents density resampling when Android loads it,
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
