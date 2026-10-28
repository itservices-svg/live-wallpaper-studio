package com.itservices.live_wallpaper_studio

import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "live_wallpaper_studio/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Opens Android's own "set live wallpaper" screen for our Home or Lock service.
                    "openLive" -> {
                        val cls = when (call.argument<String>("which")) {
                            "lock" -> LockWallpaperService::class.java
                            "studio" -> StudioWallpaperService::class.java
                            else -> HomeWallpaperService::class.java
                        }
                        try {
                            val intent = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER)
                            intent.putExtra(
                                WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT,
                                ComponentName(this, cls)
                            )
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
