package com.quick.quick_run_driver

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.res.Resources
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.os.Handler
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.*
import android.widget.ImageView
import android.widget.TextView
import android.media.MediaPlayer
import android.media.AudioAttributes
import android.media.AudioManager
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.quick.quick_run_driver.R
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.Priority
import java.io.File
import org.json.JSONObject

class FloatingService : Service() {
    
    private fun logDebug(location: String, message: String, data: Map<String, Any?>, hypothesisId: String) {
        try {
            // Log to Android Log only for now to avoid potential file I/O issues during high frequency updates
            Log.d("FloatingService", "[$hypothesisId] $location: $message - ${data.toString()}")
        } catch (e: Exception) {
            Log.e("FloatingService", "Failed to log debug: ${e.message}", e)
        }
    }

    private var windowManager: WindowManager? = null
    private var bubbleView: View? = null
    private var bubbleIconView: ImageView? = null
    private var bubbleNewOrderTextView: TextView? = null
    private var orderOverlayView: View? = null
    private var params: WindowManager.LayoutParams? = null
    private var overlayParams: WindowManager.LayoutParams? = null
    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    private var cachedDriverAuthId: String? = null
    private var isServiceInitialized = false
    private var hasNewOrderIndicator: Boolean = false
    private var appInForeground: Boolean = false
    private var overlayCustomerId: String? = null
    private var overlayOrderId: String? = null
    private var overlayItemText: String? = null
    private var overlayPickupText: String? = null
    private var overlayDropText: String? = null
    private var overlayShowAccept: Boolean = true
    private var overlayMode: String = "driver" // "driver" | "seller"
    private var wakeLock: PowerManager.WakeLock? = null
    private var orderSoundPlayer: MediaPlayer? = null
    private var orderSoundPlaysRemaining: Int = 0
    private var audioFocusRequest: AudioManager.OnAudioFocusChangeListener? = null
    private var lastBellOrderId: String? = null
    private var lastBellAtMs: Long = 0L
    
    // Order tracking variables
    private var currentCustomerId: String? = null
    private var currentOrderId: String? = null
    private var driverDocId: String? = null
    private var isEatDriver: Boolean = false
    private var isFetchingDriverId = false
    private val handler = Handler(Looper.getMainLooper())
    private var locationUpdateRunnable: Runnable? = null
    private var driverDetailsUpdateRunnable: Runnable? = null
    private var lastKnownLat: Double? = null
    private var lastKnownLng: Double? = null
    private var lastWrittenLat: Double? = null
    private var lastWrittenLng: Double? = null
    private var enableLocationTracking: Boolean = true

    override fun onCreate() {
        super.onCreate()
        try {
            Log.d("FloatingService", "onCreate() called")
            
            // 1. MUST start foreground notification IMMEDIATELY for Android 14+ (API 34)
            startForegroundServiceNotification()

            if (FirebaseApp.getApps(this).isEmpty()) {
                FirebaseApp.initializeApp(this)
            }

            val sharedPref = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            cachedDriverAuthId = sharedPref.getString("flutter.driverAuthID", null) 
                ?: sharedPref.getString("flutter.user_phone", null)
            isEatDriver = sharedPref.getBoolean("flutter.isEatDriver", false)
            Log.d("FloatingService", "Cached driverAuthId = $cachedDriverAuthId, isEatDriver = $isEatDriver")

            val userType = sharedPref.getString("flutter.userType", null)
            // Sellers should NOT track/write location. This service is used only for overlay + sound.
            enableLocationTracking = userType != "seller"
            Log.d("FloatingService", "userType=$userType enableLocationTracking=$enableLocationTracking")
            
            // Check if there's a previously accepted order
            val savedCustomerId = sharedPref.getString("flutter.acceptedOrderCustomerId", null)
            val savedOrderId = sharedPref.getString("flutter.acceptedOrderId", null)
            if (savedCustomerId != null && savedOrderId != null) {
                currentCustomerId = savedCustomerId
                currentOrderId = savedOrderId
                Log.d("FloatingService", "Restored accepted order: customerId=$savedCustomerId, orderId=$savedOrderId")
            }
            
            if (enableLocationTracking) {
                fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
                // Fetch driver doc ID once on service start
                fetchDriverDocId()
            }
            
            showFloatingBubble()
            
            isServiceInitialized = true
            Log.d("FloatingService", "Service initialized successfully")
        } catch (e: Exception) {
            Log.e("FloatingService", "Error in onCreate()", e)
            isServiceInitialized = false
        }
    }

    private fun showFloatingBubble() {
        // Don't show bubble if it's already displayed
        if (bubbleView != null && windowManager != null) {
            Log.d("FloatingService", "Bubble already displayed, skipping")
            startLocationTracking()
            return
        }
        
        // Check if we have permission to draw over other apps
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(this)) {
                Log.w("FloatingService", "SYSTEM_ALERT_WINDOW permission not granted. Skipping floating bubble display.")
                // Still start location tracking even without the bubble
                startLocationTracking()
                return
            }
        }

        try {
            windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

            bubbleView = LayoutInflater.from(this).inflate(R.layout.bubble_layout, null)

            val bubble = bubbleView!!.findViewById<ImageView>(R.id.bubbleIcon)
            bubbleIconView = bubble
            bubbleNewOrderTextView = bubbleView!!.findViewById(R.id.bubbleNewOrderText)

            val overlayType =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else
                    WindowManager.LayoutParams.TYPE_PHONE

            params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                overlayType,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
            )

            params!!.gravity = Gravity.TOP or Gravity.START
            params!!.x = 0
            params!!.y = 200

            windowManager!!.addView(bubbleView, params)

            bubble.setOnTouchListener(FloatingTouchListener())
            // Ensure bubble state reflects latest known indicator flag
            updateBubbleNewOrderIndicator(hasNewOrderIndicator)
            Log.d("FloatingService", "Floating bubble displayed successfully")
        } catch (e: Exception) {
            Log.e("FloatingService", "Failed to show floating bubble", e)
            e.printStackTrace()
            // Clear references if bubble creation failed
            bubbleView = null
            bubbleIconView = null
            bubbleNewOrderTextView = null
            windowManager = null
            params = null
            // Continue with location tracking even if bubble fails
        }

        // Start location tracking with appropriate interval based on order status
        if (enableLocationTracking) {
            startLocationTracking()
        }
    }

    private fun showOrderOverlayIfNeeded() {
        if (orderOverlayView != null && windowManager != null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(this)) return
        }

        try {
            if (windowManager == null) {
                windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            }

            val overlayType =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else
                    WindowManager.LayoutParams.TYPE_PHONE

            overlayParams = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                overlayType,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                PixelFormat.TRANSLUCENT
            )

            overlayParams!!.gravity = Gravity.TOP
            overlayParams!!.x = 0
            overlayParams!!.y = 120

            orderOverlayView = LayoutInflater.from(this).inflate(R.layout.order_overlay, null)
            windowManager!!.addView(orderOverlayView, overlayParams)

            bindOverlayData()
            bindOverlaySwipe()
        } catch (e: Exception) {
            Log.e("FloatingService", "Failed to show order overlay", e)
            orderOverlayView = null
            overlayParams = null
        }
    }

    private fun hideOrderOverlay() {
        try {
            orderOverlayView?.let { view ->
                windowManager?.removeView(view)
            }
        } catch (e: Exception) {
            Log.e("FloatingService", "Failed to hide order overlay", e)
        } finally {
            orderOverlayView = null
            overlayParams = null
        }
    }

    private fun bindOverlayData() {
        val root = orderOverlayView ?: return
        try {
            val orderIdView = root.findViewById<TextView>(R.id.overlayOrderId)
            val itemView = root.findViewById<TextView>(R.id.overlayItem)
            val pickupView = root.findViewById<TextView>(R.id.overlayPickup)
            val dropView = root.findViewById<TextView>(R.id.overlayDrop)
            val swipeContainer = root.findViewById<View>(R.id.overlaySwipeContainer)

            val oid = overlayOrderId ?: ""
            orderIdView.text = if (oid.isNotBlank()) "#$oid" else "#"
            itemView.text = overlayItemText ?: ""
            pickupView.text = overlayPickupText ?: ""
            dropView.text = overlayDropText ?: ""

            swipeContainer?.visibility = if (overlayShowAccept) View.VISIBLE else View.GONE
        } catch (e: Exception) {
            Log.e("FloatingService", "Failed to bind overlay data", e)
        }
    }

    private fun bindOverlaySwipe() {
        val root = orderOverlayView ?: return
        if (!overlayShowAccept) {
            // Info-only overlay (seller): tapping the card dismisses it.
            root.setOnClickListener { updateNewOrderOverlayVisible(false) }
            return
        }
        val swipeContainer = root.findViewById<View>(R.id.overlaySwipeContainer)
        val handle = root.findViewById<View>(R.id.overlaySwipeHandle)
        if (swipeContainer == null || handle == null) return

        handle.setOnTouchListener(object : View.OnTouchListener {
            private var startX = 0f
            private var origX = 0f
            override fun onTouch(v: View, event: MotionEvent): Boolean {
                val containerWidth = swipeContainer.width.toFloat()
                val handleWidth = handle.width.toFloat()
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        startX = event.rawX
                        origX = handle.x
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - startX
                        val next = (origX + dx).coerceIn(0f, (containerWidth - handleWidth))
                        handle.x = next
                        return true
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        val threshold = (containerWidth - handleWidth) * 0.7f
                        if (handle.x >= threshold) {
                            // Accept
                            onOverlayAccepted()
                        }
                        // reset handle
                        handle.animate().x(0f).setDuration(200).start()
                        return true
                    }
                }
                return false
            }
        })
    }

    private fun onOverlayAccepted() {
        if (!overlayShowAccept) return
        val cid = overlayCustomerId
        val oid = overlayOrderId
        if (cid.isNullOrBlank() || oid.isNullOrBlank()) {
            Log.w("FloatingService", "Overlay accepted but missing ids cid=$cid oid=$oid")
            return
        }
        try {
            // Store for Flutter to auto-accept after opening
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit()
                .putString("flutter.overlayAcceptCustomerId", cid)
                .putString("flutter.overlayAcceptOrderId", oid)
                .apply()

            // Open the app to MainActivity
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            startActivity(launchIntent)

            // Hide overlay immediately
            updateNewOrderOverlayVisible(false)
        } catch (e: Exception) {
            Log.e("FloatingService", "Failed to handle overlay accept", e)
        }
    }

    private fun updateNewOrderOverlayVisible(show: Boolean) {
        handler.post {
            // Never show overlay/bubble while app is in foreground
            if (appInForeground) {
                hideOrderOverlay()
                bubbleView?.visibility = View.GONE
                return@post
            }
            if (show) {
                // Wake the phone briefly so the driver sees the order even on lock screen
                wakeUpScreenBriefly()
                // Play bell sound 7 times (best-effort while service is running)
                playOrderBell7Times()
                // Hide tiny bubble when showing the full card
                bubbleView?.visibility = View.GONE
                showOrderOverlayIfNeeded()
                bindOverlayData()
            } else {
                hideOrderOverlay()
                bubbleView?.visibility = View.VISIBLE
                stopOrderBell()
            }
        }
    }

    private fun playOrderBell7Times() {
        try {
            // Debounce: don't re-ring the same order immediately
            val now = System.currentTimeMillis()
            val oid = overlayOrderId
            if (!oid.isNullOrBlank() && oid == lastBellOrderId && (now - lastBellAtMs) < 30_000L) {
                return
            }
            lastBellOrderId = oid
            lastBellAtMs = now

            stopOrderBell()
            orderSoundPlaysRemaining = 7

            // Verify raw resource exists (helps debug packaging/install issues)
            try {
                resources.openRawResourceFd(R.raw.order_notification)?.close()
            } catch (e: Exception) {
                Log.e("FloatingService", "order_notification raw resource not found/accessible", e)
                return
            }

            val mp = MediaPlayer()
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    // Use ALARM-ish usage so it is loud/urgent.
                    // Note: DND can still block depending on device settings.
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            val afd = resources.openRawResourceFd(R.raw.order_notification)
            if (afd == null) {
                Log.e("FloatingService", "Failed to open order_notification raw resource fd")
                return
            }
            mp.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            afd.close()
            mp.setVolume(1.0f, 1.0f)
            orderSoundPlayer = mp

            // Request transient audio focus so playback is not muted by other audio
            try {
                val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audioFocusRequest = AudioManager.OnAudioFocusChangeListener { /* no-op */ }
                @Suppress("DEPRECATION")
                am.requestAudioFocus(
                    audioFocusRequest,
                    AudioManager.STREAM_ALARM,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
                )
            } catch (e: Exception) {
                Log.w("FloatingService", "Audio focus request failed (continuing)", e)
            }

            mp.setOnCompletionListener {
                orderSoundPlaysRemaining -= 1
                if (orderSoundPlaysRemaining > 0) {
                    try {
                        it.seekTo(0)
                        it.start()
                    } catch (e: Exception) {
                        Log.e("FloatingService", "Failed repeating bell", e)
                        stopOrderBell()
                    }
                } else {
                    stopOrderBell()
                }
            }
            mp.setOnErrorListener { _, _, _ ->
                stopOrderBell()
                true
            }
            mp.prepare()
            mp.start()
        } catch (e: Exception) {
            Log.e("FloatingService", "Failed to play order bell", e)
        }
    }

    private fun stopOrderBell() {
        try {
            orderSoundPlaysRemaining = 0
            orderSoundPlayer?.let {
                try {
                    if (it.isPlaying) it.stop()
                } catch (_: Exception) {}
                try {
                    it.release()
                } catch (_: Exception) {}
            }
        } finally {
            orderSoundPlayer = null
            try {
                val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                @Suppress("DEPRECATION")
                audioFocusRequest?.let { am.abandonAudioFocus(it) }
            } catch (_: Exception) {}
            audioFocusRequest = null
        }
    }

    private fun wakeUpScreenBriefly() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            // Release any previous lock
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
            @Suppress("DEPRECATION")
            val wl = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                        PowerManager.ACQUIRE_CAUSES_WAKEUP or
                        PowerManager.ON_AFTER_RELEASE,
                "quickrun:NEW_ORDER_WAKE"
            )
            wakeLock = wl
            wl.acquire(6_000L) // 6 seconds is enough to light up and show overlay
        } catch (e: Exception) {
            Log.e("FloatingService", "Failed to wake screen", e)
        }
    }

    private fun updateAppInForeground(inForeground: Boolean) {
        appInForeground = inForeground
        handler.post {
            if (inForeground) {
                // Hide everything while app is open
                hideOrderOverlay()
                bubbleView?.visibility = View.GONE
                // Stop ringing immediately and avoid ringing again when opening app
                stopOrderBell()
                lastBellOrderId = null
                lastBellAtMs = 0L
                hasNewOrderIndicator = false
            } else {
                // App backgrounded: show overlay if there is a new order, else show bubble icon.
                updateNewOrderOverlayVisible(hasNewOrderIndicator)
            }
        }
    }

    private fun updateBubbleNewOrderIndicator(show: Boolean) {
        hasNewOrderIndicator = show
        handler.post {
            try {
                val icon = bubbleIconView
                val txt = bubbleNewOrderTextView
                if (icon == null || txt == null) return@post
                if (show) {
                    icon.visibility = View.GONE
                    txt.visibility = View.VISIBLE
                } else {
                    txt.visibility = View.GONE
                    icon.visibility = View.VISIBLE
                }
            } catch (e: Exception) {
                Log.e("FloatingService", "Failed to update bubble indicator", e)
            }
        }
    }
    
    private fun startLocationTracking() {
        try {
            if (fusedLocationClient == null) {
                Log.e("FloatingService", "FusedLocationClient is null, initializing...")
                fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
            }
            
            // Remove existing location updates if any
            locationCallback?.let { 
                fusedLocationClient?.removeLocationUpdates(it)
            }
        
            // TESTING: Set to 10 seconds to reduce resource usage
            val locationRequest = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 10000)
                .setMinUpdateIntervalMillis(5000)
                .build()
            
            Log.d("FloatingService", "Location tracking started (10s interval)")
            
            // Create location callback
            val newCallback = object : LocationCallback() {
                override fun onLocationResult(locationResult: LocationResult) {
                    val loc = locationResult.lastLocation ?: return
                    val lat = loc.latitude
                    val lng = loc.longitude
                    
                    lastKnownLat = lat
                    lastKnownLng = lng

                    val sharedPref = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    val userType = sharedPref.getString("flutter.userType", null)
                    val bdId = sharedPref.getString("flutter.bdId", null)
                    
                    if (currentCustomerId != null && currentOrderId != null) {
                        updateDriverDetailsLocation(lat, lng)
                    }

                    if (userType == "BD_executive" && bdId != null) {
                        updateBDLocation(lat, lng, bdId)
                    }

                    if (currentCustomerId == null && currentOrderId == null) {
                        if (driverDocId != null) {
                            writeDriverLocationHistory(lat, lng)
                        } else {
                            fetchDriverDocId()
                        }
                    }
                }
            }
            
            fusedLocationClient?.requestLocationUpdates(locationRequest, newCallback, Looper.getMainLooper())
            this.locationCallback = newCallback
            
            if (currentCustomerId != null && currentOrderId != null) {
                fusedLocationClient?.lastLocation?.addOnSuccessListener { location ->
                    if (location != null) {
                        lastKnownLat = location.latitude
                        lastKnownLng = location.longitude
                        updateDriverDetailsLocation(lastKnownLat!!, lastKnownLng!!)
                    }
                }
                startOrderLocationUpdates()
            }
        } catch (e: Exception) {
            Log.e("FloatingService", "Error in startLocationTracking()", e)
        }
    }

    private fun updateBDLocation(lat: Double, lng: Double, bdId: String) {
        val todayDate = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault()).format(java.util.Date())
        val db = FirebaseFirestore.getInstance()
        val entry = hashMapOf(
            "lat" to lat,
            "lng" to lng,
            "timestamp" to FieldValue.serverTimestamp()
        )
        db.collection("bd_profiles").document(bdId)
            .collection("locationActivity").document(todayDate)
            .collection("entries").add(entry)
            .addOnFailureListener { e -> Log.e("FloatingService", "BD location update failed", e) }
    }
    
    // Method to set accepted order information
    fun setAcceptedOrder(customerId: String, orderId: String) {
        try {
            // #region agent log
            logDebug("FloatingService.kt:315", "setAcceptedOrder - entry", mapOf("customerId" to customerId, "orderId" to orderId, "isServiceInitialized" to isServiceInitialized), "D")
            // #endregion
            
            Log.d("FloatingService", "Setting accepted order: customerId=$customerId, orderId=$orderId")
            
            // Ensure service is initialized
            if (!isServiceInitialized) {
                Log.w("FloatingService", "Service not fully initialized, initializing fusedLocationClient...")
                if (fusedLocationClient == null) {
                    fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
                }
                isServiceInitialized = true
            }
            
            currentCustomerId = customerId
            currentOrderId = orderId
            
            // Store in SharedPreferences for persistence
            val sharedPref = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            sharedPref.edit()
                .putString("flutter.acceptedOrderCustomerId", customerId)
                .putString("flutter.acceptedOrderId", orderId)
                .apply()
            
            // Fetch driver doc ID if not already cached
            if (driverDocId == null) {
                fetchDriverDocId()
            }
            
            // Restart location tracking with fast updates (10 seconds) since order is now accepted
            startLocationTracking()
            
            // Start periodic updates for order location
            startOrderLocationUpdates()
            
            // #region agent log
            logDebug("FloatingService.kt:338", "setAcceptedOrder - success", mapOf("customerId" to currentCustomerId, "orderId" to currentOrderId), "D")
            // #endregion
            
            Log.d("FloatingService", "Successfully set accepted order")
        } catch (e: Exception) {
            // #region agent log
            logDebug("FloatingService.kt:340", "setAcceptedOrder - error", mapOf("error" to e.message, "stackTrace" to e.stackTraceToString()), "D")
            // #endregion
            Log.e("FloatingService", "Error in setAcceptedOrder()", e)
            e.printStackTrace()
        }
    }
    
    // Method to clear accepted order (when order is completed)
    fun clearAcceptedOrder() {
        Log.d("FloatingService", "Clearing accepted order")
        currentCustomerId = null
        currentOrderId = null
        
        // Reset last written location to allow fresh writes for next order
        lastWrittenLat = null
        lastWrittenLng = null
        
        // Clear from SharedPreferences
        val sharedPref = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        sharedPref.edit()
            .remove("flutter.acceptedOrderCustomerId")
            .remove("flutter.acceptedOrderId")
            .apply()
        
        // Stop order location updates
        stopOrderLocationUpdates()
        
        // Restart location tracking with slow updates (15 minutes)
        startLocationTracking()
    }
    
    private fun fetchDriverDocId() {
        if (isFetchingDriverId || cachedDriverAuthId == null) return
        
        isFetchingDriverId = true
        val driverAuthId = cachedDriverAuthId!!
        val db = FirebaseFirestore.getInstance()
        
        Log.d("FloatingService", "Fetching driver ID for $driverAuthId")
        
        // Try 'drivers' collection first (new eat app)
        db.collection("drivers")
            .document(driverAuthId)
            .get()
            .addOnSuccessListener { doc ->
                if (doc.exists()) {
                    driverDocId = driverAuthId // For 'drivers' collection, docId is phone number
                    isEatDriver = true
                    
                    // Persist this info for when app is killed/restarted
                    val sharedPref = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    sharedPref.edit().putBoolean("flutter.isEatDriver", true).apply()
                    
                    Log.d("FloatingService", "Eat Driver detected: $driverDocId")
                    isFetchingDriverId = false
                } else {
                    // Fallback to 'QuickRunDrivers' collection (old porter app)
                    db.collection("QuickRunDrivers")
                        .whereEqualTo("phone", driverAuthId)
                        .limit(1)
                        .get()
                        .addOnSuccessListener { result ->
                            if (!result.isEmpty) {
                                driverDocId = result.documents[0].id
                                isEatDriver = false
                                
                                val sharedPref = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                                sharedPref.edit().putBoolean("flutter.isEatDriver", false).apply()
                                
                                Log.d("FloatingService", "Porter Driver Doc ID cached: $driverDocId")
                            }
                            isFetchingDriverId = false
                        }
                        .addOnFailureListener {
                            isFetchingDriverId = false
                        }
                }
            }
            .addOnFailureListener { e ->
                Log.e("FloatingService", "Error fetching driver document", e)
                isFetchingDriverId = false
            }
    }
    
    private fun startOrderLocationUpdates() {
        // Stop existing updates
        stopOrderLocationUpdates()
        
        Log.d("FloatingService", "Starting periodic order location updates")
        
        // Ensure driverDocId is available for active order updates
        if (driverDocId == null) {
            fetchDriverDocId()
        }
        
        // Update acceptedDriverDetails.driverLatLng every 10 seconds
        locationUpdateRunnable = object : Runnable {
            override fun run() {
                // #region agent log
                logDebug("FloatingService.kt:392", "Periodic update - run", mapOf("hasCustomerId" to (currentCustomerId != null), "hasOrderId" to (currentOrderId != null), "hasLat" to (lastKnownLat != null), "hasLng" to (lastKnownLng != null)), "E")
                // #endregion
                
                if (currentCustomerId != null && currentOrderId != null && 
                    lastKnownLat != null && lastKnownLng != null) {
                    Log.d("FloatingService", "Periodic update: acceptedDriverDetails.driverLatLng")
                    updateDriverDetailsLocation(lastKnownLat!!, lastKnownLng!!)
                } else {
                    Log.w("FloatingService", "Skipping periodic update - missing data")
                }
                handler.postDelayed(this, 10000) // 10 seconds to reduce resource usage
            }
        }
        handler.post(locationUpdateRunnable!!)
        
        // #region agent log
        logDebug("FloatingService.kt:403", "Periodic updates started", mapOf("runnablePosted" to true), "E")
        // #endregion
        
        // Remove the second runnable since we're only using one update method now
        driverDetailsUpdateRunnable = null
    }
    
    private fun stopOrderLocationUpdates() {
        locationUpdateRunnable?.let { handler.removeCallbacks(it) }
        driverDetailsUpdateRunnable?.let { handler.removeCallbacks(it) }
        locationUpdateRunnable = null
        driverDetailsUpdateRunnable = null
    }
    
    private fun updateDriverDetailsLocation(lat: Double, lng: Double) {
        val cid = currentCustomerId
        val oid = currentOrderId
        
        if (cid == null || oid == null) {
            Log.w("FloatingService", "Skipping driver details update: customerId or orderId is null")
            return
        }
        
        val db = FirebaseFirestore.getInstance()
        val collectionName = if (isEatDriver) "Customers" else "Customer"
        val subCollectionName = if (isEatDriver) "currentOrder" else "current_order"
        
        val orderRef = db.collection(collectionName)
            .document(cid)
            .collection(subCollectionName)
            .document(oid)
        
        val updateData = mapOf(
            "acceptedDriverDetails.driverLatLng" to mapOf(
                "lat" to lat,
                "lng" to lng,
                "timestamp" to FieldValue.serverTimestamp()
            ),
            "driverLatLng" to FieldValue.delete(),
            "driverDetails" to FieldValue.delete() // Remove the old field
        )
        
        Log.d("FloatingService", "Updating location at $collectionName/$cid/$subCollectionName/$oid")
        orderRef.update(updateData)
            .addOnSuccessListener {
                Log.d("FloatingService", "✓ Driver details updated successfully")
            }
            .addOnFailureListener { e ->
                Log.e("FloatingService", "✗ Failed to update driver details: ${e.message}")
            }
    }
    
    /**
     * Updates driver location in the main document.
     * Called from background/bubble tracking flow every 5 seconds.
     */
    /**
     * Updates driver location in the main document.
     * Called from background/bubble tracking flow every 5 seconds.
     */
    private fun writeDriverLocationHistory(lat: Double, lng: Double) {
        if (driverDocId == null) {
            fetchDriverDocId()
            return
        }
        
        val db = FirebaseFirestore.getInstance()
        val collectionName = if (isEatDriver) "drivers" else "QuickRunDrivers"
        
        // Update main document only
        val updateData = hashMapOf(
            "lat" to lat,
            "lng" to lng,
            "lastUpdated" to FieldValue.serverTimestamp(),
            "trackingState" to "background"
        )

        db.collection(collectionName)
            .document(driverDocId!!)
            .update(updateData as Map<String, Any>)
            .addOnSuccessListener {
                lastWrittenLat = lat
                lastWrittenLng = lng
                Log.d("FloatingService", "Location updated in main doc: $driverDocId in $collectionName")
            }
            .addOnFailureListener { e ->
                Log.e("FloatingService", "Failed to update main doc in $collectionName", e)
            }
    }

    inner class FloatingTouchListener : View.OnTouchListener {

        private var initialX = 0
        private var initialY = 0
        private var touchX = 0f
        private var touchY = 0f

        override fun onTouch(view: View, event: MotionEvent): Boolean {
            val currentParams = params ?: return false
            val currentWindowManager = windowManager ?: return false
            val currentBubbleView = bubbleView ?: return false
            
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = currentParams.x
                    initialY = currentParams.y
                    touchX = event.rawX
                    touchY = event.rawY
                    return true
                }

                MotionEvent.ACTION_MOVE -> {
                    currentParams.x = initialX + (event.rawX - touchX).toInt()
                    currentParams.y = initialY + (event.rawY - touchY).toInt()
                    currentWindowManager.updateViewLayout(currentBubbleView, currentParams)
                    return true
                }

                MotionEvent.ACTION_UP -> {
                    val middle = Resources.getSystem().displayMetrics.widthPixels / 2
                    currentParams.x = if (currentParams.x >= middle) Resources.getSystem().displayMetrics.widthPixels - currentBubbleView.width else 0
                    currentWindowManager.updateViewLayout(currentBubbleView, currentParams)
                    return true
                }
            }
            return false
        }
    }

    private fun startForegroundServiceNotification() {
        val channelId = "bubble_service_channel"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Floating Bubble",
                NotificationManager.IMPORTANCE_LOW
            )

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("You are online")
            .setContentText("We will update you for you orders")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(1, notification)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            stopOrderLocationUpdates()
            locationCallback?.let { 
                fusedLocationClient?.removeLocationUpdates(it)
            }
            // Remove bubble view if it was created
            bubbleView?.let { view ->
                windowManager?.removeView(view)
            }
            // Remove order overlay if present
            hideOrderOverlay()
            stopOrderBell()
            try {
                wakeLock?.let { if (it.isHeld) it.release() }
            } catch (_: Exception) {}
            isServiceInitialized = false
            Log.d("FloatingService", "Service destroyed")
        } catch (e: Exception) {
            Log.e("FloatingService", "Error in onDestroy()", e)
        }
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            Log.d("FloatingService", "onStartCommand() called")
            
            // Ensure foreground state is maintained on every start command
            startForegroundServiceNotification()
            
            // Toggle bubble indicator for new orders (sent from Flutter)
            intent?.let {
                if (it.hasExtra("appInForeground")) {
                    val fg = it.getBooleanExtra("appInForeground", false)
                    Log.d("FloatingService", "Received appInForeground=$fg")
                    updateAppInForeground(fg)
                }
                if (it.hasExtra("hasNewOrder")) {
                    val hasNewOrder = it.getBooleanExtra("hasNewOrder", false)
                    Log.d("FloatingService", "Received hasNewOrder=$hasNewOrder")
                    hasNewOrderIndicator = hasNewOrder
                    // show full overlay card instead of tiny red bubble
                    updateNewOrderOverlayVisible(hasNewOrder)
                }
                // Update overlay payload (sent from Flutter)
                if (it.hasExtra("overlayCustomerId") || it.hasExtra("overlayOrderId")) {
                    overlayCustomerId = it.getStringExtra("overlayCustomerId")
                    overlayOrderId = it.getStringExtra("overlayOrderId")
                    overlayItemText = it.getStringExtra("overlayItemText")
                    overlayPickupText = it.getStringExtra("overlayPickupText")
                    overlayDropText = it.getStringExtra("overlayDropText")
                    if (it.hasExtra("overlayShowAccept")) {
                        overlayShowAccept = it.getBooleanExtra("overlayShowAccept", true)
                    }
                    if (it.hasExtra("overlayMode")) {
                        overlayMode = it.getStringExtra("overlayMode") ?: overlayMode
                    }
                    bindOverlayData()
                }
            }

            // Handle order info from intent or SharedPreferences
            intent?.let {
                val customerId = it.getStringExtra("customerId")
                val orderId = it.getStringExtra("orderId")
                if (customerId != null && orderId != null) {
                    Log.d("FloatingService", "Received order from intent: customerId=$customerId, orderId=$orderId")
                    setAcceptedOrder(customerId, orderId)
                }
            }
            
            // Also check SharedPreferences for order info (in case service was already running)
            val sharedPref = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val customerId = sharedPref.getString("flutter.acceptedOrderCustomerId", null)
            val orderId = sharedPref.getString("flutter.acceptedOrderId", null)
            if (customerId != null && orderId != null && 
                (currentCustomerId != customerId || currentOrderId != orderId)) {
                Log.d("FloatingService", "Found order in SharedPreferences: customerId=$customerId, orderId=$orderId")
                setAcceptedOrder(customerId, orderId)
            }
        } catch (e: Exception) {
            Log.e("FloatingService", "Error in onStartCommand()", e)
            e.printStackTrace()
        }
        
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null
}