"""Adds gallery permissions and the app name to the generated AndroidManifest."""
import re
from pathlib import Path

path = Path("android/app/src/main/AndroidManifest.xml")
text = path.read_text()

perms = [
    '<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>',
    '<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>',
    '<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>',
]
block = "\n    ".join(p for p in perms if p not in text)
if block:
    # Insert right after the opening <manifest ...> tag.
    text = re.sub(r"(<manifest[^>]*>)", lambda m: m.group(1) + "\n    " + block, text, count=1)

text = re.sub(r'android:label="[^"]*"', 'android:label="Live Wallpaper Studio"', text, count=1)
path.write_text(text)
print("Patched", path)
