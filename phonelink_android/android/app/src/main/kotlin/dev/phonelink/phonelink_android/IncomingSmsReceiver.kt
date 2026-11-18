package dev.phonelink.phonelink_android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/** SMS delivery does not depend on the Flutter activity being attached. */
class IncomingSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (parts.isEmpty()) return
        val event = mapOf("type" to "sms", "from" to (parts[0].originatingAddress ?: "unknown"),
            "body" to parts.joinToString("") { it.messageBody.orEmpty() },
            "date" to parts[0].timestampMillis)
        val pending = goAsync()
        val app = context.applicationContext
        Thread {
            try { NotificationRelay.sendLocally(app, event, requireNotificationAccess = false) }
            finally { pending.finish() }
        }.start()
    }
}
