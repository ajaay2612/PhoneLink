package dev.phonelink.phonelink_android
import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import android.os.Environment
import android.net.Uri
import android.app.KeyguardManager
import android.content.ClipData
import android.content.ClipboardManager
import android.os.PowerManager
import android.content.IntentFilter
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import android.app.Activity
import android.app.NotificationManager
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel.Result
import java.lang.ref.WeakReference

/** One application-scoped engine; the foreground service outlives its window. */
internal object PhoneRuntime {
    private var engine: FlutterEngine? = null
    private lateinit var context: Context
    private var activity = WeakReference<Activity>(null)
    var serviceRunning = false

    fun attachActivity(value: Activity) { activity = WeakReference(value) }
    fun detachActivity(value: Activity) { if (activity.get() === value) activity.clear() }
    private fun requireActivity(): Activity = activity.get()
        ?: throw IllegalStateException("Open Fonelink to change permissions")

    fun getEngine(value: Context): FlutterEngine {
        engine?.let { return it }
        context = value.applicationContext
        val created = FlutterEngine(context)
        engine = created
        val channel = MethodChannel(created.dartExecutor.binaryMessenger, "phonelink/share")
        NotificationRelay.channel = channel
        channel.setMethodCallHandler { call, result ->
          try {
            when (call.method) {
                "activityAttached" -> result.success(activity.get() != null)
                "connectionState" -> {
                    ClipboardControlService.updateConnection(call.arguments == true)
                    result.success(null)
                }
                "connectionNotificationsEnabled" -> {
                    val manager = context.getSystemService(NotificationManager::class.java)
                    val channel = if (Build.VERSION.SDK_INT >= 26) manager.getNotificationChannel("phonelink_persistent") else null
                    result.success(manager.areNotificationsEnabled() && channel?.importance != NotificationManager.IMPORTANCE_NONE)
                }
                "openConnectionNotifications" -> {
                    val intent = if (Build.VERSION.SDK_INT >= 26) {
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                    } else {
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:${context.packageName}"))
                    }
                    requireActivity().startActivity(intent)
                    result.success(null)
                }
                "getSmsHistory" -> readSmsHistory(result)
                "storageAccess" -> result.success(storageAccess())
                "openStorageAccess" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 30) {
                            val appSettings = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                Uri.parse("package:${context.packageName}"))
                            try { requireActivity().startActivity(appSettings) }
                            catch (_: android.content.ActivityNotFoundException) {
                                requireActivity().startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                            }
                        } else if (Build.VERSION.SDK_INT >= 23 && !storageAccess()) {
                            requireActivity().requestPermissions(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE,
                                Manifest.permission.WRITE_EXTERNAL_STORAGE), 41)
                        } else {
                            requireActivity().startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:${context.packageName}")))
                        }
                        result.success(null)
                    } catch (error: Exception) { result.error("storage_settings_unavailable", error.message, null) }
                }
                "notificationAccess" -> result.success(notificationAccess())
                "getNotifications" -> result.success(PhoneNotificationListener.connectedListener?.snapshot() ?: emptyList<Map<String, Any?>>())
                "openNotificationAccess" -> {
                    try { requireActivity().startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)); result.success(null) }
                    catch (error: Exception) { result.error("settings_unavailable", error.message, null) }
                }
                "receiveClipboard" -> {
                    val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                    val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                    val text = call.arguments as? String
                    if (keyguard.isKeyguardLocked || !power.isInteractive || text == null) {
                        result.success(false)
                    } else {
                        try {
                            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                            clipboard.setPrimaryClip(ClipData.newPlainText("", text))
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("clipboard_unavailable", error.message, null)
                        }
                    }
                }
                "deviceStatus" -> result.success(deviceStatus())
                "startClipboardControls" -> {
                    val service = Intent(context, ClipboardControlService::class.java)
                    if (!serviceRunning) {
                        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(service) else context.startService(service)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
          } catch (error: Exception) {
            result.error("native_action_unavailable", error.message, null)
          }
        }
        created.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        return created
    }

    private fun readSmsHistory(result: Result) {
        Thread {
            try {
                val rows = mutableListOf<Map<String, Any?>>()
                context.contentResolver.query(Telephony.Sms.Inbox.CONTENT_URI,
                    arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
                    null, null, "${Telephony.Sms.DATE} DESC")?.use { cursor ->
                    while (rows.size < 30 && cursor.moveToNext()) {
                        rows.add(mapOf("from" to (cursor.getString(0) ?: "?"),
                            "body" to (cursor.getString(1) ?: ""), "date" to cursor.getLong(2)))
                    }
                }
                Handler(Looper.getMainLooper()).post { result.success(rows) }
            } catch (error: Exception) {
                Handler(Looper.getMainLooper()).post { result.error("sms_unavailable", error.message, null) }
            }
        }.start()
    }

    private fun storageAccess(): Boolean = when {
        Build.VERSION.SDK_INT >= 30 -> Environment.isExternalStorageManager()
        Build.VERSION.SDK_INT >= 23 -> context.checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
            && context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        else -> true
    }

    private fun notificationAccess(): Boolean = NotificationRelay.hasAccess(context)

    @Suppress("DEPRECATION")
    private fun deviceStatus(): Map<String, Any?> {
        val fallbackName = "${Build.MANUFACTURER} ${Build.MODEL}".trim()
        val name = try { Settings.Global.getString(context.contentResolver, "device_name") } catch (_: Exception) { null }
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val percent = if (level >= 0 && scale > 0) (level * 100 / scale).coerceIn(0, 100) else null
        val chargingStatus = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val charging = chargingStatus == BatteryManager.BATTERY_STATUS_CHARGING || chargingStatus == BatteryManager.BATTERY_STATUS_FULL
        var network = "Unavailable"
        var wifiLabel = "Unavailable"
        try {
            val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val capabilities = manager.getNetworkCapabilities(manager.activeNetwork)
            network = when {
                capabilities == null -> "Offline"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "Mobile data"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet"
                else -> "Other network"
            }
            val wifi = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val info = wifi.connectionInfo
            val wifiConnected = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true || (info != null && info.networkId != -1)
            wifiLabel = if (wifiConnected) {
                val ssid = info?.ssid?.trim('"')?.takeUnless { it == "<unknown ssid>" || it.isBlank() }
                val rssi = info?.rssi ?: -127
                val strength = if (rssi in -100..-30) ((rssi + 100) * 100 / 70).coerceIn(0, 100) else null
                listOfNotNull(ssid ?: "Connected", strength?.let { "$it% signal" }).joinToString(" · ")
            } else if (wifi.isWifiEnabled) "Not connected" else "Off"
        } catch (_: SecurityException) { /* Restricted identifiers stay unavailable. */ }
        return mapOf("name" to (name?.takeIf { it.isNotBlank() } ?: fallbackName),
            "battery" to percent, "charging" to charging, "network" to network, "wifi" to wifiLabel,
            "notificationAccess" to notificationAccess(), "statusSupported" to true)
    }

}
