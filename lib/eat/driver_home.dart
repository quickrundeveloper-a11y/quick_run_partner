import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:slide_to_confirm/slide_to_confirm.dart';
import 'eat_login.dart';

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> with WidgetsBindingObserver {
  static const _bubbleChannel = MethodChannel('floating.chat.head');
  
  bool _isOnline = false;
  Position? _currentPos;
  StreamSubscription<Position>? _posSub;
  StreamSubscription? _ordersSub;
  StreamSubscription? _activeOrderSub;
  List<DocumentSnapshot> _placedOrders = [];
  String? _activeOrderId;
  String? _activeCustomerId;
  String? _userName;
  String? _userPhone;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDriverData();
    _setAppInForeground(true);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _ordersSub?.cancel();
    _activeOrderSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setAppInForeground(true);
    } else {
      _setAppInForeground(false);
    }
  }

  Future<void> _setAppInForeground(bool inForeground) async {
    try {
      await _bubbleChannel.invokeMethod('setAppInForeground', {'inForeground': inForeground});
    } catch (e) {
      debugPrint('⚠️ Failed to set foreground state: $e');
    }
  }

  Future<void> _initDriverData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? 'Driver';
      _userPhone = prefs.getString('user_phone');
      _isOnline = prefs.getBool('driver_is_online') ?? false;
      _activeOrderId = prefs.getString('active_order_id');
      _activeCustomerId = prefs.getString('active_customer_id');
      _isLoading = false;
    });

    if (_isOnline) {
      _toggleOnline(true);
    }

    if (_activeOrderId != null) {
      _listenToActiveOrder();
    }
  }

  void _listenToActiveOrder() {
    _activeOrderSub?.cancel();
    if (_activeOrderId == null || _activeCustomerId == null) return;

    debugPrint("🔍 Listening to active order: $_activeOrderId");
    _activeOrderSub = FirebaseFirestore.instance
        .collection('Customers')
        .doc(_activeCustomerId)
        .collection('currentOrder')
        .doc(_activeOrderId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) {
        debugPrint("🔍 Active order document deleted from Firestore");
        _clearActiveOrderLocally();
        return;
      }

      final data = snap.data() as Map<String, dynamic>;
      final status = data['status'];
      debugPrint("🔍 Active order status update: $status");

      // If status is no longer one of the active delivery states, clear it locally
      if (status == 'placed' || status == 'delivered' || status == 'cancelled' || status == 'rejected') {
        debugPrint("🔍 Order is no longer active for driver, clearing local state");
        _clearActiveOrderLocally();
      }
    });
  }

  Future<void> _clearActiveOrderLocally() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_order_id');
    await prefs.remove('active_customer_id');
    
    _activeOrderSub?.cancel();
    
    if (mounted) {
      setState(() {
        _activeOrderId = null;
        _activeCustomerId = null;
      });
      _listenForOrders(); // Restart new order requests listener
    }
  }

  bool _hasListenerTriggered = false;

  void _listenForOrders() {
    _ordersSub?.cancel();
    if (!_isOnline || _activeOrderId != null) {
      debugPrint("🔍 Listener skipped: isOnline=$_isOnline, activeOrder=$_activeOrderId");
      return;
    }

    debugPrint("🔍 Starting order listener for collectionGroup 'currentOrder'...");
    _ordersSub = FirebaseFirestore.instance
        .collectionGroup('currentOrder')
        .limit(20) // Safety limit to prevent memory exhaustion (OOM)
        .snapshots()
        .listen((snap) {
      _hasListenerTriggered = true;
      debugPrint("🔍 Received snapshot with ${snap.docs.length} total orders");
      final placed = snap.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['status'] == 'placed';
      }).toList();
      
      debugPrint("🔍 Filtered to ${placed.length} 'placed' orders");
      if (mounted) {
        setState(() {
          _placedOrders = placed;
        });
      }
    }, onError: (e) {
      debugPrint("❌ Firestore listener error: $e");
    });
  }

  Future<void> _toggleOnline(bool online) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('driver_is_online', online);
    
    setState(() => _isOnline = online);

    if (online) {
      _startTracking();
      _listenForOrders();
      try {
        await _bubbleChannel.invokeMethod('startBubble');
      } catch (e) {
        debugPrint('❌ Error starting bubble: $e');
      }
    } else {
      _stopTracking();
      _ordersSub?.cancel();
      setState(() => _placedOrders = []);
      try {
        await _bubbleChannel.invokeMethod('stopBubble');
      } catch (e) {
        debugPrint('❌ Error stopping bubble: $e');
      }
    }

    // Update Firestore online status
    if (_userPhone != null) {
      FirebaseFirestore.instance
          .collection('drivers')
          .doc(_userPhone)
          .update({'isOnline': online});
    }
  }

  String? _acceptingOrderId;

  Future<void> _acceptOrder(DocumentSnapshot orderDoc) async {
    if (_userPhone == null) {
      debugPrint("❌ Cannot accept: userPhone is null");
      return;
    }
    
    final orderId = orderDoc.id;
    final customerId = orderDoc.reference.parent.parent?.id;
    
    debugPrint("🚀 Attempting to accept order: $orderId for customer: $customerId");
    if (customerId == null) {
      debugPrint("❌ Cannot accept: customerId not found in path");
      return;
    }

    // Set loading state for this specific order
    setState(() => _acceptingOrderId = orderId);

    try {
      // 0. Ensure location is available
      Position? currentPos = _currentPos;
      if (currentPos == null) {
        debugPrint("🔍 Current position is null, fetching fresh position...");
        currentPos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      }

      // 1. Get Driver Details with timeout
      final driverSnap = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(_userPhone)
          .get()
          .timeout(const Duration(seconds: 10));

      if (!driverSnap.exists) {
        throw 'Driver profile not found. Please complete your registration.';
      }
      
      final driverData = driverSnap.data() as Map<String, dynamic>;

      // 2. Update Order Status with timeout
      await orderDoc.reference.update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'driverDetails': FieldValue.delete(), // Remove the old field
        'acceptedDriverDetails': {
          'name': driverData['name'] ?? 'Driver',
          'phone': _userPhone,
          'vehicleNumber': driverData['vehicleNumber'] ?? '',
          'vehicleType': driverData['vehicleType'] ?? '',
          'driverLatLng': {
            'lat': currentPos.latitude,
            'lng': currentPos.longitude,
            'timestamp': FieldValue.serverTimestamp(),
          },
        }
      }).timeout(const Duration(seconds: 15));

      debugPrint("✅ Firestore updated: status=accepted");

      // 3. Persist locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_order_id', orderId);
      await prefs.setString('active_customer_id', customerId);

      // 4. Update Native Service (wrapped in try-catch)
      try {
        await _bubbleChannel.invokeMethod('setAcceptedOrder', {
          'customerId': customerId,
          'orderId': orderId,
        }).timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('⚠️ Native service warning: $e');
      }

      // 5. Success UI Update
      if (mounted) {
        setState(() {
          _activeOrderId = orderId;
          _activeCustomerId = customerId;
          _placedOrders = []; // Clear pending requests
          _acceptingOrderId = null;
        });
      }
      
      _listenToActiveOrder(); // Start listening to status changes for the new active order
      _ordersSub?.cancel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order accepted successfully!')));
      }
      
    } catch (e) {
      debugPrint('❌ Error in _acceptOrder: $e');
      if (mounted) {
        setState(() => _acceptingOrderId = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _completeOrder() async {
    if (_activeCustomerId == null || _activeOrderId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('Customers')
          .doc(_activeCustomerId)
          .collection('currentOrder')
          .doc(_activeOrderId)
          .update({'status': 'delivered', 'completedAt': FieldValue.serverTimestamp()});

      // Note: _clearActiveOrderLocally() will be called automatically by the active order listener
      // once it sees the status change to 'delivered'.
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order completed!')));
    } catch (e) {
      debugPrint('❌ Error completing order: $e');
    }
  }

  void _startTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      _posSub?.cancel();
      _posSub = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          intervalDuration: const Duration(seconds: 10),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationText: "QuickRun is tracking your location for testing",
            notificationTitle: "Test Mode Active",
            enableWakeLock: true,
          ),
        ),
      ).listen((Position pos) {
        setState(() => _currentPos = pos);
        _updateLocationInFirestore(pos);
      });
    }
  }

  void _stopTracking() {
    _posSub?.cancel();
    _posSub = null;
  }

  Future<void> _updateLocationInFirestore(Position pos) async {
    if (_userPhone == null) return;

    try {
      // Update current location in the main document
      await FirebaseFirestore.instance.collection('drivers').doc(_userPhone).update({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'lastUpdated': FieldValue.serverTimestamp(),
        'trackingState': 'foreground',
      });

      // Update active order location if exists
      if (_activeCustomerId != null && _activeOrderId != null) {
        await FirebaseFirestore.instance
            .collection('Customers')
            .doc(_activeCustomerId)
            .collection('currentOrder')
            .doc(_activeOrderId)
            .update({
          'acceptedDriverDetails.driverLatLng': {
            'lat': pos.latitude,
            'lng': pos.longitude,
            'timestamp': FieldValue.serverTimestamp(),
          },
        });
      }
    } catch (e) {
      debugPrint('❌ Error updating location: $e');
    }
  }

  Future<void> _logout(BuildContext context) async {
    await _toggleOnline(false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      debugPrint('✅ Logout successful');
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const EatLoginPage()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('❌ Logout failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text('QuickRun Eat', style: GoogleFonts.kronaOne(fontSize: 18, color: Colors.black)),
        actions: [
          Switch(
            value: _isOnline,
            activeColor: Colors.green,
            onChanged: (val) => _toggleOnline(val),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Driver Profile Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: _isOnline ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                    child: Icon(Icons.person, size: 30, color: _isOnline ? Colors.green : Colors.grey),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_userName',
                          style: GoogleFonts.kumbhSans(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _isOnline ? 'Online' : 'Offline',
                          style: GoogleFonts.kumbhSans(
                            color: _isOnline ? Colors.green : Colors.red,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Lat: ${_currentPos?.latitude.toString() ?? '--'}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                      Text('Lng: ${_currentPos?.longitude.toString() ?? '--'}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),

            if (_activeOrderId != null) ...[
              Text('ACTIVE ORDER', style: GoogleFonts.kumbhSans(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black54, letterSpacing: 1.2)),
              const SizedBox(height: 12),
              _buildActiveOrderCard(),
            ] else if (!_isOnline) ...[
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    Icon(Icons.cloud_off, size: 64, color: Colors.grey.withOpacity(0.3)),
                    const SizedBox(height: 16),
                    Text(
                      'Go online to receive orders',
                      style: GoogleFonts.kumbhSans(color: Colors.black54, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('NEW REQUESTS', style: GoogleFonts.kumbhSans(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black54, letterSpacing: 1.2)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
                    child: Text('${_placedOrders.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_placedOrders.isEmpty)
                Center(
                  child: Column(
                    children: [
                      const SizedBox(height: 40),
                      if (!_hasListenerTriggered)
                        const CircularProgressIndicator(strokeWidth: 2, color: Colors.black12)
                      else
                        Icon(Icons.search_off, size: 48, color: Colors.grey.withOpacity(0.3)),
                      const SizedBox(height: 16),
                      Text(
                        _hasListenerTriggered ? 'No orders nearby at the moment' : 'Searching for orders nearby...',
                        style: GoogleFonts.kumbhSans(color: Colors.black38),
                      ),
                    ],
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _placedOrders.length,
                  itemBuilder: (context, index) => _buildOrderCard(_placedOrders[index]),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final items = data['items'] as List? ?? [];
    final address = data['address'] as Map? ?? {};
    final isAccepting = _acceptingOrderId == doc.id;
    
    // Extract payment method safely
    String paymentMethod = 'COD';
    if (data['payment'] is Map && data['payment']['gateway'] is Map) {
      paymentMethod = (data['payment']['gateway']['method'] ?? 'COD').toString().toUpperCase();
    } else if (data['payment'] is Map && data['payment']['gateway'] is String) {
      paymentMethod = data['payment']['gateway'].toString().toUpperCase();
    }

    return Container(
      key: ValueKey('order_${doc.id}'), // Use unique key to reset slider on state changes
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Order #${doc.id.substring(doc.id.length - 6)}', style: GoogleFonts.kumbhSans(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('₹${data['toPay']}', style: GoogleFonts.kumbhSans(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
            ],
          ),
          const Divider(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on, color: Colors.redAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${address['line'] ?? address['address'] ?? 'No address provided'}',
                  style: GoogleFonts.kumbhSans(fontSize: 14, color: Colors.black87),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Items List
          Column(
            children: items.map((item) {
              final i = item as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.fiber_manual_record, size: 8, color: Colors.black38),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${i['title'] ?? 'Unknown Item'} x ${i['quantity'] ?? 1}',
                        style: GoogleFonts.kumbhSans(fontSize: 13, color: Colors.black54),
                      ),
                    ),
                    Text(
                      '₹${(i['basePrice'] ?? 0) * (i['quantity'] ?? 1)}',
                      style: GoogleFonts.kumbhSans(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.payment, color: Colors.black54, size: 18),
              const SizedBox(width: 8),
              Text(
                'Payment: $paymentMethod',
                style: GoogleFonts.kumbhSans(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          if (isAccepting)
            Container(
              height: 56,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                ),
              ),
            )
          else
            Dismissible(
              key: ValueKey('dismiss_${doc.id}'),
              direction: DismissDirection.startToEnd,
              confirmDismiss: (direction) async {
                _acceptOrder(doc);
                return false; // Don't let it dismiss naturally, our state change will remove it
              },
              background: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 20),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.check, color: Colors.white),
              ),
              child: Container(
                height: 56,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Container(
                      height: 40,
                      width: 40,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.chevron_right, color: Colors.black),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          "Swipe to Accept",
                          style: GoogleFonts.kumbhSans(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 48), // Balance for the icon
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActiveOrderCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Customers')
          .doc(_activeCustomerId)
          .collection('currentOrder')
          .doc(_activeOrderId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final data = snapshot.data!.data() as Map<String, dynamic>;
        final items = data['items'] as List? ?? [];
        final address = data['address'] as Map? ?? {};
        final customerName = data['name'] ?? address['name'] ?? 'Customer';

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DELIVER TO', style: GoogleFonts.kumbhSans(color: Colors.white54, fontSize: 10, letterSpacing: 1.1)),
                      Text('$customerName', style: GoogleFonts.kumbhSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.call, color: Colors.white, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${address['line'] ?? address['address']}',
                      style: GoogleFonts.kumbhSans(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white10),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Bill Amount', style: GoogleFonts.kumbhSans(color: Colors.white54, fontSize: 14)),
                  Text('₹${data['toPay']}', style: GoogleFonts.kumbhSans(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _completeOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Complete Delivery', style: GoogleFonts.kumbhSans(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLocationCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.kumbhSans(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.kumbhSans(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
        ],
      ),
    );
  }
}
