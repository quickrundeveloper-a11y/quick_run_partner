import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart'; // (kept if you use Cupertino icons elsewhere)
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:async/async.dart'; // For StreamGroup.merge
import 'package:flutter/services.dart';


class SellerHome extends StatefulWidget {
  final String driverAuthId;
  const SellerHome(this.driverAuthId, {super.key});



  @override
  State<SellerHome> createState() => _SellerHomeState();
}

class _SellerHomeState extends State<SellerHome> with WidgetsBindingObserver {
  String currentRestId = "";
  bool _isOnline = false; // default to online
  bool _isLoadingRest = true;
  String? _restLoadError;

  // Android floating bubble / overlay (same channel used by Driver)
  static const MethodChannel _bubbleChannel = MethodChannel('floating.chat.head');
  bool _lastHasNewOrderSent = false;
  String? _lastOverlayOrderIdSent;
  bool _desiredHasNewOrder = false;
  Map<String, String>? _desiredOverlayPayload; // last built payload to re-send on background transition
  
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAll();
    // App is foreground when SellerHome starts
    // ignore: unawaited_futures
    _setAppInForeground(true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload restaurant ID if needed
    if (currentRestId.isEmpty && !_isLoadingRest) {
      _loadCurrentRestId();
    }
  }

  Future<void> _initAll() async {
    await _loadOnlineStatus();
    await _loadCurrentRestId();

    // If seller was already online, ensure bubble service is running.
    if (_isOnline) {
      // ignore: unawaited_futures
      _startBubble();
    }
  }

  Future<void> _loadOnlineStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'driver_${widget.driverAuthId}_isOnline';
      final stored = prefs.getBool(key);
      setState(() {
        _isOnline = stored ?? false; // if not set, default to online
      });
      print('✅ Loaded online status for ${widget.driverAuthId}: $_isOnline');
    } catch (e) {
      print('❌ Error loading online status: $e');
    }
  }

  Future<void> _startBubble() async {
    try {
      await _bubbleChannel.invokeMethod("startBubble");
      debugPrint("🟢 SELLER ONLINE → Starting bubble...");
    } catch (e) {
      debugPrint("❌ Seller startBubble error: $e");
    }
  }

  Future<void> _stopBubble() async {
    try {
      await _bubbleChannel.invokeMethod("stopBubble");
      debugPrint("🔴 SELLER OFFLINE → Stopping bubble...");
    } catch (e) {
      debugPrint("❌ Seller stopBubble error: $e");
    }
  }

  Future<void> _setAppInForeground(bool inForeground) async {
    try {
      await _bubbleChannel.invokeMethod('setAppInForeground', {'inForeground': inForeground});
    } catch (e) {
      debugPrint('⚠️ Seller failed to update app foreground state: $e');
    }
  }

  Future<void> _setHasNewOrder(bool hasNewOrder) async {
    await _setHasNewOrderInternal(hasNewOrder, force: false);
  }

  Future<void> _setHasNewOrderInternal(bool hasNewOrder, {required bool force}) async {
    _desiredHasNewOrder = hasNewOrder;
    if (!force && _lastHasNewOrderSent == hasNewOrder) return;
    _lastHasNewOrderSent = hasNewOrder;
    try {
      await _bubbleChannel.invokeMethod('setHasNewOrder', {'hasNewOrder': hasNewOrder});
    } catch (e) {
      debugPrint('⚠️ Seller failed to setHasNewOrder($hasNewOrder): $e');
    }
  }

  Future<void> _setNewOrderOverlayData({
    required String customerId,
    required String orderId,
    required String itemText,
    required String pickupText,
    required String dropText,
  }) async {
    _desiredOverlayPayload = {
      'customerId': customerId,
      'orderId': orderId,
      'itemText': itemText,
      'pickupText': pickupText,
      'dropText': dropText,
    };
    // Avoid spamming Android service with the same overlay payload.
    if (_lastOverlayOrderIdSent == orderId) return;
    _lastOverlayOrderIdSent = orderId;
    try {
      await _bubbleChannel.invokeMethod('setNewOrderOverlayData', {
        'customerId': customerId,
        'orderId': orderId,
        'itemText': itemText,
        'pickupText': pickupText,
        'dropText': dropText,
        'showAccept': false, // seller should not accept from overlay
        'mode': 'seller',
      });
    } catch (e) {
      debugPrint('⚠️ Seller failed to setNewOrderOverlayData: $e');
    }
  }

  Future<void> _setOnlineStatus(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'driver_${widget.driverAuthId}_isOnline';
      await prefs.setBool(key, value);
      print('💾 Saved online status for ${widget.driverAuthId}: $value');
    } catch (e) {
      print('❌ Error saving online status: $e');
    }
  }

  Future<void> _loadCurrentRestId() async {
    try {
      setState(() {
        _isLoadingRest = true;
        _restLoadError = null;
      });

      String cleanPhone = widget.driverAuthId.replaceAll("+91", "").trim();

      final q = await FirebaseFirestore.instance
          .collection('Restaurent_shop')
          .where('phone', isEqualTo: cleanPhone)
          .limit(1)
          .get();

      if (q.docs.isNotEmpty) {
        final newRestId = q.docs.first.id;
        setState(() {
          currentRestId = newRestId;
          _isLoadingRest = false;
        });
        print("🍽️ Loaded Restaurant ID: $currentRestId");
      } else {
        setState(() {
          _isLoadingRest = false;
          _restLoadError = "Restaurant not found for $cleanPhone";
        });
        print("❌ No restaurant found for phone: $cleanPhone");
      }
    } catch (e) {
      setState(() {
        _isLoadingRest = false;
        _restLoadError = "Error loading restaurant: $e";
      });
      print("❌ Error loading restaurant ID: $e");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Mirror driver behavior: service must know when to hide/show overlay.
    if (state == AppLifecycleState.resumed) {
      // ignore: unawaited_futures
      _setAppInForeground(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // When app is going background, re-send desired new-order state so the
      // Android service can show bubble/overlay immediately even if the order
      // was first detected while we were foreground.
      // ignore: unawaited_futures
      _setAppInForeground(false).then((_) async {
        // Force a ping even if value didn't change (service may have reset while fg).
        await _setHasNewOrderInternal(_desiredHasNewOrder, force: true);
        final p = _desiredOverlayPayload;
        if (_desiredHasNewOrder && p != null) {
          await _setNewOrderOverlayData(
            customerId: p['customerId'] ?? '',
            orderId: p['orderId'] ?? '',
            itemText: p['itemText'] ?? 'New Order',
            pickupText: p['pickupText'] ?? 'Pickup:',
            dropText: p['dropText'] ?? 'Drop:',
          );
        }
      });
    }
  }

  /// Computes whether seller has any "new/unaccepted" order for this restaurant.
  /// When true, we notify the Android `FloatingService` so it can show the red bubble
  /// + full overlay card while app is backgrounded.
  Future<void> _syncSellerNewOrderState(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredOrders,
  ) async {
    if (!_isOnline) {
      await _setHasNewOrder(false);
      return;
    }

    // Define "new order" for seller: an order that contains items for this restaurant
    // and has NOT been accepted by a restaurant yet.
    QueryDocumentSnapshot<Map<String, dynamic>>? newest;
    for (final doc in filteredOrders) {
      final data = doc.data();
      final isAccepted = data['restaurentAccpetedId'] != null;
      if (isAccepted) continue;
      newest = doc;
      break;
    }

    final hasNew = newest != null;
    await _setHasNewOrderInternal(hasNew, force: false);
    if (!hasNew) return;

    try {
      final doc = newest!;
      final data = doc.data();
      final customerId = doc.reference.parent.parent?.id ?? '';
      if (customerId.isEmpty) return;

      final items = (data['items'] as List?) ?? const [];
      final itemNames = <String>[];
      for (final it in items) {
        if (it is Map && it['restaurentId']?.toString() == currentRestId) {
          final nm = (it['name'] ?? '').toString().trim();
          if (nm.isNotEmpty) itemNames.add(nm);
        }
      }
      final itemText = itemNames.isEmpty ? 'New Order' : itemNames.take(4).join(', ');

      final address = data['address'];
      String dropText = 'Drop: Customer';
      if (address is Map) {
        final line = (address['landmark'] ?? address['address'] ?? address['fullAddress'] ?? '').toString().trim();
        if (line.isNotEmpty) dropText = 'Drop: $line';
      }

      await _setNewOrderOverlayData(
        customerId: customerId,
        orderId: doc.id,
        itemText: itemText,
        pickupText: 'Pickup: Your restaurant',
        dropText: dropText,
      );
    } catch (e) {
      debugPrint('⚠️ Seller _syncSellerNewOrderState overlay build failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xFFF1F0F5),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _isOnline = !_isOnline;
                });
                _setOnlineStatus(_isOnline);
                // Start/stop bubble service for seller, same as driver.
                if (_isOnline) {
                  // ignore: unawaited_futures
                  _startBubble();
                } else {
                  // ignore: unawaited_futures
                  _setHasNewOrder(false);
                  // ignore: unawaited_futures
                  _stopBubble();
                }
                if (currentRestId.isNotEmpty) {
                  FirebaseFirestore.instance
                      .collection('Restaurent_shop')
                      .doc(currentRestId)
                      .update({'activeShop': _isOnline}).then((_) {
                    print("🔥 Firestore updated activeShop = $_isOnline");
                  }).catchError((e) {
                    print("❌ Error updating activeShop: $e");
                  });
                } else {
                  print("❌ currentRestId is empty, cannot update activeShop");
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 130,
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: _isOnline ? Color(0xFF00BA69) : Color(0xFF83C7FF),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: Text(
                        _isOnline ? 'ONLINE' : 'OFFLINE',
                        style: GoogleFonts.lexend(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    AnimatedAlign(
                      duration: Duration(milliseconds: 300),
                      alignment: _isOnline ? Alignment.centerRight : Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.all(.0),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: _isOnline ? Color(0xFF008C4F) : Color(0xFF0088FF),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                //  Icon(CupertinoIcons.profile_circled,size: 35,)
              ],
            ),
          ],
        ),
      ),
      backgroundColor: Color(0xFFF1F0F5),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Builder(
              builder: (context) {
                if (_isLoadingRest) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (_restLoadError != null) {
                  return Center(
                    child: Text(
                      _restLoadError!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.lexend(
                        fontSize: 14,
                        color: Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }

                if (currentRestId.isEmpty) {
                  return Center(
                    child: Text(
                      'Restaurant not found',
                      style: GoogleFonts.lexend(
                        fontSize: 14,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }

                // Use Stream.periodic to fetch orders every 2 seconds - simple and reliable
                return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                  stream: Stream.periodic(const Duration(seconds: 2))
                      .asyncMap((_) async {
                    print("🔄 Fetching all orders...");
                    
                    try {
                      // Get all customers
                      final customerSnapshot = await FirebaseFirestore.instance
                          .collection('Customer')
                          .get();
                      
                      print("👥 Found ${customerSnapshot.docs.length} customers");
                      
                      // Collect all orders from all customers
                      List<QueryDocumentSnapshot<Map<String, dynamic>>> allOrders = [];
                      
                      for (var customerDoc in customerSnapshot.docs) {
                        try {
                          final orderSnapshot = await FirebaseFirestore.instance
                              .collection('Customer')
                              .doc(customerDoc.id)
                              .collection('current_order')
                              .get();
                          
                          print("  📦 Customer ${customerDoc.id.substring(0, 8)}...: ${orderSnapshot.docs.length} orders");
                          allOrders.addAll(orderSnapshot.docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>());
                        } catch (e) {
                          print("❌ Error fetching orders for customer ${customerDoc.id}: $e");
                        }
                      }
                      
                      print("📦 TOTAL orders collected: ${allOrders.length}");
                      return allOrders;
                    } catch (e) {
                      print("❌ ERROR fetching orders: $e");
                      return <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    }
                  }),
                  builder: (context, snapshotOrders) {
                        if (snapshotOrders.connectionState ==
                            ConnectionState.waiting && 
                            !snapshotOrders.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        
                        final allOrderDocs = snapshotOrders.data ?? [];
                        
                        print("📦 Builder: ${allOrderDocs.length} orders available");
                        print(
                            "📦 Total orders fetched: ${allOrderDocs.length}, Restaurant ID: $currentRestId");

                        if (allOrderDocs.isEmpty) {
                          print("❌ ERROR: No orders in snapshot - stream is empty!");
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'No orders found',
                                  style: GoogleFonts.lexend(
                                    fontSize: 16,
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Restaurant ID: $currentRestId',
                                  style: GoogleFonts.lexend(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        // Filter orders for current restaurant
                        print("🔍 Checking ${allOrderDocs.length} orders for restaurant $currentRestId");
                        final filteredOrders = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                        
                        for (var orderDoc in allOrderDocs) {
                          try {
                            final data = orderDoc.data() as Map<String, dynamic>;
                            final List<dynamic> items = data['items'] ?? [];
                            
                            print("📋 Order ${orderDoc.id} has ${items.length} items");
                            
                            bool hasRestaurantItem = false;
                            for (var item in items) {
                              final itemMap = item as Map<String, dynamic>;
                              final restId = itemMap['restaurentId']?.toString();
                              print("  - Item: ${itemMap['name']}, restaurentId: $restId (currentRestId: $currentRestId)");
                              
                              if (restId == currentRestId) {
                                hasRestaurantItem = true;
                                print("  ✅ MATCH FOUND!");
                                break;
                              }
                            }
                            
                            if (hasRestaurantItem) {
                              filteredOrders.add(orderDoc);
                              print("✅ Added order ${orderDoc.id} to filtered list");
                            } else {
                              print("❌ Order ${orderDoc.id} does not match restaurant $currentRestId");
                            }
                          } catch (e) {
                            print("❌ ERROR processing order ${orderDoc.id}: $e");
                            print("  Data: ${orderDoc.data()}");
                          }
                        }

                        print("🍽️ Filtered orders for restaurant: ${filteredOrders.length} out of ${allOrderDocs.length} total");

                        if (filteredOrders.isEmpty) {
                          // If there are no orders for this restaurant, clear indicator.
                          // ignore: unawaited_futures
                          _setHasNewOrder(false);
                          return Center(
                            child: Text(
                              'No current orders',
                              style: GoogleFonts.lexend(
                                fontSize: 14,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }

                        // Keep Android overlay in sync (best-effort; do not block UI build).
                        // ignore: unawaited_futures
                        _syncSellerNewOrderState(filteredOrders);

                        return ListView.builder(
                          itemCount: filteredOrders.length,
                          itemBuilder: (context, index) {
                            final data = filteredOrders[index].data();
                            final address = data['address'] ?? {};
                            final userId = data['userId'] ?? 'N/A';
                            final payment = data['paymentMethod'] ?? {};
                            final List<dynamic> items = data['items'] ?? [];

                            // Filter items for current restaurant
                            final orderItems = items
                                .where((it) =>
                            it['restaurentId'] == currentRestId)
                                .toList();
                            if (orderItems.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            // Check if the restaurant has accepted
                            final bool isRestaurantAccepted =
                                data['restaurentAccpetedId'] != null;

                            return Card(
                              color: Colors.white,
                              margin: const EdgeInsets.symmetric(vertical: 12),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(40),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 40.0, horizontal: 20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "ORDER ID",
                                      style: GoogleFonts.lexend(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                        color: Color(0xFF555555),
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    RichText(
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text: '#',
                                            style: GoogleFonts.lexend(
                                              fontSize: 35,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.black,
                                            ),
                                          ),
                                          TextSpan(
                                            text: filteredOrders[index].id
                                                .toString()
                                                .toUpperCase()
                                                .substring(
                                                filteredOrders[index].id
                                                    .length -
                                                    7),
                                            style: GoogleFonts.lexend(
                                              fontSize: 35,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF606060),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Color(0xFFFCFCFC),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Column(
                                          children: [
                                            ...orderItems.map((item) {
                                              // Get orderId and productId, ensuring they're not null
                                              final orderId = filteredOrders[index].id;
                                              // Try multiple fields to get productId, ensure it's not empty
                                              final productId = (item['id']?.toString() ?? 
                                                                 item['productId']?.toString() ?? 
                                                                 item['_id']?.toString() ?? 
                                                                 '').trim();
                                              
                                              // Validate that we have both IDs
                                              if (orderId.isEmpty || productId.isEmpty) {
                                                print('⚠️ WARNING: Missing IDs for QR - orderId: $orderId, productId: $productId, item: $item');
                                                // Skip this item if we don't have valid IDs
                                                return const SizedBox.shrink();
                                              }
                                              
                                              // #region agent log
                                              _writeDebugLog('seller_home.dart:445', 'QR generation - before', {
                                                'orderId': orderId,
                                                'itemId': item['id'],
                                                'itemProductId': item['productId'],
                                                'computedProductId': productId,
                                              }, 'A');
                                              // #endregion
                                              
                                              // Properly format JSON string with escaped quotes
                                              final qrData = '{"orderId":"$orderId","productId":"$productId"}';
                                              
                                              // Validate JSON before using
                                              try {
                                                final testJson = jsonDecode(qrData);
                                                // #region agent log
                                                _writeDebugLog('seller_home.dart:494', 'QR generation - after', {
                                                  'qrData': qrData,
                                                  'isValidJson': true,
                                                  'testOrderId': testJson['orderId'],
                                                  'testProductId': testJson['productId'],
                                                }, 'A');
                                                // #endregion
                                              } catch (e) {
                                                print('❌ ERROR: Invalid QR JSON: $qrData, error: $e');
                                                return const SizedBox.shrink();
                                              }
                                              
                                              // Debug print to verify QR data
                                              print('📱 QR Code generated - orderId: $orderId, productId: $productId');
                                              
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                    bottom: 8.0),
                                                child: Column(
                                                  children: [
                                                    Row(
                                                      crossAxisAlignment: CrossAxisAlignment
                                                          .start,
                                                      children: [
                                                        if (item['image'] !=
                                                            null &&
                                                            item['image'] != "")
                                                          ClipRRect(
                                                            borderRadius: BorderRadius
                                                                .circular(8),
                                                            child: Image
                                                                .network(
                                                              item['image'],
                                                              height: 110,
                                                              width: 110,
                                                              fit: BoxFit.cover,
                                                            ),
                                                          ),
                                                        const SizedBox(
                                                            width: 12),
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment
                                                                .start,
                                                            children: [
                                                              Row(
                                                                mainAxisAlignment: MainAxisAlignment
                                                                    .spaceBetween,
                                                                children: [
                                                                  Text(
                                                                    "ITEM NAME",
                                                                    style: GoogleFonts
                                                                        .lexend(
                                                                      fontSize: 12,
                                                                      fontWeight: FontWeight
                                                                          .w400,
                                                                      color: Color(
                                                                          0xFF555555),
                                                                    ),
                                                                  ),
                                                                  (item['isVeg'] !=
                                                                      null)
                                                                      ? Container(
                                                                    height: 20,
                                                                    width: 20,
                                                                    decoration: BoxDecoration(
                                                                      border: Border
                                                                          .all(
                                                                        color: item['isVeg'] ==
                                                                            'veg'
                                                                            ? Colors
                                                                            .green
                                                                            : Colors
                                                                            .red,
                                                                        width: 2,
                                                                      ),
                                                                      borderRadius: BorderRadius
                                                                          .circular(
                                                                          4),
                                                                    ),
                                                                    child: Center(
                                                                      child: Container(
                                                                        height: 10,
                                                                        width: 10,
                                                                        decoration: BoxDecoration(
                                                                          color: item['isVeg'] ==
                                                                              'veg'
                                                                              ? Colors
                                                                              .green
                                                                              : Colors
                                                                              .red,
                                                                          shape: BoxShape
                                                                              .circle,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  )
                                                                      : SizedBox(
                                                                      width: 20),
                                                                ],
                                                              ),
                                                              Text(
                                                                item['name'] ??
                                                                    'Unknown Item',
                                                                overflow: TextOverflow
                                                                    .ellipsis,
                                                                style: GoogleFonts
                                                                    .lexend(
                                                                  fontSize: 19,
                                                                  fontWeight: FontWeight
                                                                      .w400,
                                                                  color: Colors
                                                                      .black,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  height: 10),
                                                              Row(
                                                                mainAxisAlignment: MainAxisAlignment
                                                                    .spaceBetween,
                                                                children: [
                                                                  Column(
                                                                    crossAxisAlignment: CrossAxisAlignment
                                                                        .start,
                                                                    children: [
                                                                      Text(
                                                                        "PRICE",
                                                                        style: GoogleFonts
                                                                            .lexend(
                                                                          fontSize: 12,
                                                                          fontWeight: FontWeight
                                                                              .w400,
                                                                          color: Color(
                                                                              0xFF555555),
                                                                        ),
                                                                      ),
                                                                      Text(
                                                                        "₹ ${(item['price'] is num)
                                                                            ? item['price']
                                                                            .toInt()
                                                                            : item['price']}",
                                                                        style: GoogleFonts
                                                                            .lexend(
                                                                          fontSize: 19,
                                                                          fontWeight: FontWeight
                                                                              .w400,
                                                                          color: Colors
                                                                              .black,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  Column(
                                                                    crossAxisAlignment: CrossAxisAlignment
                                                                        .start,
                                                                    children: [
                                                                      Text(
                                                                        "QUANTITY",
                                                                        style: GoogleFonts
                                                                            .lexend(
                                                                          fontSize: 12,
                                                                          fontWeight: FontWeight
                                                                              .w400,
                                                                          color: Color(
                                                                              0xFF555555),
                                                                        ),
                                                                      ),
                                                                      Text(
                                                                        "${item['quantity']} ${((item['unit'] ??
                                                                            ''))
                                                                            .toString()
                                                                            .toUpperCase()}",
                                                                        overflow: TextOverflow
                                                                            .ellipsis,
                                                                        style: GoogleFonts
                                                                            .lexend(
                                                                          fontSize: 19,
                                                                          fontWeight: FontWeight
                                                                              .w400,
                                                                          color: Colors
                                                                              .black,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ],
                                                              ),
                                                              const SizedBox(
                                                                  height: 12),
                                                              QrImageView(
                                                                data: qrData,
                                                                version: QrVersions
                                                                    .auto,
                                                                size: 120,
                                                              ),

                                                              const SizedBox(
                                                                  height: 10),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }),
                                            const SizedBox(height: 10),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
            ),
          ),
        ],
      ),
    );
  }
}