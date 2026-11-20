package com.ma.finwick.sms

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class SmsBackgroundReceiver : BroadcastReceiver() {
    companion object {
        private const val CHANNEL_ID = "expensy_sms_background"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit().putLong("flutter.sms_pending_reconcile_at", System.currentTimeMillis()).apply()

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: return
        launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        launchIntent.putExtra("expensy_open", "sms_inbox")

        val pending = PendingIntent.getActivity(
            context,
            42202,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                    PendingIntent.FLAG_IMMUTABLE
                else 0
        )

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "SMS transaction parsing",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Incoming SMS waiting for parsing"
                }
            )
        }

        val sender = messages.firstOrNull()?.originatingAddress ?: "SMS"
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle("SMS received")
            .setContentText("Expensy is checking $sender for a transaction")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(42202, notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS may be denied; startup reconciliation still runs.
        }
    }
}
