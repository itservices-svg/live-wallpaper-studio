package com.itservices.live_wallpaper_studio

import android.media.MediaPlayer
import android.service.wallpaper.WallpaperService
import android.view.SurfaceHolder
import java.io.File

/**
 * Plays the newest "<prefix>_*.mp4" from files/wallpaper as a looping, silent live wallpaper.
 * The Flutter app writes those files; Home and Lock use separate subclasses so each can
 * have its own video.
 */
abstract class BaseVideoWallpaperService : WallpaperService() {
    abstract val prefix: String

    override fun onCreateEngine(): Engine = VideoEngine()

    private fun latestVideo(): File? {
        val dir = File(filesDir, "wallpaper")
        val files = dir.listFiles { f -> f.name.startsWith(prefix + "_") && f.name.endsWith(".mp4") }
        return files?.maxByOrNull { it.lastModified() }
    }

    inner class VideoEngine : Engine() {
        private var player: MediaPlayer? = null
        private var holder: SurfaceHolder? = null
        private var visible = false
        private var playingPath: String? = null

        override fun onSurfaceCreated(surfaceHolder: SurfaceHolder) {
            super.onSurfaceCreated(surfaceHolder)
            holder = surfaceHolder
            startPlayer()
        }

        override fun onSurfaceDestroyed(surfaceHolder: SurfaceHolder) {
            stopPlayer()
            holder = null
            super.onSurfaceDestroyed(surfaceHolder)
        }

        override fun onVisibilityChanged(isVisible: Boolean) {
            visible = isVisible
            if (isVisible) {
                // A newer video may have been written while we were hidden.
                if (player == null || latestVideo()?.path != playingPath) {
                    startPlayer()
                } else {
                    try { player?.start() } catch (_: Exception) {}
                }
            } else {
                try { player?.pause() } catch (_: Exception) {}
            }
        }

        private fun startPlayer() {
            val h = holder ?: return
            val file = latestVideo() ?: return
            stopPlayer()
            try {
                val p = MediaPlayer()
                p.setSurface(h.surface)
                p.setDataSource(file.path)
                p.isLooping = true
                p.setVolume(0f, 0f)
                p.setOnPreparedListener { mp -> if (visible) mp.start() }
                p.setOnErrorListener { _, _, _ -> true }
                p.prepareAsync()
                player = p
                playingPath = file.path
            } catch (_: Exception) {
                stopPlayer()
            }
        }

        private fun stopPlayer() {
            try { player?.release() } catch (_: Exception) {}
            player = null
            playingPath = null
        }

        override fun onDestroy() {
            stopPlayer()
            super.onDestroy()
        }
    }
}
