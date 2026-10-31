package __PKG__

import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lws/depth")
            .setMethodCallHandler { call, result ->
                val comp = ComponentName(this, DepthWallpaperService::class.java)
                when (call.method) {
                    "setConfig" -> {
                        try {
                            val json = call.arguments as String
                            File(filesDir, "depth_config.json").writeText(json)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("write", e.message, null)
                        }
                    }
                    "openPicker" -> {
                        try {
                            val i = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER)
                                .putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, comp)
                            startActivity(i)
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                startActivity(Intent(WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER))
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("picker", e2.message, null)
                            }
                        }
                    }
                    "isActive" -> {
                        val info = WallpaperManager.getInstance(this).wallpaperInfo
                        result.success(info != null && info.component == comp)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
