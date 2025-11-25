import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'order_tracking.dart'; // Import for OrderTracking
import 'order_delivery.dart'; // Import for OrderDelivery
import 'package:flutter/services.dart';


class PorterHome extends StatefulWidget {
  const PorterHome({super.key});

  @override
  State<PorterHome> createState() => _PorterHomeState();
}

class _PorterHomeState extends State<PorterHome> {
  // --- Driver identity (TODO: wire to your auth/user profile) ---
  String _driverName = 'Driver';
  String _driverPhone = '0000000000';
  String? _driverId;
  StreamSubscription<User?>? _authSub;

  Position? _myPos;
  StreamSubscription<Position>? _posSub;

  // Key change: Store subcollection listeners to manage them
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _customerOrderSubs = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _customerCollectionSub;

  // Requests within 10km of driver
  final List<Map<String, dynamic>> _nearbyRequests = [];
  final Set<String> _hiddenRequestIds =
  <String>{}; // locally declined this session

  // Accepted panel state (used by _buildAcceptedPanel)
  bool _showAccepted = false;
  Map<String, dynamic>? _activeReqData;
  double _mapBottomPadding = 0;

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

  // Helper to process an order snapshot change
  void _processOrderUpdate(String customerId, QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final orderId = doc.id;

    // *** FIX: REMOVED AUTO-ACCEPTANCE LOGIC ***
    // The previous logic here would automatically call _acceptRequest if
    // `restaurentAccpetedId` was set and the request was in `_nearbyRequests`.
    // This is the source of the race condition.
    // By removing it, the driver must now manually swipe to accept.
    final restaurantId = data['restaurentAccpetedId'] as String?;

    // If this order is the one currently assigned to THIS driver, update the current order state
    // We check for `driverId` AND `status == 'accepted'` (set by the driver's _acceptRequest)
    if (data['driverId'] == _driverId && data['status'] == 'accepted') {
      setState(() {
        _currentAssignedOrder = {
          ...data,
          '_id': orderId,
          '_customerId': customerId,
        };
        // Also remove it from the list of new requests, just in case
        _nearbyRequests.removeWhere((e) => e['_id'] == orderId);
      });
      return; // Stop further processing for this order
    }

    // First, remove any existing entry for this order/customer combo
    _nearbyRequests.removeWhere(
          (e) => e['_id'] == orderId && e['_customerId'] == customerId,
    );

    // If the order has been accepted by ANY driver (even if driverId is not THIS driver), or is hidden, skip
    if (data['acceptedBy'] != null || data['driverId'] != null || _hiddenRequestIds.contains(orderId)) {
      return;
    }

    // Orders are visible if:
    // 1. Not accepted by a driver (`acceptedBy` == null and `driverId` == null)
    // 2. Not locally hidden
    if (data['acceptedBy'] == null && data['driverId'] == null) {
      // Try computing distance if pickup coordinates are available
      final pick = data['PickupLatLng'];
      double? dKm;
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

      // Fetch Restaurant Details if 'restaurentAccpetedId' exists
      Map<String, dynamic>? restaurantDetails;
      if (restaurantId != null) {
        restaurantDetails = await _fetchRestaurantDetails(restaurantId);
        // We need to trigger a UI update once the data is fetched
        if (mounted) {
          setState(() {});
        }
      }

      // Add the request to the list (with a check to prevent adding duplicates after async fetch)
      // Check again if the order is still unaccepted and not hidden
      if (data['acceptedBy'] == null && data['driverId'] == null && !_nearbyRequests.any((e) => e['_id'] == orderId && e['_customerId'] == customerId)) {
        _nearbyRequests.add({
          ...data,
          'isGrocery': true, // Assuming this is for grocery
          '_id': orderId,
          '_customerId': customerId,
          if (dKm != null) '_distanceKm': double.parse(dKm.toStringAsFixed(2)),
          if (restaurantDetails != null) '_restaurantDetails': restaurantDetails, // Store fetched details
        });
      }
    }

    // Sort requests by distance after processing
    _nearbyRequests.sort((a, b) {
      final distA = a['_distanceKm'] as double? ?? double.infinity;
      final distB = b['_distanceKm'] as double? ?? double.infinity;
      return distA.compareTo(distB);
    });

    // Explicit setState call to update UI after processing/sorting, especially after async call
    if (mounted) {
      setState(() {});
    }
  }

  // Listen to all Customer/*/current_order collections
  void _startCustomerOrdersListener() {
    // 1. Listen for changes in the parent 'Customer' collection
    _customerCollectionSub = FirebaseFirestore.instance.collection('Customer').snapshots().listen(
          (customerSnapshot) {
        for (final change in customerSnapshot.docChanges) {
          final customerId = change.doc.id;

          if (change.type == DocumentChangeType.added) {
            // New Customer: Start listening to their 'current_order' subcollection
            if (!_customerOrderSubs.containsKey(customerId)) {
              final sub = FirebaseFirestore.instance
                  .collection('Customer')
                  .doc(customerId)
                  .collection('current_order')
                  .snapshots()
                  .listen((orderSnap) {
                // Process initial and subsequent order changes
                setState(() {
                  for (final orderDoc in orderSnap.docs) {
                    _processOrderUpdate(customerId, orderDoc);
                  }

                  // Also explicitly check if an order was unassigned from this driver
                  if (_currentAssignedOrder != null && _currentAssignedOrder!['_customerId'] == customerId) {
                    final stillExists = orderSnap.docs.any((d) => d.id == _currentAssignedOrder!['_id']);
                    if (!stillExists) {
                      setState(() {
                        _currentAssignedOrder = null;
                      });
                    }
                  }
                  if (orderSnap.docChanges.any((c) => c.type == DocumentChangeType.removed && c.doc.id == _currentAssignedOrder?['_id'])) {
                    setState(() => _currentAssignedOrder = null);
                  }

                  // Clean up removed documents (if they were in the list)
                  for (final removedChange in orderSnap.docChanges) {
                    if (removedChange.type == DocumentChangeType.removed) {
                      _nearbyRequests.removeWhere(
                            (e) =>
                        e['_id'] == removedChange.doc.id &&
                            e['_customerId'] == customerId,
                      );
                    }
                  }

                  // Sorting is now handled in _processOrderUpdate to ensure sorting after async data is back
                  // _nearbyRequests.sort(...) // Removed here
                });
              }, onError: (e) => debugPrint('Order sub listener error: $e'));
              _customerOrderSubs[customerId] = sub;
            }
          } else if (change.type == DocumentChangeType.removed) {
            // Customer removed: Cancel its subcollection listener and remove all its orders
            _customerOrderSubs[customerId]?.cancel();
            _customerOrderSubs.remove(customerId);
            setState(() {
              _nearbyRequests
                  .removeWhere((e) => e['_customerId'] == customerId);
            });
          }
        }
      },
      onError: (e) => debugPrint('Customer collection listener error: $e'),
    );
  }

  Future<void> _acceptRequest(Map<String, dynamic> req) async {
    final id = req['_id'] as String?;
    final customerId = req['_customerId'] as String?;
    final driverId = FirebaseAuth.instance.currentUser?.uid;
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
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order accepted!')),
      );

      // Navigate to OrderTracking page AFTER state update
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OrderTracking(
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

  void _declineRequest(Map<String, dynamic> req) {
    final id = req['_id'] as String?;
    if (id == null) return;
    setState(() {
      _hiddenRequestIds.add(id);
      _nearbyRequests.removeWhere((e) => e['_id'] == id);
    });
  }


  Widget _buildCurrentOrderPanel() {
    if (_currentAssignedOrder == null) return const SizedBox.shrink();

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

                final docRef = FirebaseFirestore.instance.collection('Customer').doc(customerId).collection('current_order').doc(orderId);
                final docSnap = await docRef.get();

                if (!mounted) return;

                final data = docSnap.data();
                final bool orderReceived = data?['orderRecieved'] == true;

                if (orderReceived) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => OrderDelivery(customerId: customerId, orderId: orderId)),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => OrderTracking(customerId: customerId, orderId: orderId)),
                  );
                }
              },
              child:  Text(
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
    // set current driver id from FirebaseAuth and listen for changes
    _driverId = FirebaseAuth.instance.currentUser?.uid;
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      setState(() {
        _driverId = user?.uid;
        if (_driverId != null) {
          // When driver signs in, start listening for orders they might already have
        }
      });
    });

    _ensurePermission();
    _startPositionStream();
    _startCustomerOrdersListener();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _authSub?.cancel();
    _customerCollectionSub?.cancel();
    // Cancel all subcollection listeners
    _assignedOrderSub?.cancel();
    _customerOrderSubs.forEach((key, sub) => sub.cancel());
    _customerOrderSubs.clear();
    super.dispose();
  }

  // *** The corrected and improved _nearbyRequestsPanel implementation ***
  Widget _nearbyRequestsPanel() {
    if (_nearbyRequests.isEmpty) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          // Adjust padding to account for the current order panel at the very bottom
          padding: EdgeInsets.fromLTRB(12, 8, 12, _currentAssignedOrder != null ? 80 : 12),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(12),
              child: Text(
                'No nearby requests found.',
                style: GoogleFonts.lexend(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    // Using DraggableScrollableSheet is the best way to handle this floating, interactive panel
    return DraggableScrollableSheet(
      initialChildSize: 0.8, // Start at 50% height
      minChildSize: 0.15,    // Can be minimized a bit
      maxChildSize: 0.9,     // Can be maximized
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: ListView.separated(
            controller: scrollController, // Essential: Connects the list to the DraggableSheet
            // Padding adjustment for when the current order panel is visible
            padding: EdgeInsets.fromLTRB(12, 8, 12, _currentAssignedOrder != null ? 80 : 12),
            itemCount: _nearbyRequests.length,
            separatorBuilder: (_, __) => const SizedBox(height: 18),
            itemBuilder: (context, i) {
              final r = _nearbyRequests[i] as Map<String, dynamic>;
              final dist = (r['_distanceKm'] ?? 'N/A').toString();
              final restaurantDetails = (r['_restaurantDetails'] is Map)
                  ? r['_restaurantDetails'] as Map<String, dynamic>
                  : null;
              // Check if the restaurant has accepted the order yet.
              final bool isRestaurantAccepted = r['restaurentAccpetedId'] != null;
              // Driver can only accept if the restaurant has accepted
              final bool canDriverAccept = isRestaurantAccepted;

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
              String totalDistText = dist != 'N/A' ? '$dist km' : 'N/A';
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

              // Card UI
              return Material(
                elevation: 4, // Added elevation for better separation
                borderRadius: BorderRadius.circular(18),
                color: Colors.white,
                child: Container(
                  padding: const EdgeInsets.symmetric( vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0,top: 5),
                        child: Container(
                          height: 5,
                          width: 70,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCACACA),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
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
                      ),
                      const SizedBox(height: 12),
                      // Item name in subtle rounded box
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18.0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFCFCFC),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ITEM NAME ',
                                  style: GoogleFonts.lexend(
                                    fontSize: 9.0,
                                    color: Color(0xFF555555),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  itemsText,
                                  style: GoogleFonts.lexend(
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
                        padding: const EdgeInsets.only(left: 18.0, right: 18.0, top: 18.0),
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
                        padding: const EdgeInsets.symmetric(horizontal: 18.0),
                        child: SwipeToAccept(
                          enabled: true,
                          onConfirm: () async {
                            await _acceptRequest(r);
                          },
                          text: "Swipe to Accept",
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // We remove the blocking Container() and add a proper placeholder/map here.
    return Scaffold(
      backgroundColor: Colors.transparent, // Make background transparent to show parent's color
      body: Stack(
        children: [
          // 1. Map/Background Placeholder (fills the screen but allows gestures to pass)

          // 2. The Draggable Panel for Requests (contains the functional slider)
          _nearbyRequestsPanel(),

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
  final Future<void> Function() onConfirm;
  final String text;

  const SwipeToAccept({
    required this.onConfirm,
    this.enabled = true,
    this.text = "Swipe to Accept",
    Key? key,
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
          await widget.onConfirm();
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