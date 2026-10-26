# Live Wallpaper Studio (Flutter prototype)

Create Studio, Pick Media, Motion Editor, Theme Builder, Preview and Setup Guide screens.
Ab real gallery se video/photo pick karke theme ban sakta hai. Sample footage fallback bhi maujood hai.

> Ye code is sandbox mein compile nahi hua (Flutter installed nahi tha). Pehli run par `flutter analyze` chalayein, chhoti typos ya warnings aa sakti hain.

## Packages

| Package | Kaam |
| --- | --- |
| `photo_manager` | Gallery permission, date-wise paged list, asset file |
| `photo_manager_image_provider` | `AssetEntityImage` thumbnails |
| `video_player` | Motion Editor mein real video playback aur loop |
| `video_thumbnail` | Timeline filmstrip frames aur key-frame still |

## Setup

```bash
flutter create --platforms=android,ios live_wallpaper_studio
cd live_wallpaper_studio
# is folder ki lib/, pubspec.yaml aur analysis_options.yaml ko upar wale project par copy karein
flutter pub get
```

### Android (`android/app/src/main/AndroidManifest.xml`, `<manifest>` ke andar)

```xml
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
```

`android/app/build.gradle` mein `compileSdk` 34 ya zyada, `minSdk` 21 ya zyada rakhein.

### iOS (`ios/Runner/Info.plist`)

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Pick your own videos and photos to make wallpapers.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Save your live wallpaper to Photos.</string>
```

Phir `flutter run`. Debug mode mein Studio par "iOS flow / Android flow" switch hai.

## Real media ka flow

```
Studio -> Pick Media (permission, date groups, 90 items per page)
  Video: Motion Editor (asli playback, 3s tak trim, key frame) -> Theme Builder / Preview
  Photo: seedha Theme Builder / Preview
```

- **Pick Media**: permission maangta hai. iOS "limited access" par "Manage" banner aata hai. Deny hone par "Use sample footage" ka rasta hai.
- **Motion Editor**: video ki asli length par timeline banti hai, loop max 3s. "Set at playhead" us frame ko Lock still banata hai.
- **Theme Builder**: Home still key frame se banta hai, blur/dim/tint live lagte hain. 5 colour swatches us frame se sample hote hain (upar se neeche 5 bands ka average).
- **Preview**: Lock screen par press and hold karein to video chalti hai, chhorne par key-frame still wapas aata hai.

## Files

| File | Kaam |
| --- | --- |
| `lib/state/studio_state.dart` | Poora flow state, video controller, strip frames, key still, palette sampling |
| `lib/services/media_library.dart` | Gallery paging (`MediaPager`) |
| `lib/widgets/media_view.dart` | `MediaThumb`, `StillBackdrop`, `LiveBackdrop` (sample ya real, dono handle) |
| `lib/widgets/mocks.dart` | Lock/Home mocks, kisi bhi background widget par chalte hain |
| `lib/data/scenes.dart` | Sample scenes aur `MediaItem` (sample ya real asset) |
| `lib/screens/*.dart` | 6 screens |
| `lib/services/wallpaper_service.dart` | Native bridge (abhi prototype mode, hamesha success) |

## Abhi baqi hai

1. **Export**: Save/Set abhi sirf UI hai. Real trimmed loop export ke liye FFmpeg (`ffmpeg_kit_flutter`) ya native exporter chahiye, aur Home still ko blur/dim/tint ke saath image mein render karna hai.
2. **iOS save**: native side par `PHAssetCreationRequest` se Live Photo (still + paired video, same content identifier) aur Home still Photos mein save karein.
3. **Android set**: `WallpaperService` banayein aur `WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER` se system chooser kholein.
4. **Bounce loop**: `video_player` reverse nahi chala sakta, isliye preview mein bounce frame-by-frame seek se chalta hai (thoda jhatkedar). Export mein reversed clip banani hogi.
5. **iCloud videos**: jo video device par downloaded nahi, unka `asset.file` null aa sakta hai. Abhi "Could not open this video" dikhta hai.
6. **Recents**: Studio ke Recent tiles abhi sample hain. Saved themes ko disk par rakhna baqi hai.

GitHub par push karne se pehle aap se permission li jayegi, is project ko maine kahin push nahi kiya.
