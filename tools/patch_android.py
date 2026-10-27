"""
Prepares the generated Android project (Flutter-only app, no custom native code):
  * gallery read permissions and app name in AndroidManifest.xml
  * minSdk 24 (needed by the wallpaper plugin)
Run from the repo root after `flutter create`.
"""
import re
import sys
from pathlib import Path

ANDROID = Path("android")
manifest_path = ANDROID / "app" / "src" / "main" / "AndroidManifest.xml"
text = manifest_path.read_text()

perms = [
    '<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>',
    '<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>',
    '<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>',
    '<uses-permission android:name="android.permission.SET_WALLPAPER"/>',
]
missing = [p for p in perms if p.split('"')[1] not in text]
if missing:
    block = "\n    ".join(missing)
    text = re.sub(r"(<manifest[^>]*>)", lambda m: m.group(1) + "\n    " + block, text, count=1)
text = re.sub(r'android:label="[^"]*"', 'android:label="Live Wallpaper Studio"', text, count=1)
manifest_path.write_text(text)
print("Patched", manifest_path)

for name in ("build.gradle.kts", "build.gradle"):
    g = ANDROID / "app" / name
    if g.exists():
        src = g.read_text()
        kts = name.endswith(".kts")
        new = re.sub(r"minSdk(Version)?\s*=?\s*(flutter\.minSdkVersion|\d+)",
                     "minSdk = 24" if kts else "minSdkVersion 24", src)
        if new != src:
            g.write_text(new)
            print("minSdk set to 24 in", g)
        else:
            print("WARNING: minSdk pattern not found in", g, file=sys.stderr)

# AGP 9 opts: some plugins still use the legacy Android DSL / their own Kotlin plugin.
gp = ANDROID / "gradle.properties"
props = gp.read_text() if gp.exists() else ""
for line in ("android.newDsl=false", "android.builtInKotlin=false", "android.disallowKotlinSourceSets=false"):
    if line.split("=")[0] not in props:
        props += ("\n" if props and not props.endswith("\n") else "") + line + "\n"
gp.write_text(props)
print("Updated", gp)
