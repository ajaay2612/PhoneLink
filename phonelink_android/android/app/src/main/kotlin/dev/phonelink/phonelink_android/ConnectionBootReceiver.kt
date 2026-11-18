package dev.phonelink.phonelink_android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/** Restore only an enabled, previously trusted pairing after login/update. */
class ConnectionBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("flutter.connectionEnabled", false)) return
        val token = prefs.getString("flutter.token", "").orEmpty()
        val pin = prefs.getString("flutter.serverPin", "").orEmpty()
        if (!token.matches(Regex("[a-f0-9]{64}")) || !pin.matches(Regex("[a-f0-9]{64}"))) return
        try {
            val service = Intent(context, ClipboardControlService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(service)
            else context.startService(service)
        } catch (_: IllegalStateException) {
            // Respect OS/vendor background-start restrictions; opening the app can retry.
        } catch (_: SecurityException) {
            // A revoked permission must not crash boot or bypass user control.
        }
    }
}
