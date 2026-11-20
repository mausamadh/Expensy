package com.ma.finwick.sms

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.database.Cursor
import android.os.Build
import android.provider.Telephony.Sms
import android.provider.Telephony.Sms.Inbox
import android.provider.Telephony.Sms.Intents
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.Executors

/**
 * SMS access for Expensy transaction import.
 *
 * Methods (channel com.ma.finwick/sms):
 *  - checkPermissions  -> {read: bool, receive: bool, isDefaultSmsApp: bool}
 *  - requestPermissions -> {read: bool, receive: bool}
 *  - scanSms {limit}   -> [{id, sender, body, timestamp}]
 *  - getSenders        -> [{sender, count}]
 *  - startLiveCapture  -> null (streams via event channel)
 *  - stopLiveCapture   -> null
 *
 * Events (channel com.ma.finwick/sms/events):
 *  - {id, sender, body, timestamp} for each incoming SMS while capturing.
 */
class ExpensySmsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var context: Context
    private var activity: android.app.Activity? = null
    private var liveReceiver: BroadcastReceiver? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val executor = Executors.newSingleThreadExecutor()

    companion object {
        private const val CHANNEL_NAME = "com.ma.finwick/sms"
        private const val EVENT_CHANNEL_NAME = "com.ma.finwick/sms/events"
        private const val REQUEST_CODE_SMS = 42201
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL_NAME)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopLiveCaptureInternal()
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    // ── ActivityAware ────────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != REQUEST_CODE_SMS) return false
        val result = pendingPermissionResult
        pendingPermissionResult = null
        if (result == null) return true
        result.success(mapOf(
            "read" to hasPermission(Manifest.permission.READ_SMS),
            "receive" to hasPermission(Manifest.permission.RECEIVE_SMS)
        ))
        return true
    }

    // ── MethodChannel ────────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkPermissions" -> {
                result.success(mapOf(
                    "read" to hasPermission(Manifest.permission.READ_SMS),
                    "receive" to hasPermission(Manifest.permission.RECEIVE_SMS),
                    "isDefaultSmsApp" to isDefaultSmsApp()
                ))
            }
            "requestPermissions" -> {
                val act = activity
                if (act == null) {
                    result.error("NO_ACTIVITY", "No activity attached", null)
                    return
                }
                // Already granted? Report immediately.
                if (hasPermission(Manifest.permission.READ_SMS) &&
                    hasPermission(Manifest.permission.RECEIVE_SMS)
                ) {
                    result.success(mapOf(
                        "read" to true,
                        "receive" to true
                    ))
                    return
                }
                val perms = arrayOf(
                    Manifest.permission.READ_SMS,
                    Manifest.permission.RECEIVE_SMS
                )
                pendingPermissionResult = result
                ActivityCompat.requestPermissions(act, perms, REQUEST_CODE_SMS)
            }
            "scanSms" -> {
                if (!canReadSms()) {
                    result.error("NO_PERMISSION", "READ_SMS permission not granted", null)
                    return
                }
                val limit = (call.argument<Int>("limit") ?: 500).coerceIn(1, 5000)
                val beforeTimestamp =
                    call.argument<Number>("beforeTimestamp")?.toLong()
                val beforeId = call.argument<Number>("beforeId")?.toLong()
                executor.execute {
                    try {
                        result.success(scanSms(limit, beforeTimestamp, beforeId))
                    } catch (e: Exception) {
                        result.error("SCAN_FAILED", e.message ?: "Failed to read SMS", null)
                    }
                }
            }
            "getSenders" -> {
                if (!canReadSms()) {
                    result.error("NO_PERMISSION", "READ_SMS permission not granted", null)
                    return
                }
                executor.execute {
                    try {
                        result.success(getSenders())
                    } catch (e: Exception) {
                        result.error("SCAN_FAILED", e.message ?: "Failed to read SMS", null)
                    }
                }
            }
            "startLiveCapture" -> {
                if (!hasPermission(Manifest.permission.RECEIVE_SMS)) {
                    result.error("NO_PERMISSION", "RECEIVE_SMS permission not granted", null)
                    return
                }
                startLiveCaptureInternal()
                result.success(null)
            }
            "stopLiveCapture" -> {
                stopLiveCaptureInternal()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ── EventChannel ─────────────────────────────────────────────────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // ── SMS reading ──────────────────────────────────────────────────────────

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    /** The default SMS app may read SMS without the READ_SMS permission. */
    private fun isDefaultSmsApp(): Boolean =
        try {
            val defaultSms = Sms.getDefaultSmsPackage(context)
            defaultSms != null && defaultSms == context.packageName
        } catch (e: Exception) {
            false
        }

    private fun canReadSms(): Boolean = hasPermission(Manifest.permission.READ_SMS) || isDefaultSmsApp()

    private fun scanSms(
        limit: Int,
        beforeTimestamp: Long?,
        beforeId: Long?
    ): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            Inbox._ID,
            Inbox.ADDRESS,
            Inbox.BODY,
            Inbox.DATE
        )
        val selection = when {
            beforeTimestamp != null && beforeId != null ->
                "(${Inbox.DATE} < ? OR (${Inbox.DATE} = ? AND ${Inbox._ID} < ?))"
            beforeTimestamp != null -> "${Inbox.DATE} < ?"
            else -> null
        }
        val selectionArgs = when {
            beforeTimestamp != null && beforeId != null ->
                arrayOf(beforeTimestamp.toString(), beforeTimestamp.toString(), beforeId.toString())
            beforeTimestamp != null -> arrayOf(beforeTimestamp.toString())
            else -> null
        }
        val cursor: Cursor = context.contentResolver.query(
            Inbox.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            "${Inbox.DATE} DESC, ${Inbox._ID} DESC LIMIT $limit"
        ) ?: return out
        cursor.use { c ->
            val idCol = c.getColumnIndexOrThrow(Inbox._ID)
            val addrCol = c.getColumnIndexOrThrow(Inbox.ADDRESS)
            val bodyCol = c.getColumnIndexOrThrow(Inbox.BODY)
            val dateCol = c.getColumnIndexOrThrow(Inbox.DATE)
            while (c.moveToNext()) {
                val body = c.getString(bodyCol) ?: continue
                if (body.isBlank()) continue
                out.add(mapOf(
                    "id" to c.getLong(idCol),
                    "sender" to (c.getString(addrCol) ?: ""),
                    "body" to body,
                    "timestamp" to c.getLong(dateCol)
                ))
            }
        }
        return out
    }

    private fun getSenders(): List<Map<String, Any?>> {
        val counts = LinkedHashMap<String, Int>()
        val projection = arrayOf(Inbox.ADDRESS)
        val cursor: Cursor = context.contentResolver.query(
            Inbox.CONTENT_URI,
            projection,
            null,
            null,
            "${Inbox.DATE} DESC LIMIT 2000"
        ) ?: return emptyList()
        cursor.use { c ->
            val addrCol = c.getColumnIndexOrThrow(Inbox.ADDRESS)
            while (c.moveToNext()) {
                val addr = c.getString(addrCol) ?: continue
                if (addr.isBlank()) continue
                counts[addr] = (counts[addr] ?: 0) + 1
            }
        }
        return counts.entries
            .sortedByDescending { it.value }
            .map { mapOf("sender" to it.key, "count" to it.value) }
    }

    // ── Live capture ─────────────────────────────────────────────────────────

    private fun startLiveCaptureInternal() {
        if (liveReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                if (intent.action != Intents.SMS_RECEIVED_ACTION) return
                val messages = Intents.getMessagesFromIntent(intent) ?: return
                for (msg in messages) {
                    val sender = msg.originatingAddress ?: ""
                    val body = msg.messageBody ?: continue
                    if (body.isBlank()) continue
                    eventSink?.success(mapOf(
                        "id" to (System.currentTimeMillis() * 1000L),
                        "sender" to sender,
                        "body" to body,
                        "timestamp" to System.currentTimeMillis()
                    ))
                }
            }
        }
        val filter = IntentFilter(Intents.SMS_RECEIVED_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
        liveReceiver = receiver
    }

    private fun stopLiveCaptureInternal() {
        liveReceiver?.let {
            try {
                context.unregisterReceiver(it)
            } catch (e: Exception) {
                // Already unregistered.
            }
        }
        liveReceiver = null
    }
}
