package com.itservices.live_wallpaper_studio

import android.service.wallpaper.WallpaperService

/**
 * One wallpaper for both screens: the Lock engine plays the sharp video and the Home
 * engine plays the blurred one. Which screen an engine draws on is read from
 * Engine.getWallpaperFlags() (reflection, so older Android versions still compile and
 * simply fall back to the Home video).
 */
class StudioWallpaperService : BaseVideoWallpaperService() {
    override val prefix = "home"

    override fun prefixFor(engine: WallpaperService.Engine): String {
        return try {
            val m = WallpaperService.Engine::class.java.getMethod("getWallpaperFlags")
            val flags = m.invoke(engine) as Int
            // FLAG_SYSTEM = 1 (home), FLAG_LOCK = 2
            if ((flags and 2) != 0 && (flags and 1) == 0) "lock" else "home"
        } catch (e: Exception) {
            "home"
        }
    }
}
