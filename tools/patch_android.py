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
    '<uses-permission android:name="android.permission.INTERNET"/>',
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

# ---- stable signing key -----------------------------------------------------
# Without this every CI build is signed with a different random debug key, so a new
# APK cannot be installed over an older one ("invalid package" / "app not installed").
for name in ("build.gradle.kts",):
    g = ANDROID / "app" / name
    if not g.exists():
        continue
    src = g.read_text()
    if 'create("lws")' not in src:
        block = '''    signingConfigs {
        create("lws") {
            storeFile = rootProject.file("../tools/release.jks")
            storePassword = "livewallpaper"
            keyAlias = "lws"
            keyPassword = "livewallpaper"
        }
    }

    buildTypes {'''
        src = src.replace("    buildTypes {", block, 1)
        src = src.replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("lws")')
        g.write_text(src)
        print("Signing config added to", g)
