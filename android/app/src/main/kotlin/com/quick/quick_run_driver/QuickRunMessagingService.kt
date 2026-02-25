package com.quick.quick_run_driver

import android.app.Service
import android.content.Intent
import android.os.Build
import android.util.Log
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


