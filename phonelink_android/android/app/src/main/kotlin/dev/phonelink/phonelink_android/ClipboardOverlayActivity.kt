package dev.phonelink.phonelink_android

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.content.res.Configuration
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.WindowManager
import android.widget.TextView
import android.widget.Toast
import java.util.concurrent.Executors

/** Focus is acquired only after the user taps the notification action. */
class ClipboardOverlayActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private var handled = false
    private val timeout = Runnable { finish() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN)
        window.setGravity(Gravity.TOP or Gravity.CENTER_HORIZONTAL)
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val appearance = prefs.getString("flutter.themeMode", "system")
        val systemDark = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        val dark = appearance == "dark" || (appearance == "system" && systemDark)
        val density = resources.displayMetrics.density
        setContentView(TextView(this).apply {
            text = "Sending clipboard…"
            textSize = 14f
            setTextColor(if (dark) 0xFFE8E8E7.toInt() else 0xFF182D29.toInt())
            background = GradientDrawable().apply {
                setColor(if (dark) 0xFF191B1C.toInt() else 0xFFFFFFFF.toInt())
                cornerRadius = 10 * density
                setStroke(1, if (dark) 0xFF303335.toInt() else 0xFFE1E6DE.toInt())
            }
            setPadding((16 * density).toInt(), (12 * density).toInt(), (16 * density).toInt(), (12 * density).toInt())
        })
        window.setLayout(WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT)
        handler.postDelayed(timeout, 4000)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || handled) return
        handled = true
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("flutter.connectionEnabled", true)) {
            Toast.makeText(this, "Connect your PC first", Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        val text = try {
            val clip = (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).primaryClip
            if (clip != null && clip.itemCount > 0) clip.getItemAt(0).text?.toString() else null
        } catch (_: SecurityException) { null }
        if (text.isNullOrEmpty()) {
            Toast.makeText(this, "Clipboard empty or unavailable", Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        // Keep Flutter's clipboard watcher in step with this native send.
        NotificationRelay.channel?.invokeMethod("clipboardSent", text)
        val app = applicationContext
        sender.execute {
            val sent = NotificationRelay.sendLocally(app, mapOf("type" to "clip", "text" to text),
                requireNotificationAccess = false)
            if (!sent) handler.post {
                Toast.makeText(app, "Could not reach PC", Toast.LENGTH_SHORT).show()
            }
        }
        // Sending continues independently; immediately restore the previous app's focus.
        finish()
    }

    override fun onDestroy() {
        handler.removeCallbacks(timeout)
        super.onDestroy()
    }

    companion object {
        private val sender = Executors.newSingleThreadExecutor()
    }
}
