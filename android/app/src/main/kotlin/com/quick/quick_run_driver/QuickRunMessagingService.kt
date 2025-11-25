package com.quick.quick_run_driver

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Native FCM handler so NEW_ORDER can wake/ring/show overlay even when Flutter is terminated.
 *
 * Expected data payload keys (best-effort, all optional):
 * - type: "NEW_ORDER"
 * - mode: "seller" | "driver"   (seller => no accept button)
 * - orderId, customerId
 * - itemText, pickupText, dropText
 */
class QuickRunMessagingService : FirebaseMessagingService() {

    private fun ensureNativeOrderChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val mgr = getSystemService(NotificationManager::class.java)
                val channel = NotificationChannel(
                    "native_new_order_channel_v1",
                    "Native New Orders",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Native fallback alerts for incoming orders"
                    setShowBadge(true)
                }
                mgr.createNotificationChannel(channel)
            } catch (e: Exception) {
                Log.e("QuickRunMessagingService", "Failed to create native order channel", e)
            }
        }
    }

    private fun showNativeFallbackNotification(orderId: String, title: String, body: String) {
        try {
            ensureNativeOrderChannel()

            // Open app when tapped (and allow full-screen heads-up on lockscreen).
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            launchIntent?.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            )

            val pendingIntent = android.app.PendingIntent.getActivity(
                this,
                1001,
                launchIntent,
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) android.app.PendingIntent.FLAG_IMMUTABLE else 0) or
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT
            )

            val notif = NotificationCompat.Builder(this, "native_new_order_channel_v1")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setAutoCancel(true)
                // Full screen intent helps on lock screen for high priority notifications.
                .setFullScreenIntent(pendingIntent, true)
                .setContentIntent(pendingIntent)
                // Use same custom sound resource as FloatingService (best-effort).
                .setSound(
                    android.net.Uri.parse("android.resource://$packageName/${R.raw.order_notification}")
                )
                .build()

            NotificationManagerCompat.from(this).notify(
                (System.currentTimeMillis() % Int.MAX_VALUE).toInt(),
                notif
            )

            Log.d("QuickRunMessagingService", "Native fallback notification shown for orderId=$orderId")
        } catch (e: Exception) {
            Log.e("QuickRunMessagingService", "Failed to show native fallback notification", e)
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        try {
            if (FirebaseApp.getApps(this).isEmpty()) {
                FirebaseApp.initializeApp(this)
            }
        } catch (_: Exception) {}

        val data = message.data
        val type = (data["type"] ?: message.notification?.title ?: "").trim().uppercase()
        val orderId = (data["orderId"] ?: data["order_id"] ?: "").trim()

        Log.d(
            "QuickRunMessagingService",
            "FCM received. messageId=${message.messageId} type=$type orderId=$orderId data=$data"
        )

        val isOrder = type == "NEW_ORDER" || orderId.isNotEmpty()
        if (!isOrder) {
            Log.d("QuickRunMessagingService", "Ignored (not an order). type=$type orderId=$orderId")
            return
        }

        // Default to the locally logged-in userType if backend doesn't provide mode
        val prefs = getSharedPreferences("FlutterSharedPreferences", Service.MODE_PRIVATE)
        val savedUserType = prefs.getString("flutter.userType", null)
        val defaultMode = if (savedUserType == "seller") "seller" else "driver"

        val mode = (data["mode"] ?: defaultMode).trim().lowercase() // seller | driver
        val showAccept = mode != "seller"

        // Native fallback notification (works even if overlay permission/service is blocked)
        val title = (data["title"] ?: "New Order").trim()
        val body = (data["body"] ?: "You have a new order").trim()
        if (orderId.isNotBlank()) {
            showNativeFallbackNotification(orderId, title, body)
        }

        val intent = Intent(this, FloatingService::class.java).apply {
            putExtra("hasNewOrder", true)
            putExtra("overlayMode", mode)
            putExtra("overlayShowAccept", showAccept)
            putExtra("overlayOrderId", orderId)
            putExtra("overlayCustomerId", (data["customerId"] ?: data["customer_id"] ?: "").trim())
            putExtra("overlayItemText", (data["itemText"] ?: data["item"] ?: message.notification?.body ?: "New Order").trim())
            putExtra("overlayPickupText", (data["pickupText"] ?: "Pickup:").trim())
            putExtra("overlayDropText", (data["dropText"] ?: "Drop:").trim())
            // Ensure service is allowed to show overlay (Flutter will set foreground state when it starts)
            putExtra("appInForeground", false)
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            Log.d("QuickRunMessagingService", "Started FloatingService for NEW_ORDER mode=$mode orderId=$orderId")
        } catch (e: Exception) {
            Log.e("QuickRunMessagingService", "Failed to start FloatingService for NEW_ORDER", e)
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d("QuickRunMessagingService", "FCM token refreshed: $token")
    }
}


