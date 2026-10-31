package __PKG__

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.service.wallpaper.WallpaperService
import android.view.SurfaceHolder
import org.json.JSONObject
import java.io.File
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/** Live wallpaper made of picture layers that shift when the phone is tilted (depth / parallax). */
class DepthWallpaperService : WallpaperService() {

    override fun onCreateEngine(): Engine = DepthEngine()

    private class Layer(
        val bmp: Bitmap, val d: Float, val cover: Boolean,
        val w: Float, val x: Float, val y: Float, val f: Float,
    )

    private inner class DepthEngine : Engine(), SensorEventListener {
        private val handler = Handler(Looper.getMainLooper())
        private var layers: List<Layer> = emptyList()
        private var invert = false
        private var sens = 1f
        private var visible = false
        private var cfgTime = -1L
        private var sm: SensorManager? = null
        private var tx = 0f
        private var ty = 0f
        private var gx = 0f
        private var gy = 0f
        private var baseY = 7f
        private var haveBase = false
        private val started = SystemClock.uptimeMillis()
        private val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)

        private val frame = object : Runnable {
            override fun run() {
                drawFrame()
                if (visible) handler.postDelayed(this, 16)
            }
        }

        override fun onCreate(holder: SurfaceHolder) {
            super.onCreate(holder)
            sm = getSystemService(SENSOR_SERVICE) as? SensorManager
        }

        override fun onVisibilityChanged(v: Boolean) {
            visible = v
            handler.removeCallbacks(frame)
            if (v) {
                loadConfig()
                val s = sm?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
                if (s != null) sm?.registerListener(this, s, SensorManager.SENSOR_DELAY_GAME)
                handler.post(frame)
            } else {
                sm?.unregisterListener(this)
            }
        }

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            super.onSurfaceChanged(holder, format, width, height)
            drawFrame()
        }

        override fun onDestroy() {
            visible = false
            handler.removeCallbacks(frame)
            sm?.unregisterListener(this)
            layers.forEach { it.bmp.recycle() }
            layers = emptyList()
            super.onDestroy()
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

        override fun onSensorChanged(e: SensorEvent) {
            val x = e.values[0]
            val y = e.values[1]
            if (!haveBase) {
                baseY = y
                haveBase = true
            }
            baseY += (y - baseY) * 0.006f
            val k = (if (invert) -1f else 1f) * sens
            gx = (-x / 4.5f).coerceIn(-1f, 1f) * k
            gy = ((baseY - y) / 4.5f).coerceIn(-1f, 1f) * k
        }

        private fun loadConfig() {
            try {
                val f = File(filesDir, "depth_config.json")
                if (!f.exists()) return
                if (f.lastModified() == cfgTime) return
                cfgTime = f.lastModified()
                val j = JSONObject(f.readText())
                invert = j.optBoolean("inv", false)
                sens = j.optDouble("sens", 1.0).toFloat()
                val arr = j.getJSONArray("layers")
                val out = ArrayList<Layer>()
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    val bmp = decode(o.getString("p")) ?: continue
                    out.add(
                        Layer(
                            bmp,
                            o.optDouble("d", 0.3).toFloat(),
                            o.optBoolean("c", true),
                            o.optDouble("w", 1.0).toFloat(),
                            o.optDouble("x", 0.5).toFloat(),
                            o.optDouble("y", 0.5).toFloat(),
                            o.optDouble("f", 0.0).toFloat(),
                        )
                    )
                }
                val old = layers
                layers = out
                old.forEach { it.bmp.recycle() }
            } catch (_: Throwable) {
            }
        }

        private fun decode(path: String): Bitmap? {
            return try {
                val b = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(path, b)
                var s = 1
                while (max(b.outWidth, b.outHeight) / s > 2200) s *= 2
                val o = BitmapFactory.Options().apply { inSampleSize = s }
                BitmapFactory.decodeFile(path, o)
            } catch (_: Throwable) {
                null
            }
        }

        private fun drawFrame() {
            val holder = surfaceHolder
            var c: Canvas? = null
            try {
                c = if (Build.VERSION.SDK_INT >= 26) holder.lockHardwareCanvas() else holder.lockCanvas()
                if (c != null) render(c)
            } catch (_: Throwable) {
            } finally {
                try {
                    if (c != null) holder.unlockCanvasAndPost(c)
                } catch (_: Throwable) {
                }
            }
        }

        private fun render(c: Canvas) {
            val w = c.width.toFloat()
            val h = c.height.toFloat()
            tx += (gx - tx) * 0.12f
            ty += (gy - ty) * 0.12f
            val t = (SystemClock.uptimeMillis() - started) / 1000f
            c.drawColor(Color.BLACK)
            for ((i, l) in layers.withIndex()) {
                val bw = l.bmp.width.toFloat()
                val bh = l.bmp.height.toFloat()
                val dx = tx * l.d * 0.10f * w + sin(t * 0.6f + i * 1.7f) * l.f * w
                val dy = ty * l.d * 0.06f * h + cos(t * 0.45f + i * 1.7f) * l.f * w
                val s: Float
                val cx: Float
                val cy: Float
                if (l.cover) {
                    s = max(w / bw, h / bh) * (1f + 0.2f * l.d + 4f * l.f)
                    cx = w / 2f + dx
                    cy = h / 2f + dy
                } else {
                    s = l.w * w / bw
                    cx = l.x * w + dx
                    cy = l.y * h + dy
                }
                c.save()
                c.translate(cx, cy)
                c.scale(s, s)
                c.drawBitmap(l.bmp, -bw / 2f, -bh / 2f, paint)
                c.restore()
            }
        }
    }
}
