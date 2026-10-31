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

# ---- depth (tilt / parallax) live wallpaper: native service + channel -------------------
import glob

main_acts = glob.glob(str(ANDROID / "app" / "src" / "main" / "kotlin" / "**" / "MainActivity.kt"), recursive=True)
if main_acts:
    act = Path(main_acts[0])
    pkg = re.search(r"^package\s+([\w.]+)", act.read_text(), re.M).group(1)
    for name in ("MainActivity.kt", "DepthWallpaperService.kt"):
        body = Path("tools/native", name).read_text().replace("__PKG__", pkg)
        (act.parent / name).write_text(body)
    print("Native depth wallpaper written to", act.parent, "package", pkg)
else:
    print("WARNING: MainActivity.kt not found; depth wallpaper skipped", file=sys.stderr)

xml_dir = ANDROID / "app" / "src" / "main" / "res" / "xml"
xml_dir.mkdir(parents=True, exist_ok=True)
(xml_dir / "depth_wallpaper.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<wallpaper xmlns:android="http://schemas.android.com/apk/res/android"\n'
    '    android:thumbnail="@mipmap/ic_launcher" />\n'
)
text = manifest_path.read_text()
if "DepthWallpaperService" not in text:
    svc = '''    <service
            android:name=".DepthWallpaperService"
            android:label="Depth Wallpaper"
            android:exported="true"
            android:permission="android.permission.BIND_WALLPAPER">
            <intent-filter>
                <action android:name="android.service.wallpaper.WallpaperService"/>
            </intent-filter>
            <meta-data
                android:name="android.service.wallpaper"
                android:resource="@xml/depth_wallpaper"/>
        </service>
    </application>'''
    text = text.replace("</application>", svc, 1)
    text = re.sub(r"(<manifest[^>]*>)",
                  lambda m: m.group(1) + '\n    <uses-feature android:name="android.software.live_wallpaper" android:required="false"/>',
                  text, count=1)
    manifest_path.write_text(text)
    print("Depth service added to manifest")
