package dev.phonelink.phonelink_android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import android.util.Log

class ClipboardControlService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val notificationCheck = object : Runnable {
        override fun run() {
            restoreMissingNotification()
            handler.postDelayed(this, 5000)
        }
    }
    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            restoreMissingNotification()
        }
    }
    companion object {
        private var instance: ClipboardControlService? = null
        private var connected = false

        fun updateConnection(value: Boolean) {
            connected = value
            instance?.showNotification()
        }
    }
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        PhoneRuntime.serviceRunning = true
        showNotification(promoteToForeground = true)
        val filter = IntentFilter(Intent.ACTION_USER_PRESENT).apply {
            addAction(Intent.ACTION_SCREEN_ON)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(screenReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(screenReceiver, filter)
        }
        handler.postDelayed(notificationCheck, 5000)
        PhoneRuntime.getEngine(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        showNotification()
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(notificationCheck)
        unregisterReceiver(screenReceiver)
        if (instance === this) instance = null
        connected = false
        PhoneRuntime.serviceRunning = false
        super.onDestroy()
    }

    private fun restoreMissingNotification() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        if (!prefs.getBoolean("flutter.connectionEnabled", false)) return
        if (prefs.getString("flutter.token", "").orEmpty().isEmpty()) return
        val manager = getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return
        if (Build.VERSION.SDK_INT >= 26 &&
            manager.getNotificationChannel("phonelink_persistent")?.importance == NotificationManager.IMPORTANCE_NONE) return
        if (manager.activeNotifications.none { it.id == 1 && it.tag == null }) {
            showNotification()
            Log.i("PhoneLinkService", "Restored missing connection controls")
        }
    }

    private fun showNotification(promoteToForeground: Boolean = false) {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(
                "phonelink_persistent", "Connection and clipboard", NotificationManager.IMPORTANCE_LOW))
        }
        val sendIntent = Intent(this, ClipboardOverlayActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
        }
        val send = PendingIntent.getActivity(this, 20, sendIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val open = PendingIntent.getActivity(this, 21, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "phonelink_persistent")
            else Notification.Builder(this)
        val enabled = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            .getBoolean("flutter.connectionEnabled", true)
        val status = if (connected) "PC connected" else if (enabled) "Waiting for PC" else "Disconnected"
        if (Build.VERSION.SDK_INT >= 31) builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        val notification = builder.setSmallIcon(R.drawable.ic_stat_phonelink)
            .setContentTitle("PhoneLink · $status").setContentText("Copy text, then tap Send clipboard to PC")
            .setContentIntent(open).setOngoing(true).setShowWhen(false).setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, "Send clipboard to PC", send).build()).build()
        if (!promoteToForeground) {
            manager.notify(1, notification)
        } else if (Build.VERSION.SDK_INT >= 34) {
            startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else startForeground(1, notification)
    }
}
