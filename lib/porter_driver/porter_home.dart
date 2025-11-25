import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quick_run_driver/notifications/pending_order.dart';
import 'order_delivery.dart'; // Import for OrderDelivery
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'order_tracking.dart';


class PorterHome extends StatefulWidget {
  final String driverAuthId;
  const PorterHome(this.driverAuthId, {super.key});

  @override
  State<PorterHome> createState() => _PorterHomeState();
}

class _PorterHomeState extends State<PorterHome> with WidgetsBindingObserver {
  // --- Driver identity (TODO: wire to your auth/user profile) ---
  String _driverName = 'Driver';
  String _driverPhone = '0000000000';
  String? _driverId;
  
  // Helper method to write debug logs
  Future<void> _writeDebugLog(String location, String message, Map<String, dynamic> data, String hypothesisId) async {
    try {
      final logEntry = jsonEncode({
        'location': location,
        'message': message,
        'data': data,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'sessionId': 'debug-session',
        'runId': 'run1',
        'hypothesisId': hypothesisId,
      });
      final logFile = File('/Users/akki/Documents/quick_run_driver/.cursor/debug.log');
      await logFile.writeAsString('$logEntry\n', mode: FileMode.append);
    } catch (_) {
      // Silently fail if logging doesn't work
    }
  }

  Position? _myPos;
  StreamSubscription<Position>? _posSub;

  // Single source of truth for Firestore listening:
  // Keep ONE stable listener (no per-customer loops) and derive UI state from it.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersSub;

  // Android floating bubble channel (controls FloatingService bubble UI)
  static const MethodChannel _bubbleChannel = MethodChannel('floating.chat.head');
  bool _lastHasNewOrderSent = false;
  String? _pendingOverlayAcceptCustomerId;
  String? _pendingOverlayAcceptOrderId;

  Future<void> _setAppInForeground(bool inForeground) async {
    try {
      await _bubbleChannel.invokeMethod('setAppInForeground', {'inForeground': inForeground});
    } catch (e) {
      debugPrint('⚠️ Failed to update app foreground state: $e');
    }
  }

  // If orders arrive while app is backgrounded, we defer showing the popup
  // until the app resumes (Flutter cannot show modal UI in background).
  bool _pendingShowPopupOnResume = false;
  bool _isSheetOpen = false;

  // Requests within 10km of driver
  final List<Map<String, dynamic>> _nearbyRequests = [];
  final Set<String> _hiddenRequestIds =
  <String>{}; // locally declined this session

  // Accepted panel state (used by _buildAcceptedPanel)
  bool _showAccepted = false;
  Map<String, dynamic>? _activeReqData;

  // New state for tracking the driver's current assigned order
  Map<String, dynamic>? _currentAssignedOrder;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _assignedOrderSub;

  // Cache for restaurant details to avoid repeated fetches
  final Map<String, Map<String, dynamic>> _restaurantCache = {};

  // --- Utils ---
  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // earth radius in km
    final dLat = (lat2 - lat1) * (pi / 180.0);
    final dLon = (lon2 - lon1) * (pi / 180.0);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180.0)) *
            cos(lat2 * (pi / 180.0)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  Future<void> _ensurePermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location services are disabled. Enable GPS for nearby requests.',
                style: GoogleFonts.lexend()),
          ),
        );
      }
      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location permission permanently denied in settings.',
                style: GoogleFonts.lexend()),
          ),
        );
      }
    } catch (e) {
      debugPrint('Permission error: $e');
    }
  }

  void _startPositionStream() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 25,
    );
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen((
        pos,
        ) {
      setState(() => _myPos = pos);
    }, onError: (e) => debugPrint('Position stream error: $e'));
  }

  // New method to fetch restaurant details
  Future<Map<String, dynamic>?> _fetchRestaurantDetails(String restaurantId) async {
    if (_restaurantCache.containsKey(restaurantId)) {
      return _restaurantCache[restaurantId];
    }
    try {
      final docSnap = await FirebaseFirestore.instance
          .collection('Restaurent_shop')
          .doc(restaurantId)
          .get();

      if (docSnap.exists) {
        final data = docSnap.data() as Map<String, dynamic>;
        // Cache and return the relevant data
        _restaurantCache[restaurantId] = data;
        return data;
      }
    } catch (e) {
      debugPrint('Error fetching restaurant details for $restaurantId: $e');
    }
    return null;
  }

  /// Old behavior (as before): show NEW nearby unaccepted requests + show current accepted order panel.
  ///
  /// Still production-safe:
  /// - ONE stable listener (collectionGroup) to avoid racing per-customer listeners.
  /// - Derive `_nearbyRequests` and `_currentAssignedOrder` from the same snapshot.
  /// - Never clear the accepted order panel on transient empties.
  void _startOrdersListener() {
    _ordersSub?.cancel();

    debugPrint('[ORDERS] Starting unified orders listener (old behavior)');

    _ordersSub = FirebaseFirestore.instance
        .collectionGroup('current_order')
        .snapshots()
        .listen((snap) async {
      debugPrint('[ORDERS] Unified snapshot: docs=${snap.docs.length} changes=${snap.docChanges.length}');

      final nextNearby = <Map<String, dynamic>>[];
      Map<String, dynamic>? nextAssigned;

      for (final doc in snap.docs) {
        final data = doc.data();
        final orderId = doc.id;
        final customerId = doc.reference.parent.parent?.id;
        if (customerId == null) continue;

        // 1) If this order is accepted by THIS driver, it becomes the current panel.
        if (_driverId != null &&
            data['driverId'] == _driverId &&
            data['status'] == 'accepted') {
          nextAssigned = {
            ...data,
            '_id': orderId,
            '_customerId': customerId,
          };
          continue;
        }

        // 2) Otherwise, show it as a "new request" if it's unaccepted and near.
        if (data['acceptedBy'] != null || data['driverId'] != null) continue;
        if (_hiddenRequestIds.contains(orderId)) continue;

        // Distance check (same as old logic)
        double? dKm;
        final pick = data['PickupLatLng'];
        if (_myPos != null &&
            pick is Map &&
            pick['lat'] != null &&
            pick['lng'] != null) {
          dKm = _distanceKm(
            _myPos!.latitude,
            _myPos!.longitude,
            (pick['lat'] as num).toDouble(),
            (pick['lng'] as num).toDouble(),
          );
        }

        // If we can't compute distance yet, keep it (old behavior was permissive).
        // If we can compute, only keep within ~10km.
        if (dKm != null && dKm > 10.0) continue;

        // Best-effort restaurant cache (non-blocking):
        // We keep the UI consistent even if restaurantDetails hasn't loaded yet.
        final restaurantId = data['restaurentAccpetedId'] as String?;
        Map<String, dynamic>? restaurantDetails;
        if (restaurantId != null) {
          restaurantDetails = _restaurantCache[restaurantId];
        }

        nextNearby.add({
          ...data,
          'isGrocery': true,
          '_id': orderId,
          '_customerId': customerId,
          if (dKm != null) '_distanceKm': double.parse(dKm.toStringAsFixed(2)),
          if (restaurantDetails != null) '_restaurantDetails': restaurantDetails,
        });
      }

      // Sort by distance (old behavior)
      nextNearby.sort((a, b) {
        final distA = a['_distanceKm'] as double? ?? double.infinity;
        final distB = b['_distanceKm'] as double? ?? double.infinity;
        return distA.compareTo(distB);
      });

      // Detect meaningful changes to avoid UI thrash.
      final prevAssignedId = _currentAssignedOrder?['_id']?.toString();
      final nextAssignedId = nextAssigned?['_id']?.toString();
      final prevNearbyCount = _nearbyRequests.length;
      final nextNearbyCount = nextNearby.length;

      final shouldUpdate =
          prevAssignedId != nextAssignedId || prevNearbyCount != nextNearbyCount;

      debugPrint('[ORDERS] willUpdate=$shouldUpdate assigned: $prevAssignedId -> $nextAssignedId nearby: $prevNearbyCount -> $nextNearbyCount');
      if (!shouldUpdate) return;
      if (!mounted) return;

      setState(() {
        // Keep accepted order if new snapshot didn't include it (avoid transient wipes).
        if (nextAssigned != null) {
          _currentAssignedOrder = nextAssigned;
        }

        _nearbyRequests
          ..clear()
          ..addAll(nextNearby);
      });

      // Update floating bubble indicator (NEW ORDER text) based on current state
      _syncNewOrderBubbleIndicator();
      // Keep top overlay card content in sync
      _syncNewOrderOverlayData();
      // If driver swiped accept from overlay, auto-accept when order is available
      _maybeAutoAcceptFromOverlay();

      _maybeShowPendingOrderPopup();

      // Trigger old auto-popup behavior (only when no active order)
      if (mounted && _currentAssignedOrder == null && _nearbyRequests.isNotEmpty) {
        debugPrint('[ORDERS] Auto-popup eligible. routeCurrent=${ModalRoute.of(context)?.isCurrent} sheetOpen=$_isSheetOpen');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final isCurrent = ModalRoute.of(context)?.isCurrent == true;
          if (!isCurrent) {
            debugPrint('[ORDERS] Skipping popup now (route not current). Will show on resume.');
            _pendingShowPopupOnResume = true;
            return;
          }
          if (_isSheetOpen) {
            debugPrint('[ORDERS] Skipping popup now (sheet already open).');
            return;
          }
          _showNearbyRequestsBottomSheet();
        });
      }

      // Best-effort: warm restaurant cache asynchronously (does not change logic)
      final idsToFetch = <String>{};
      for (final r in nextNearby) {
        final rid = r['restaurentAccpetedId'];
        if (rid is String && rid.isNotEmpty && !_restaurantCache.containsKey(rid)) {
          idsToFetch.add(rid);
        }
      }
      for (final rid in idsToFetch) {
        // ignore: unawaited_futures
        _fetchRestaurantDetails(rid);
      }
    }, onError: (e) {
      debugPrint('[ORDERS] Unified orders listener error: $e');
    });
  }

  Future<void> _syncNewOrderBubbleIndicator() async {
    // Show NEW ORDER on bubble only when there is no active accepted order and there are nearby requests.
    final hasNewOrder = _currentAssignedOrder == null && _nearbyRequests.isNotEmpty;
    if (hasNewOrder == _lastHasNewOrderSent) return;
    _lastHasNewOrderSent = hasNewOrder;
    try {
      await _bubbleChannel.invokeMethod('setHasNewOrder', {'hasNewOrder': hasNewOrder});
    } catch (e) {
      debugPrint('⚠️ Failed to update bubble new-order indicator: $e');
    }
  }

  Future<void> _syncNewOrderOverlayData() async {
    // Send the first nearby order details for the overlay card.
    if (_currentAssignedOrder != null || _nearbyRequests.isEmpty) return;
    final r = _nearbyRequests.first;
    final customerId = r['_customerId']?.toString();
    final orderId = r['_id']?.toString();
    if (customerId == null || orderId == null) return;

    final items = r['items'];
    String itemText = '';
    if (items is List && items.isNotEmpty) {
      final first = items.first;
      if (first is Map && first['name'] != null) itemText = first['name'].toString();
    } else if (items is Map && items['name'] != null) {
      itemText = items['name'].toString();
    }
    if (itemText.isEmpty) itemText = (r['item'] ?? '').toString();

    // Pickup: prefer restaurant name, else fallback.
    String pickupText = '';
    final restaurantDetails = (r['_restaurantDetails'] is Map)
        ? r['_restaurantDetails'] as Map<String, dynamic>
        : null;
    if (restaurantDetails != null && restaurantDetails['name'] != null) {
      pickupText = 'Pickup: ${restaurantDetails['name']}';
    } else if (r['address'] is Map && (r['address'] as Map)['address'] != null) {
      pickupText = 'Pickup: ${(r['address'] as Map)['address']}';
    } else {
      pickupText = 'Pickup:';
    }

    // Drop
    String dropText = '';
    if (r['address'] is Map && (r['address'] as Map)['address'] != null) {
      dropText = 'Drop: ${(r['address'] as Map)['address']}';
    } else {
      dropText = 'Drop:';
    }

    try {
      await _bubbleChannel.invokeMethod('setNewOrderOverlayData', {
        'customerId': customerId,
        'orderId': orderId,
        'itemText': itemText,
        'pickupText': pickupText,
        'dropText': dropText,
      });
    } catch (e) {
      debugPrint('⚠️ Failed to send overlay data: $e');
    }
  }

  Future<void> _maybeAutoAcceptFromOverlay() async {
    final cid = _pendingOverlayAcceptCustomerId;
    final oid = _pendingOverlayAcceptOrderId;
    if (cid == null || oid == null) return;
    if (_currentAssignedOrder != null) return;

    Map<String, dynamic>? match;
    for (final r in _nearbyRequests) {
      if (r['_customerId']?.toString() == cid && r['_id']?.toString() == oid) {
        match = r;
        break;
      }
    }
    if (match == null) return;

    // Clear pending overlay accept so it doesn't double-run.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('overlayAcceptCustomerId');
      await prefs.remove('overlayAcceptOrderId');
    } catch (_) {}
    _pendingOverlayAcceptCustomerId = null;
    _pendingOverlayAcceptOrderId = null;

    // ignore: unawaited_futures
    _acceptRequest(Map<String, dynamic>.from(match));
  }

  void _maybeShowPendingOrderPopup() {
    // If user came from notification tap, show the popup immediately after
    // our Firestore listener has data.
    final pendingId = PendingOrder.orderId.value;
    if (pendingId == null || pendingId.isEmpty) return;

    // If we already have an active assigned order, we don't show new request popup.
    if (_currentAssignedOrder != null) return;

    final hasThatOrder = _nearbyRequests.any((r) => r['_id']?.toString() == pendingId);
    debugPrint('[ORDERS] Pending popup check. pendingId=$pendingId nearby=${_nearbyRequests.length} hasThatOrder=$hasThatOrder');
    if (!hasThatOrder) return;

    PendingOrder.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      if (_isSheetOpen) return;
      debugPrint('[ORDERS] Showing popup due to pending orderId=$pendingId');
      _showNearbyRequestsBottomSheet();
    });
  }

  Future<void> _acceptRequest(Map<String, dynamic> req) async {
    final id = req['_id'] as String?;
    final customerId = req['_customerId'] as String?;
    final driverId = _driverId;
    if (id == null || customerId == null) return;

    // Set driver info from local state
    final driverName = _driverName;
    final driverPhone = _driverPhone;

    try {
      final docRef = FirebaseFirestore.instance
          .collection('Customer')
          .doc(customerId)
          .collection('current_order')
          .doc(id);

      // Use a transaction to ensure atomic acceptance
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final freshSnap = await transaction.get(docRef);
        final data = freshSnap.data();

        // Check if the order has ALREADY been accepted by anyone
        // It's crucial to check both acceptedBy (the ID) and driverId
        if (data?['acceptedBy'] != null || data?['driverId'] != null) {
          throw Exception('Order has already been accepted by another driver.');
        }

        // Perform the update
        transaction.update(docRef, {
          'acceptedBy': driverId,
          'driverId': driverId,
          'acceptedAt': FieldValue.serverTimestamp(),
          'acceptedDriverDetails': {
            'driverName': driverName,
            'driverPhone': driverPhone,
            'driverLatLng': _myPos == null
                ? null
                : {'lat': _myPos!.latitude, 'lng': _myPos!.longitude},
          },
          // Setting a status to track the driver's acceptance
          'status': 'accepted', // This is the driver's status
        });
      });
      
      // After transaction, remove direct driverLatLng field if it exists
      try {
        await docRef.update({
          'driverLatLng': FieldValue.delete(),
        });
      } catch (e) {
        // Ignore if field doesn't exist or update fails
        debugPrint('Note: Could not delete direct driverLatLng: $e');
      }

      if (!mounted) return;

      // Update state locally *before* navigation
      setState(() {
        _nearbyRequests.removeWhere((e) => e['_id'] == id);
        // Immediately set the accepted order as the current assigned order
        _currentAssignedOrder = {
          ...req,
          'status': 'accepted', // ensure status is updated locally
          'driverId': driverId,
        };
        _currentAssignedOrder!['_customerId'] = customerId;
        _currentAssignedOrder!['_id'] = id;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order accepted!')),
      );

      // Start background location tracking for accepted order
      try {
        // #region agent log
        _writeDebugLog('porter_home.dart:369', 'Order accept - before MethodChannel', {
          'customerId': customerId,
          'orderId': id,
        }, 'B');
        // #endregion
        
        const platform = MethodChannel('floating.chat.head');
        final result = await platform.invokeMethod('setAcceptedOrder', {
          'customerId': customerId,
          'orderId': id,
        });
        
        // #region agent log
        _writeDebugLog('porter_home.dart:375', 'Order accept - after MethodChannel', {
          'result': result,
          'success': result == true,
        }, 'B');
        // #endregion
        
        debugPrint('✅ Background location tracking started for order $id');
      } catch (e) {
        // #region agent log
        _writeDebugLog('porter_home.dart:377', 'Order accept - MethodChannel error', {
          'error': e.toString(),
        }, 'D');
        // #endregion
        debugPrint('⚠️ Failed to start background location tracking: $e');
      }

      // Hide NEW ORDER indicator once accepted
      // ignore: unawaited_futures
      _bubbleChannel.invokeMethod('setHasNewOrder', {'hasNewOrder': false});
      _lastHasNewOrderSent = false;

      // Navigate to OrderTracking page AFTER state update
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OrderTracking(
            widget.driverAuthId,
            customerId: customerId, orderId: id,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Accept failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to accept. ${e.toString().contains('already been accepted') ? 'Too late! Another driver got it.' : 'Try again.'}')),
      );
    }
  }
  Future<void> _fetchDriverIdFromPhone() async {
    final snap = await FirebaseFirestore.instance.collection('QuickRunDrivers').get();
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['phone'] == widget.driverAuthId) {
        setState(() {
          _driverId = doc.id;
          _driverPhone = data['phone'] ?? '';
          _driverName = data['name'] ?? 'Driver';
        });
        break;
      }
    }
  }

  void _declineRequest(Map<String, dynamic> req) {
    final id = req['_id'] as String?;
    if (id == null) return;
    setState(() {
      _hiddenRequestIds.add(id);
      _nearbyRequests.removeWhere((e) => e['_id'] == id);
    });
  }


  Widget _buildCurrentOrderPanel() {
    if (_currentAssignedOrder == null) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: SizedBox.shrink(),
      );
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.blue.shade800,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Current Order',
              style: GoogleFonts.lexend(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton(
              onPressed: () async {
                if (_currentAssignedOrder == null) return;

                final customerId = _currentAssignedOrder!['_customerId'];
                final orderId = _currentAssignedOrder!['_id'];

                final docRef = FirebaseFirestore.instance
                    .collection('Customer')
                    .doc(customerId)
                    .collection('current_order')
                    .doc(orderId);

                try {
                  final docSnap = await docRef.get();
                  if (!mounted) return;

                  final data = docSnap.data();
                  // --- New logic: check if all items are received first ---
                  final items = data?['items'];
                  bool allItemsReceived = false;
                  if (items is List) {
                    allItemsReceived = items.every((item) =>
                      item is Map && item['itemReceived'] == true
                    );
                  }
                  if (allItemsReceived) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OrderDelivery(
                          customerId: customerId,
                          orderId: orderId,
                          driverAuthId: widget.driverAuthId,
                        ),
                      ),
                    );
                    return;
                  }
                  // Fallback to previous logic if not all items are received
                  final bool orderReceived = data?['orderRecieved'] == true;
                  if (orderReceived) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OrderDelivery(
                          customerId: customerId,
                          orderId: orderId,
                          driverAuthId: widget.driverAuthId,
                        ),
                      ),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OrderTracking(
                          widget.driverAuthId,
                          customerId: customerId,
                          orderId: orderId,
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint("Error fetching order details for navigation: $e");
                  if (!mounted) return;
                  // Fallback to tracking page on error
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => OrderTracking(
                        widget.driverAuthId,
                        customerId: customerId,
                        orderId: orderId,
                      ),
                    ),
                  );
                }
              },
              child: Text(
                'Show Details',
                style: GoogleFonts.lexend(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDriver();
    // App is foreground when this screen is created
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: unawaited_futures
      _setAppInForeground(true);
    });
  }

  Future<void> _initDriver() async {
    await _fetchDriverIdFromPhone();  // 💥 wait until driverId is set
    _ensurePermission();
    _startPositionStream();
    _startOrdersListener(); // ✅ old behavior, but one stable listener

    // Read any "accepted from overlay" saved by Android service.
    // We'll attempt auto-accept as soon as the matching order appears in _nearbyRequests.
    try {
      final prefs = await SharedPreferences.getInstance();
      _pendingOverlayAcceptCustomerId = prefs.getString('overlayAcceptCustomerId');
      _pendingOverlayAcceptOrderId = prefs.getString('overlayAcceptOrderId');
    } catch (_) {}
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _ordersSub?.cancel();
    _assignedOrderSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // If we missed showing the popup due to backgrounding, show it on resume.
    if (state == AppLifecycleState.resumed) {
      // ignore: unawaited_futures
      _setAppInForeground(true);
      debugPrint('[ORDERS] App resumed. pendingPopup=$_pendingShowPopupOnResume nearby=${_nearbyRequests.length} assigned=${_currentAssignedOrder?['_id']} sheetOpen=$_isSheetOpen');
      if (_pendingShowPopupOnResume &&
          _currentAssignedOrder == null &&
          _nearbyRequests.isNotEmpty &&
          !_isSheetOpen &&
          mounted &&
          (ModalRoute.of(context)?.isCurrent == true)) {
        _pendingShowPopupOnResume = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_isSheetOpen) return;
          debugPrint('[ORDERS] Showing deferred popup on resume');
          _showNearbyRequestsBottomSheet();
        });
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // App backgrounded -> allow bubble/overlay to show
      // ignore: unawaited_futures
      _setAppInForeground(false);
    }
  }

  void _showNearbyRequestsBottomSheet() {
    // If driver already has a current order, do NOT show new requests
    if (_currentAssignedOrder != null) {
      return;
    }
    if (_nearbyRequests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No nearby requests available.", style: GoogleFonts.lexend())),
      );
      return;
    }

    // Add PageController and current page state for dots indicator
    final PageController _pageController = PageController();
    int _currentPage = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Allows the sheet to be taller
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent, // Important for custom rounded corners
      builder: (context) {
        _isSheetOpen = true;
        return WillPopScope(
          onWillPop: () async => false,
          child: FractionallySizedBox(
            heightFactor: 0.8, // fixed height, cannot drag down
            child: StatefulBuilder(
              builder: (context, setModalState) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      // --- HEADER (Close) ---
                      Padding(
                        padding: const EdgeInsets.only(top: 10, left: 8, right: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              onPressed: () {
                                // Allow driver to close the sheet manually
                                Navigator.of(context).pop();
                              },
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      // --- DOTS INDICATOR ---
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              _nearbyRequests.length,
                              (index) => AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                width: _currentPage == index ? 34 : 18,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: _currentPage == index ? Colors.black : Colors.grey,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // --- PAGEVIEW ---
                      Expanded(
                        child: PageView.builder(
                          controller: _pageController,
                          onPageChanged: (i) {
                            setModalState(() => _currentPage = i);
                          },
                          itemCount: _nearbyRequests.length,
                          itemBuilder: (context, i) {
                            final r = _nearbyRequests[i] as Map<String, dynamic>;
                            final dist = (r['_distanceKm'] ?? '').toString();
                            final restaurantDetails = (r['_restaurantDetails'] is Map)
                                ? r['_restaurantDetails'] as Map<String, dynamic>
                                : null;

                            // Pickup details
                            String pickupName = '';
                            if (restaurantDetails != null &&
                                restaurantDetails['address'] is Map &&
                                restaurantDetails['address']['address'] != null) {
                              pickupName = restaurantDetails['address']['address'].toString();
                            } else if (r['address'] is Map && r['address']['address'] != null) {
                              pickupName = r['address']['address'].toString();
                            }
                            String pickupDisplay = '';
                            if (restaurantDetails != null && restaurantDetails['name'] != null) {
                              pickupDisplay = restaurantDetails['name'].toString();
                            }

                            // Drop details
                            String dropName = '';
                            if (r['address'] != null && r['address'] is Map) {
                              final dropMap = r['address'];
                              if (dropMap['address'] != null) {
                                dropName = dropMap['address'].toString();
                              }
                            }

                            // Item name
                            final items = r['items'];
                            String itemsText;
                            if (items is List) {
                              itemsText = items
                                  .map((item) => (item is Map && item['name'] != null)
                                  ? item['name'].toString()
                                  : 'Unknown Item')
                                  .join(', ');
                            } else if (items is Map) {
                              itemsText = items['name']?.toString() ?? 'Unknown Item';
                            } else {
                              itemsText = (r['item'] ?? 'Order Item Missing').toString();
                            }

                            // For locations: driver, pickup, customer
                            String yourLocation = 'Current Location';
                            String pickupLocation = pickupDisplay.isNotEmpty ? pickupDisplay : pickupName;
                            String customerLocation = dropName;

                            // Distance calculation
                            String totalDistText = dist != 'N/A' ? '$dist' : 'N/A';
                            if (_myPos != null &&
                                restaurantDetails != null &&
                                restaurantDetails['location'] is Map &&
                                r['address'] != null &&
                                r['address'] is Map &&
                                (restaurantDetails['location']['lat'] != null &&
                                    restaurantDetails['location']['lng'] != null) &&
                                (r['address']['lat'] != null && r['address']['lng'] != null)) {
                              final pickupLat = (restaurantDetails['location']['lat'] as num).toDouble();
                              final pickupLng = (restaurantDetails['location']['lng'] as num).toDouble();
                              final dropLat = (r['address']['lat'] as num).toDouble();
                              final dropLng = (r['address']['lng'] as num).toDouble();
                              final driverToPickupKm = _distanceKm(_myPos!.latitude, _myPos!.longitude, pickupLat, pickupLng);
                              final pickupToDropKm = _distanceKm(pickupLat, pickupLng, dropLat, dropLng);
                              final totalKm = driverToPickupKm + pickupToDropKm;
                              totalDistText = '${totalKm.toStringAsFixed(1)} km';
                            }

                            final orderId = r['_id']?.toString() ?? '';

                            // The content for a single order page
                            return SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildOrderCardContent(
                                      r,
                                      orderId,
                                      totalDistText,
                                      itemsText,
                                      yourLocation,
                                      pickupLocation,
                                      customerLocation,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    ).whenComplete(() {
      _isSheetOpen = false;
      debugPrint('[ORDERS] BottomSheet closed');
      if (mounted) setState(() {});
    });
  }

  // *** The corrected and improved _nearbyRequestsPanel implementation ***
  Widget _buildOrderCardContent(
      Map<String, dynamic> r,
      String orderId,
      String totalDistText,
      String itemsText,
      String yourLocation,
      String pickupLocation,
      String customerLocation,
      ) {
    // This contains the UI for a single order, extracted for reusability.
    return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // NEW ORDER label
                      Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(
                          "NEW ORDER",
                          style: GoogleFonts.lexend(
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1.2,
                            color: const Color(0xFF595959),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0,top: 5),
                        child: Container(
                          height: 1,
                          width: double.infinity,
                          decoration: BoxDecoration(
                           color: const Color(0xFFCACACA),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Order ID
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "ORDER ID",
                                      style: GoogleFonts.lexend(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF929292),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    orderId.isNotEmpty
                                        ? RichText(
                                      text: TextSpan(
                                        style: GoogleFonts.lexend(
                                          fontSize: 21,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                        children: <TextSpan>[
                                          TextSpan(text: '#',style: GoogleFonts.lexend(fontSize: 35)),
                                          TextSpan(
                                              text: orderId.length > 7
                                                  ? orderId.substring(orderId.length - 7).toUpperCase()
                                                  : orderId.toUpperCase(),
                                              style: GoogleFonts.lexend(color: Color(0xFF606060),fontSize: 35)),
                                        ],
                                      ),
                                    )
                                        : Text(
                                      "Order",
                                      style: GoogleFonts.lexend(
                                        fontSize: 21,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Distance

                              Text(
                                totalDistText,
                                style: GoogleFonts.lexend(
                                  color: const Color(0xFF575757),
                                  fontWeight: FontWeight.w400,
                                  fontSize: 15,
                                ),
                              ),
                            ]
                        ),
                      ), // This padding had an extra 12.0
                      const SizedBox(height: 12),
                      // Item name in subtle rounded box
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 0), // Adjust padding
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFCFCFC),
                              borderRadius: BorderRadius.circular(12), // Border radius for item box
                              border: Border.all(color: Colors.grey.shade200, width: 1),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ITEM NAME', style: GoogleFonts.lexend(
                                    fontSize: 9.0,
                                    color: Color(0xFF555555),
                                    fontWeight: FontWeight.w500, letterSpacing: 0.5),
                                ),
                                const SizedBox(height: 2),
                                Text(itemsText, style: GoogleFonts.lexend(
                                    fontSize: 15.0,
                                    color: Color(0xFF757575),
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Three vertical location markers with connecting line and labels
                      Padding(
                        padding: const EdgeInsets.only(left: 0, right: 0, top: 18.0), // Adjust padding
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Dots + line
                            Column(
                              children: [
                                _LocationDot(color: Colors.green),
                                _LocationLine(),
                                _LocationDot(color: Colors.amber),
                                _LocationLine(),
                                _LocationDot(color: Colors.red),
                              ],
                            ),
                            const SizedBox(width: 14),
                            // Labels and values
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _LocationLabel(
                                    label: "Your location",
                                    value: yourLocation,
                                  ),
                                  const SizedBox(height: 18),
                                  _LocationLabel(
                                    label: "Pickup From",
                                    value: pickupLocation,
                                  ),
                                  const SizedBox(height: 18),
                                  _LocationLabel(
                                    label: "Customer Location",
                                    value: customerLocation,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 0), // Adjust padding
                        child: SwipeToAccept(
                          enabled: true,
                          onConfirm: () async {
                            // Close the bottom sheet before navigating
                            Navigator.of(context).pop();
                            await _acceptRequest(r);
                          },
                          onCancel: () {
                            // Implement decline logic and move to next page or close
                            _declineRequest(r);
                            // You might want to automatically swipe to the next order here
                            // Or just close the sheet if it's the last one.
                            if (_nearbyRequests.isEmpty) {
                              Navigator.of(context).pop();
                            }
                          },
                          text: "Swipe to Accept",
                        ),
                      )
                    ],
                  );
  }

  @override
  Widget build(BuildContext context) {
    // We remove the blocking Container() and add a proper placeholder/map here.
    return Scaffold(
      // A placeholder background color, you can replace this with your map widget
      backgroundColor: Colors.grey[200],
      body: Stack(
        children: [
          // 1. Map/Background Placeholder (fills the screen but allows gestures to pass)
          // Example: GoogleMap(...) would go here. For now, it's just the Scaffold background.

          // "Show New Orders" button (only when there are pending nearby requests)
          if (_currentAssignedOrder == null && _nearbyRequests.isNotEmpty && !_isSheetOpen)
            Positioned(
              left: 16,
              right: 16,
              top: 60,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _showNearbyRequestsBottomSheet,
                child: Text(
                  'Show New Orders',
                  style: GoogleFonts.lexend(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),

          // 3. The Fixed Current Order Panel (at the absolute bottom)
          _buildCurrentOrderPanel(),
        ],
      ),
    );
  }
}


// Custom swipe-to-accept widget (replaces ConfirmationSlider)
class SwipeToAccept extends StatefulWidget {
  final bool enabled;
  final Function() onConfirm;
  final Function()? onCancel;
  final String text;

  const SwipeToAccept({
    Key? key,
    required this.onConfirm,
    this.enabled = true,
    this.text = "Swipe to Accept",
    Key? Key, this.onCancel,
  }) : super(key: key);

  @override
  _SwipeToAcceptState createState() => _SwipeToAcceptState();
}

class _SwipeToAcceptState extends State<SwipeToAccept> with SingleTickerProviderStateMixin {
  double _dragPosition = 0.0;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() => _dragPosition = 0);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width - 36;
    const buttonSize = 60.0;

    return GestureDetector(
      onHorizontalDragUpdate: !widget.enabled
          ? null
          : (details) {
        setState(() {
          _dragPosition = (_dragPosition + details.delta.dx).clamp(0.0, width - buttonSize);
        });
      },
      onHorizontalDragEnd: (details) async {
        if (!widget.enabled) return;
        if (_dragPosition > width * 0.7) {
          HapticFeedback.mediumImpact();
          widget.onConfirm();
          _reset();
        } else {
          _controller.forward(from: 0);
          _controller.addListener(() {
            setState(() {
              _dragPosition = (1 - _controller.value) * _dragPosition;
            });
          });
        }
      },
      child: Container(
        width: width,
        height: 65,
        decoration: BoxDecoration(
          color: widget.enabled
              ? const Color(0xFF70F070)
              : const Color(0xFFFFD180), // Yellow shade when disabled
          borderRadius: BorderRadius.circular(30),
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                widget.text,
                style: GoogleFonts.lexend(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Positioned(
              left: _dragPosition,
              top: (65 - buttonSize) / 2, // Center vertically within the 65px height container
              child: Padding(
                padding: const EdgeInsets.only(left: 2.5),
                child: Opacity(
                  opacity: widget.enabled ? 1.0 : 0.6,
                  child: Container(
                    width: buttonSize,
                    height: buttonSize,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      widget.enabled ? Icons.arrow_forward_ios_rounded : Icons.hourglass_top_rounded,
                      color: widget.enabled ? const Color(0xFF70F070) : const Color(0xFFFFA000),
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Helper widgets for location dots and lines (No change needed here)
class _LocationDot extends StatelessWidget {
  final Color color;
  const _LocationDot({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 3,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _LocationLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 2,
      height: 48,
      color: const Color(0xFFD5D7DB),
      margin: const EdgeInsets.symmetric(vertical: 0),
    );
  }
}

class _LocationLabel extends StatelessWidget {
  final String label;
  final String value;
  const _LocationLabel({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.lexend(
            fontSize: 13,
            color: Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.lexend(
            fontSize: 15,
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}