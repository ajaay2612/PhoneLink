package dev.phonelink.phonelink_android

import android.app.Notification
import android.content.Context
import android.content.ComponentName
import android.provider.Settings
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Base64
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.net.InetAddress
import java.net.URI
import java.security.MessageDigest
import java.security.cert.X509Certificate
import java.security.cert.CertificateException
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509TrustManager
import javax.net.ssl.TrustManager
import java.security.SecureRandom
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

class PhoneNotificationListener : NotificationListenerService() {
    companion object {
        @Volatile var connectedListener: PhoneNotificationListener? = null
    }

    override fun onListenerConnected() {
        connectedListener = this
        NotificationRelay.deliver(this, mapOf("type" to "notification_snapshot", "items" to snapshot()))
    }

    override fun onListenerDisconnected() {
        if (connectedListener === this) connectedListener = null
    }

    override fun onDestroy() {
        if (connectedListener === this) connectedListener = null
        super.onDestroy()
    }

    fun snapshot(): List<Map<String, Any?>> = try {
        activeNotifications.orEmpty().sortedByDescending { it.postTime }.mapNotNull { entry(it) }.take(50)
    } catch (_: SecurityException) { emptyList() }

    private fun entry(sbn: StatusBarNotification): Map<String, Any?>? {
        val notification = sbn.notification
        if (sbn.packageName == packageName || notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return null
        val extras = notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty().take(256)
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty().take(4000)
        if (title.isBlank() && text.isBlank()) return null
        val app = try { packageManager.getApplicationLabel(packageManager.getApplicationInfo(sbn.packageName, 0)).toString() }
            catch (_: Exception) { sbn.packageName }
        return mapOf("key" to sbn.key, "package" to sbn.packageName, "app" to app,
            "title" to title, "text" to text, "time" to sbn.postTime)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val item = entry(sbn) ?: return
        NotificationRelay.deliver(this, mapOf("type" to "notification", "item" to item))
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        if (sbn.packageName != packageName) NotificationRelay.deliver(this,
            mapOf("type" to "notification_removed", "key" to sbn.key))
    }
}

internal object NotificationRelay {
    @Volatile var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())
    private val worker = ThreadPoolExecutor(1, 1, 10, TimeUnit.SECONDS,
        ArrayBlockingQueue<Runnable>(64), ThreadPoolExecutor.DiscardOldestPolicy())

    fun hasAccess(context: Context): Boolean =
        Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners").orEmpty()
            .split(':').any { ComponentName.unflattenFromString(it)?.packageName == context.packageName }

    fun deliver(context: Context, event: Map<String, Any?>) {
        val app = context.applicationContext
        val prefs = app.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("flutter.connectionEnabled", true) || !hasAccess(app)) return
        main.post {
            val bridge = channel
            if (bridge == null) {
                worker.execute { sendLocally(app, event) }
            } else {
                bridge.invokeMethod("notificationEvent", event, object : MethodChannel.Result {
                    override fun success(result: Any?) {}
                    override fun error(code: String, message: String?, details: Any?) { worker.execute { sendLocally(app, event) } }
                    override fun notImplemented() { worker.execute { sendLocally(app, event) } }
                })
            }
        }
    }

    // The listener can remain active without a Flutter activity. Use the same paired local socket.
    fun sendLocally(context: Context, event: Map<String, Any?>, requireNotificationAccess: Boolean = true): Boolean {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            if (!prefs.getBoolean("flutter.connectionEnabled", true) || (requireNotificationAccess && !hasAccess(context))) return false
            val host = prefs.getString("flutter.host", null) ?: return false
            val token = prefs.getString("flutter.token", null)?.takeIf { it.isNotEmpty() } ?: return false
            val pin = prefs.getString("flutter.serverPin", null) ?: return false
            if (!token.matches(Regex("[a-f0-9]{64}")) || !pin.matches(Regex("[a-f0-9]{64}"))) return false
            val endpoint = URI("https://$host")
            val address = endpoint.host ?: return false
            val port = endpoint.port
            if (port !in 1..65535 || endpoint.userInfo != null || !endpoint.path.isNullOrEmpty() ||
                endpoint.query != null || endpoint.fragment != null || !address.matches(Regex("[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+"))) return false
            val ip = InetAddress.getByName(address)
            if (!ip.isSiteLocalAddress && !ip.isLoopbackAddress && !ip.isLinkLocalAddress) return false
            val expected = pin.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
            val trust = object : X509TrustManager {
                override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
                override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {
                    throw CertificateException("Client certificates are not accepted")
                }
                override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                    if (chain.isEmpty()) throw CertificateException("Missing server identity")
                    chain[0].checkValidity()
                    val actual = MessageDigest.getInstance("SHA-256").digest(chain[0].encoded)
                    if (!MessageDigest.isEqual(actual, expected)) throw CertificateException("Paired PC identity changed")
                }
            }
            val tls = SSLContext.getInstance("TLS").apply { init(null, arrayOf<TrustManager>(trust), SecureRandom()) }
            Socket().use { raw ->
              raw.connect(InetSocketAddress(ip, port), 2500)
              (tls.socketFactory.createSocket(raw, address, port, true) as SSLSocket).use { socket ->
                socket.soTimeout = 5000
                socket.enabledProtocols = arrayOf("TLSv1.3", "TLSv1.2").filter { it in socket.supportedProtocols }.toTypedArray()
                socket.startHandshake()
                val output = socket.getOutputStream()
                val key = ByteArray(16).also { SecureRandom().nextBytes(it) }
                val handshake = "GET / HTTP/1.1\r\nHost: $host\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
                    "Sec-WebSocket-Key: ${Base64.encodeToString(key, Base64.NO_WRAP)}\r\nSec-WebSocket-Version: 13\r\nX-Token: $token\r\n\r\n"
                output.write(handshake.toByteArray(Charsets.UTF_8))
                output.flush()
                val response = StringBuilder()
                val input = socket.getInputStream()
                while (!response.endsWith("\r\n\r\n") && response.length < 8192) {
                    val next = input.read()
                    if (next < 0) return false
                    response.append(next.toChar())
                }
                if (!response.startsWith("HTTP/1.1 101")) return false
                frame(output, JSONObject().put("type", "hello").put("v", 2).put("token", token).toString())
                frame(output, JSONObject(event).toString())
                output.flush()
                return true
              }
            }
        } catch (_: Exception) { return false }
    }

    private fun frame(output: OutputStream, text: String) {
        val data = text.toByteArray(Charsets.UTF_8)
        val mask = ByteArray(4).also { SecureRandom().nextBytes(it) }
        val frame = ByteArrayOutputStream()
        frame.write(0x81)
        when {
            data.size < 126 -> frame.write(0x80 or data.size)
            data.size < 65536 -> { frame.write(0xFE); frame.write(data.size shr 8); frame.write(data.size and 0xFF) }
            else -> { frame.write(0xFF); for (shift in 7 downTo 0) frame.write(((data.size.toLong() shr (shift * 8)) and 0xFF).toInt()) }
        }
        frame.write(mask)
        for (index in data.indices) frame.write(data[index].toInt() xor mask[index % 4].toInt())
        output.write(frame.toByteArray())
    }
}
