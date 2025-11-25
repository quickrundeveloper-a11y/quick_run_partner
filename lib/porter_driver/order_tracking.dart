import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async'; // Needed for Future.delayed
import 'package:audioplayers/audioplayers.dart';
import 'order_delivery.dart'; // UNCOMMENT THIS when running in your real project
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'dart:io';
import 'package:lottie/lottie.dart';

// -----------------------------------------------------------------------------
// NOTE: Since I don't have your 'order_delivery.dart', I have commented out the
// navigation import. Please uncomment the import above and the navigation logic
// inside the file where marked.
// -----------------------------------------------------------------------------

class OrderTracking extends StatefulWidget {
  final String driverAuthId;
  const OrderTracking(this.driverAuthId, {
    super.key,
    required this.customerId,
    required this.orderId,
  });

  final String customerId;
  final String orderId;

  @override
  State<OrderTracking> createState() => _OrderTrackingState();
}

class _OrderTrackingState extends State<OrderTracking> {
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _isScanning = true;
  bool _orderReceived = false;
  bool _isProcessing = false;
  String? scannedProductId;

  String? _restaurantId;
  String? _driverDocId;
  Map<String, dynamic>? _restaurantLocation;
  String? _restaurantPhone;

  List<Map<String, dynamic>> _orderItems = [];
  bool _showSuccessAnim = false;
  String? _lastScannedName;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _lastScannedRaw;
  
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
  void dispose() {
    controller.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadOrderItems();
    _fetchRestaurantId();
    _fetchDriverDocId();
  }

  Future<void> _fetchRestaurantId() async {
    try {
      final orderRef = FirebaseFirestore.instance
          .collection('Customer')
          .doc(widget.customerId)
          .collection('current_order')
          .doc(widget.orderId);

      final snap = await orderRef.get();
      final data = snap.data() as Map<String, dynamic>?;
      if (data == null) return;

      final List items = List.from(data['items'] ?? []);
      if (items.isEmpty) return;

      final first = items.first as Map<String, dynamic>;
      final restId = first['restaurentId'];

      if (restId != null && restId is String) {
        setState(() {
          _restaurantId = restId;
        });
        _fetchRestaurantLocation();
      }
    } catch (e) {
      debugPrint("Failed to fetch restaurantId: $e");
    }
  }

  Future<void> _fetchRestaurantLocation() async {
    if (_restaurantId == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('Restaurent_shop')
          .doc(_restaurantId)
          .get();
      final data = doc.data();
      if (data != null) {
        setState(() {
          if (data['location'] != null) {
            _restaurantLocation = Map<String, dynamic>.from(data['location']);
          }
          _restaurantPhone = data['phone']?.toString();
        });
      }
    } catch (e) {
      debugPrint("Failed to fetch restaurant location: $e");
    }
  }

  Future<void> _fetchDriverDocId() async {
    final snap = await FirebaseFirestore.instance.collection('QuickRunDrivers').get();
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['phone'] == widget.driverAuthId) {
        setState(() {
          _driverDocId = doc.id;
        });
        break;
      }
    }
  }

  Future<void> _loadOrderItems() async {
    try {
      final orderRef = FirebaseFirestore.instance
          .collection('Customer')
          .doc(widget.customerId)
          .collection('current_order')
          .doc(widget.orderId);
      final snap = await orderRef.get();
      final data = snap.data() as Map<String, dynamic>?;
      final List items = List.from(data?['items'] ?? []);
      setState(() {
        _orderItems = items.map((raw) {
          final m = Map<String, dynamic>.from(raw as Map);

          // Force productId fallback from Firestore 'id'
          if (m['productId'] == null && m['id'] != null) {
            m['productId'] = m['id'];
          }

          return m;
        }).toList();
      });
    } catch (_) {}
  }

  void _onQrCodeDetect(BarcodeCapture capture) async {
    if (!_isScanning || _isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final qr = barcodes.first.rawValue;
    _showSnackBar("Scanned: $qr");
    setState(() {
      _lastScannedRaw = qr;
    });
    if (qr == null) return;

    setState(() {
      _isScanning = false;     // bas logically band karo
      _isProcessing = true;
    });

    // Extract orderId + productId
    String? scannedOrderId;
    scannedProductId = null;

    try {
      // #region agent log
      _writeDebugLog('order_tracking.dart:180', 'QR scan - before parse', {
        'rawQr': qr,
        'expectedOrderId': widget.orderId,
      }, 'A');
      // #endregion
      
      final Map<String, dynamic> qrData = Map<String, dynamic>.from(
        jsonDecode(qr),
      );
      scannedOrderId = qrData['orderId']?.toString();
      scannedProductId = qrData['productId']?.toString();
      
      // #region agent log
      _writeDebugLog('order_tracking.dart:187', 'QR scan - after parse', {
        'scannedOrderId': scannedOrderId,
        'scannedProductId': scannedProductId,
        'matchesOrderId': scannedOrderId == widget.orderId,
      }, 'A');
      // #endregion
      
      // Debug: Log the extracted values
      debugPrint("🔍 QR Parsed - orderId: $scannedOrderId, productId: $scannedProductId");
      
      // If productId is still null, try alternative field names
      if (scannedProductId == null) {
        scannedProductId = qrData['id']?.toString() ?? 
                          qrData['product_id']?.toString() ?? 
                          qrData['itemId']?.toString();
        debugPrint("🔍 Trying alternative fields - productId: $scannedProductId");
      }
    } catch (e) {
      debugPrint("⚠️ JSON parse failed: $e, trying fallback parser");
      // fallback old parser
      final parts = qr.split(',');
      for (final part in parts) {
        if (part.trim().startsWith('orderId:')) {
          scannedOrderId = part.replaceFirst('orderId:', '').trim();
        }
        if (part.trim().startsWith('productId:')) {
          scannedProductId = part.replaceFirst('productId:', '').trim();
        }
        // Also try 'id:' format
        if (part.trim().startsWith('id:')) {
          scannedProductId = part.replaceFirst('id:', '').trim();
        }
      }
      debugPrint("🔍 Fallback parser - orderId: $scannedOrderId, productId: $scannedProductId");
    }
    
    // Final check - if still null, log the raw QR for debugging
    if (scannedProductId == null || scannedProductId!.isEmpty) {
      debugPrint("❌ productId is NULL or EMPTY after parsing. Raw QR: $qr");
      // #region agent log
      _writeDebugLog('order_tracking.dart:224', 'QR scan - productId null/empty', {
        'rawQr': qr,
        'scannedOrderId': scannedOrderId,
        'expectedOrderId': widget.orderId,
      }, 'A');
      // #endregion
      setState(() {
        _isScanning = true;
        _isProcessing = false;
      });
      return;
    }
    
    // #region agent log
    _writeDebugLog('order_tracking.dart:232', 'QR scan - validation check', {
      'scannedOrderId': scannedOrderId,
      'expectedOrderId': widget.orderId,
      'orderIdMatch': scannedOrderId == widget.orderId,
      'hasProductId': scannedProductId != null && scannedProductId!.isNotEmpty,
    }, 'A');
    // #endregion

    if (scannedOrderId == widget.orderId && scannedProductId != null && scannedProductId!.isNotEmpty) {
      try {
        final orderRef = FirebaseFirestore.instance
            .collection('Customer')
            .doc(widget.customerId)
            .collection('current_order')
            .doc(widget.orderId);

        final orderSnap = await orderRef.get();
        final orderData = orderSnap.data() as Map<String, dynamic>;
        final List items = List.from(orderData['items'] ?? []);

        Map<String, dynamic>? foundItem;
        int foundIndex = -1;
        bool found = false;
        
        debugPrint("🔍 Searching for productId: $scannedProductId in ${items.length} items");
        
        for (int i = 0; i < items.length; i++) {
          final itemMap = Map<String, dynamic>.from(items[i] as Map);

          // FIX: use productId if present, otherwise use id
          final itemPid = (itemMap['productId'] ?? itemMap['id'])?.toString();
          
          debugPrint("🔍 Item $i - productId: ${itemMap['productId']}, id: ${itemMap['id']}, computed: $itemPid");

          if (itemPid != null && itemPid == scannedProductId) {
            if (itemMap['itemReceived'] == true) {
              found = true;
              break;
            }

            itemMap['itemReceived'] = true;
            itemMap['itemReceivedAt'] = DateTime.now().toIso8601String();

            _lastScannedName = (itemMap['name'] ?? itemPid).toString();

            foundItem = Map<String, dynamic>.from(itemMap);
            foundIndex = i;
            found = true;

            items[i] = itemMap; // store modified data back
            break;
          }
        }

        if (found) {
          setState(() {
            _orderItems =
                items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            _showSuccessAnim = true;
          });

          await orderRef.update({'items': items});
          // --- Save delivered item details in Restaurent_shop → deliveredItem
          try {
            if (foundItem != null) {
              final String restId = foundItem['restaurentId'] ?? "";
              if (restId.isNotEmpty) {
                final restRef = FirebaseFirestore.instance
                    .collection('Restaurent_shop')
                    .doc(restId)
                    .collection('deliveredItem');

                final today = DateTime.now();
                final todayId = "${today.year}-${today.month}-${today.day}";

                await restRef.doc(todayId).set({
                  "items": FieldValue.arrayUnion([
                    {
                      "productId": foundItem['productId'] ?? foundItem['id'],
                      "name": foundItem['name'],
                      "mrp": foundItem['mrp'],
                      "price": foundItem['price'],
                      "image": foundItem['image'],
                      "quantity": foundItem['quantity'],
                      "unit": foundItem['unit'],
                      "percentOff": foundItem['percentOff'],
                      "multiple": foundItem['multiple'],
                      "addedAt": foundItem['addedAt'],
                      "restaurentId": foundItem['restaurentId'],
                      "acceptedAt": DateTime.now().toIso8601String(),
                      "acceptedBy": _driverDocId,
                      "status": "delivered",
                      "totalAmount": foundItem['price'] * (foundItem['quantity'] ?? 1),
                    }
                  ])
                }, SetOptions(merge: true));
              }
            }
          } catch (e) {
            debugPrint("Failed to save deliveredItem: $e");
          }
          // Play sound if asset exists
          try {
            await _audioPlayer.play(AssetSource('order_verified.mp3'));
          } catch(e) {
            debugPrint("Audio file not found or error: $e");
          }


          _showSnackBar('✅ Item verified: ${_lastScannedName ?? scannedProductId}');
          await Future.delayed(const Duration(milliseconds: 900));

          setState(() {
            _showSuccessAnim = false;
          });

          final allDone = _orderItems.every((it) => it['itemReceived'] == true);
          if (allDone) {
            setState(() {
              _orderReceived = true;
            });
            await Future.delayed(const Duration(milliseconds: 700));
            if (mounted) {
              // ---------------------------------------------------------
              // UNCOMMENT YOUR NAVIGATION HERE
              // ---------------------------------------------------------

              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => OrderDelivery(
                    customerId: widget.customerId,
                    orderId: widget.orderId,
                    driverAuthId: widget.driverAuthId,
                  ),
                ),
              );

            }
            return;
          }

          await Future.delayed(const Duration(milliseconds: 400));
          setState(() {
            _isProcessing = false;
            _isScanning = true;
            scannedProductId = null;
          });
        } else {
          _showSnackBar('❌ Wrong product QR — not found in order');
          await Future.delayed(const Duration(seconds: 1));
          setState(() {
            _isScanning = true;
            _isProcessing = false;
          });
        }
      } catch (e) {
        _showSnackBar('❌ Failed to update: $e');
        await Future.delayed(const Duration(seconds: 1));
        await controller.start();
        setState(() {
          _isScanning = true;
          _isProcessing = false;
        });
      }
    } else {
      _showSnackBar('❌ Wrong QR — not matching product/order.');
      await Future.delayed(const Duration(seconds: 1));
      setState(() {
        _isScanning = true;
        _isProcessing = false;
      });
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1500),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Background color similar to the image (off-white/light grey)
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header Text
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Scan\nthe QR',
                      style: GoogleFonts.lexend(
                        fontSize: 32,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 50),
              if (_lastScannedRaw != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Scanned Data: ${_lastScannedRaw}",
                        style: GoogleFonts.lexend(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: Colors.black87,
                        ),
                      ),
                      if (scannedProductId != null)
                        Text(
                          "Extracted Product ID: $scannedProductId",
                          style: GoogleFonts.lexend(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.green,
                          ),
                        )
                      else
                        Text(
                          "⚠️ Product ID: NULL",
                          style: GoogleFonts.lexend(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.red,
                          ),
                        ),
                    ],
                  ),
                ),


              // 2. The Scanner Area
              Center(
                child: SizedBox(
                  width: 260,
                  height: 260,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // The actual scanner camera view
                      if (!_orderReceived)
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: Colors.white, // Fallback if camera loads slow
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: MobileScanner(
                              controller: controller,
                              onDetect: _onQrCodeDetect,
                              // Fit logic to fill the rounded square
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),

                      // Success/Loading Overlay
                      if (_isProcessing || _showSuccessAnim)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: _showSuccessAnim
                                ? const Icon(Icons.check_circle,
                                color: Colors.green, size: 60)
                                : const CircularProgressIndicator(
                                color: Colors.white),
                          ),
                        ),

                      // If order is done
                      if (_orderReceived)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: Lottie.asset(
                              'assets/lottie/success.json',
                              width: 180,
                              height: 180,
                              repeat: false,
                            ),
                          ),
                        ),

                      // The Custom "Brackets" Border Overlay
                      // This draws the specific UI from your image
                      IgnorePointer(
                        child: CustomPaint(
                          size: const Size(280, 280), // Slightly larger than scanner
                          painter: CornerScannerPainter(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 50),

              // 3. The List of Items
              _orderItems.isEmpty
                  ? const Center(child: Text("Loading order details..."))
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      itemCount: _orderItems.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = _orderItems[index];
                        final name = item['name'] ?? item['productId'] ?? 'Unknown';
                        final productId = item['productId'] ?? item['id'] ?? 'N/A';
                        final isReceived = item['itemReceived'] == true;

                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEEEEE), // Light grey card
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  // Format: "1 )   Name"
                                  Text(
                                    "${index + 1} )",
                                    style:  GoogleFonts.lexend(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  // Wrap Name and Food ID in a Column
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name.toString(),
                                          style: GoogleFonts.lexend(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w400,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "Product ID: $productId",
                                          style: GoogleFonts.lexend(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w300,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // The Status Dot
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isReceived
                                          ? const Color(0xFF32CD32) // Bright Green
                                          : const Color(0xFFFFD700), // Yellow/Gold
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Divider(),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () {
                                        if (_restaurantLocation != null) {
                                          final lat = _restaurantLocation?['lat'];
                                          final lng = _restaurantLocation?['lng'];
                                          final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=bicycling');
                                          launchUrl(url, mode: LaunchMode.externalApplication);
                                        }
                                      },
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.navigation_outlined, color: Colors.black87),
                                          SizedBox(width: 8),
                                          Text('Get Direction', style: GoogleFonts.lexend(fontSize: 14, fontWeight: FontWeight.w400)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Container(width: 1, height: 30, color: Colors.black12),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () {
                                        if (_restaurantPhone != null) {
                                          final url = Uri.parse('tel:${_restaurantPhone}');
                                          launchUrl(url);
                                        }
                                      },
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.call, color: Colors.black87),
                                          SizedBox(width: 8),
                                          Text('Call Now', style: GoogleFonts.lexend(fontSize: 14, fontWeight: FontWeight.w400)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------
// Custom Painter to draw the specific corner brackets
// -------------------------------------------------------
class CornerScannerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 4 // Thickness of the bracket
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round; // Rounded ends of the lines

    double cornerSize = 40.0; // Length of the bracket arms
    double radius = 20.0; // Curve of the corner

    // 1. Top Left
    Path topLeft = Path();
    topLeft.moveTo(0, cornerSize);
    topLeft.lineTo(0, radius);
    topLeft.arcToPoint(Offset(radius, 0), radius: Radius.circular(radius));
    topLeft.lineTo(cornerSize, 0);
    canvas.drawPath(topLeft, paint);

    // 2. Top Right
    Path topRight = Path();
    topRight.moveTo(size.width - cornerSize, 0);
    topRight.lineTo(size.width - radius, 0);
    topRight.arcToPoint(Offset(size.width, radius), radius: Radius.circular(radius));
    topRight.lineTo(size.width, cornerSize);
    canvas.drawPath(topRight, paint);

    // 3. Bottom Left
    Path bottomLeft = Path();
    bottomLeft.moveTo(0, size.height - cornerSize);
    bottomLeft.lineTo(0, size.height - radius);
    bottomLeft.arcToPoint(Offset(radius, size.height), radius: Radius.circular(radius), clockwise: false);
    bottomLeft.lineTo(cornerSize, size.height);
    canvas.drawPath(bottomLeft, paint);

    // 4. Bottom Right
    Path bottomRight = Path();
    bottomRight.moveTo(size.width - cornerSize, size.height);
    bottomRight.lineTo(size.width - radius, size.height);
    bottomRight.arcToPoint(Offset(size.width, size.height - radius), radius: Radius.circular(radius), clockwise: false);
    bottomRight.lineTo(size.width, size.height - cornerSize);
    canvas.drawPath(bottomRight, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}