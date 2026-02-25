package com.quick.quick_run_driver

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "floating.chat.head"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startBubble" -> {
                        android.util.Log.d("MainActivity", "startBubble CALLED from Flutter")
                        Toast.makeText(this, "startBubble CALLED", Toast.LENGTH_SHORT).show()

                        if (!Settings.canDrawOverlays(this)) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                            result.error("NO_PERMISSION", "Overlay permission not granted", null)
                            return@setMethodCallHandler
                        }

                        val intent = Intent(this, FloatingService::class.java)

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }

                        result.success(true)
                    }

                    "stopBubble" -> {
                        android.util.Log.d("MainActivity", "stopBubble CALLED from Flutter")
                        Toast.makeText(this, "Bubble Stopped", Toast.LENGTH_SHORT).show()

                        val intent = Intent(this, FloatingService::class.java)
                        stopService(intent)

                        result.success(true)
                    }
                    
                    "setAcceptedOrder" -> {
                        try {
                            android.util.Log.d("MainActivity", "setAcceptedOrder CALLED from Flutter")
                            val customerId = call.argument<String>("customerId")
                            val orderId = call.argument<String>("orderId")
                            
                            if (customerId != null && orderId != null) {
                                android.util.Log.d("MainActivity", "Starting FloatingService with customerId=$customerId, orderId=$orderId")
                                
                                val intent = Intent(this, FloatingService::class.java).apply {
                                    putExtra("customerId", customerId)
                                    putExtra("orderId", orderId)
                                }
                                
                                try {
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                        startForegroundService(intent)
                                    } else {
                                        startService(intent)
                                    }
                                    android.util.Log.d("MainActivity", "FloatingService started successfully")
                                    result.success(true)
                                } catch (e: Exception) {
                                    android.util.Log.e("MainActivity", "Failed to start FloatingService", e)
                                    result.error("SERVICE_START_FAILED", "Failed to start service: ${e.message}", null)
                                }
                            } else {
                                android.util.Log.e("MainActivity", "Invalid arguments: customerId=$customerId, orderId=$orderId")
                                result.error("INVALID_ARGS", "customerId and orderId are required", null)
                            }
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "Error in setAcceptedOrder handler", e)
                            result.error("UNKNOWN_ERROR", "Unexpected error: ${e.message}", null)
                        }
                    }

                    "setHasNewOrder" -> {
                        try {
                            val hasNewOrder = call.argument<Boolean>("hasNewOrder") ?: false
                            android.util.Log.d("MainActivity", "setHasNewOrder CALLED from Flutter hasNewOrder=$hasNewOrder")

                            // Ping the service; it will update the bubble UI if it's running.
                            val intent = Intent(this, FloatingService::class.java).apply {
                                putExtra("hasNewOrder", hasNewOrder)
                            }

                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "Error in setHasNewOrder handler", e)
                            result.error("UNKNOWN_ERROR", "Unexpected error: ${e.message}", null)
                        }
                    }

                    "setNewOrderOverlayData" -> {
                        try {
                            val intent = Intent(this, FloatingService::class.java).apply {
                                putExtra("overlayCustomerId", call.argument<String>("customerId"))
                                putExtra("overlayOrderId", call.argument<String>("orderId"))
                                putExtra("overlayItemText", call.argument<String>("itemText"))
                                putExtra("overlayPickupText", call.argument<String>("pickupText"))
                                putExtra("overlayDropText", call.argument<String>("dropText"))
                                putExtra("overlayShowAccept", call.argument<Boolean>("showAccept") ?: true)
                                putExtra("overlayMode", call.argument<String>("mode") ?: "driver")
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "Error in setNewOrderOverlayData handler", e)
                            result.error("UNKNOWN_ERROR", "Unexpected error: ${e.message}", null)
                        }
                    }

                    "setAppInForeground" -> {
                        try {
                            val inForeground = call.argument<Boolean>("inForeground") ?: true
                            android.util.Log.d("MainActivity", "setAppInForeground CALLED inForeground=$inForeground")
                            val intent = Intent(this, FloatingService::class.java).apply {
                                putExtra("appInForeground", inForeground)
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "Error in setAppInForeground handler", e)
                            result.error("UNKNOWN_ERROR", "Unexpected error: ${e.message}", null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}