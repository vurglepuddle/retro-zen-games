# Phone APK exports

The local `export_presets.cfg` stays ignored because it can contain signing
configuration. After setting up the Android/Gradle preset and the
[native splash](splash/README.md), run from the project root:

```powershell
python android/configure_phone_export.py
```

This keeps ARM 32-bit and ARM 64-bit phones supported, removes Intel x86/x86_64
engine copies, and enables **Gradle Build → Compress Native Libraries**. It
also excludes development/test/gallery folders from the Android game payload.
The script preserves package identity, signing settings, version, splash,
permissions and the Web preset. It saves the original local preset under
`.godot/android_size_review/` and is safe to run again.

Compressed native libraries reduce the APK download size; Android extracts
them at installation, so installed native-code size does not shrink by the same
amount. Intel Android emulators need an x86/x86_64 preset of their own. Keep both
ARM options for older phones whose Android OS may still be 32-bit.

Use a release export when comparing APK sizes. Put review APKs under `.godot/`
so builds containing the separately licensed Potion artwork stay local. Export
and signature validation do not replace installation and gameplay checks on
the target phones.

On 24 October 2026, this changed the existing 342.4 MiB release to
105.5 MiB (69% smaller), with the same release certificate, package/version,
native splash, ARM engine payloads and retained artwork/audio. The local
candidate and its ZIP/hash audit are under `.godot/android_size_review/`.
