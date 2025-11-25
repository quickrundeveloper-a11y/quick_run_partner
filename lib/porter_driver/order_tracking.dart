import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async'; // Needed for Future.delayed
import 'order_delivery.dart'; // Import the OrderDelivery screen
import 'package:audioplayers/audioplayers.dart';

class OrderTracking extends StatefulWidget {
  const OrderTracking({
    super.key,
    required this.customerId,
    required this.orderId,
  });

  final String customerId; // The User ID of the customer who placed the order
  final String orderId; // The Document ID of the specific order

  @override
  State<OrderTracking> createState() => _OrderTrackingState();
}

class _OrderTrackingState extends State<OrderTracking> {
  final MobileScannerController controller = MobileScannerController(
    // Optional: Only scan QR codes
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _isScanning = true;
  bool _orderReceived = false;
  bool _isProcessing = false;
  String? scannedProductId;

  List<Map<String, dynamic>> _orderItems = [];
  bool _showSuccessAnim = false;
  String? _lastScannedName;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void dispose() {
    controller.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Preload order items so UI can show status and names
    _loadOrderItems();
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
        _orderItems = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (_) {}
  }

  void _onQrCodeDetect(BarcodeCapture capture) async {
    if (!_isScanning || _isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final qr = barcodes.first.rawValue;
    if (qr == null) return;

    await controller.stop();
    setState(() {
      _isScanning = false;
      _isProcessing = true;
    });

    // Extract orderId + productId from scanned QR
    final parts = qr.split(',');
    String? scannedOrderId;
    scannedProductId = null;

    for (final part in parts) {
      if (part.trim().startsWith('orderId:')) {
        scannedOrderId = part.replaceFirst('orderId:', '').trim();
      }
      if (part.trim().startsWith('productId:')) {
        scannedProductId = part.replaceFirst('productId:', '').trim();
      }
    }

    if (scannedOrderId == widget.orderId && scannedProductId != null) {
      try {
        final orderRef = FirebaseFirestore.instance
            .collection('Customer')
            .doc(widget.customerId)
            .collection('current_order')
            .doc(widget.orderId);

        final orderSnap = await orderRef.get();
        final orderData = orderSnap.data() as Map<String, dynamic>;
        final List items = List.from(orderData['items'] ?? []);

        bool found = false;
        for (int i = 0; i < items.length; i++) {
          if (items[i]['productId'] == scannedProductId) {
            // if already received, ignore
            if (items[i]['itemReceived'] == true) {
              found = true;
              break;
            }
            items[i]['itemReceived'] = true;
            items[i]['itemReceivedAt'] = DateTime.now().toIso8601String();
            _lastScannedName = (items[i]['name'] ?? items[i]['productId']).toString();
            found = true;
            break;
          }
        }

        if (found) {
          // update local cache immediately for UI
          setState(() {
            _orderItems = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            _showSuccessAnim = true;
          });

          // push update to firestore
          await orderRef.update({'items': items});
          await _audioPlayer.play(AssetSource('order_verified.mp3'));

          // show success then resume scanning or finish
          _showSnackBar('✅ Item verified: ${_lastScannedName ?? scannedProductId}');
          await Future.delayed(const Duration(milliseconds: 900));

          // hide animation and check if all scanned
          setState(() {
            _showSuccessAnim = false;
          });

          final allDone = _orderItems.every((it) => it['itemReceived'] == true);
          if (allDone) {
            setState(() {
              _orderReceived = true;
            });
            // small delay and navigate
            await Future.delayed(const Duration(milliseconds: 700));
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => OrderDelivery(
                    customerId: widget.customerId,
                    orderId: widget.orderId,
                  ),
                ),
              );
            }
            return;
          }

          // resume scanning for next item
          await Future.delayed(const Duration(milliseconds: 400));
          await controller.start();
          setState(() {
            _isProcessing = false;
            _isScanning = true;
            scannedProductId = null;
          });
        } else {
          _showSnackBar('❌ Wrong product QR — not found in order');
          await Future.delayed(const Duration(seconds: 1));
          await controller.start();
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
      await controller.start();
      setState(() {
        _isScanning = true;
        _isProcessing = false;
      });
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Tracking & Pickup'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Text(
              'Order ID: ${widget.orderId}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text('Customer ID: ${widget.customerId}\n'),
            const Divider(),
            if (_orderReceived)
              const Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 80),
                    SizedBox(height: 10),
                    Text(
                      'Order is marked as Received!',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              )
            else
              Center(
                child: Column(
                  children: [
                    const Text('Scan the QR Code to confirm order pickup/delivery.', textAlign: TextAlign.center),
                    const SizedBox(height: 15),
                    Container(
                      height: 300,
                      width: 300,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.black12, width: 1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          children: [
                            // The QR Code Scanner View
                            MobileScanner(
                              controller: controller,
                              onDetect: _onQrCodeDetect,
                            ),
                            // Overlay for better scanning experience
                            QRScannerOverlay(overlayColour: Colors.transparent),
                            if (_isProcessing)
                              const Center(
                                child: CircularProgressIndicator(color: Colors.blueAccent),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // show list of items with status
                    if (_orderItems.isNotEmpty)
                      Column(
                        children: _orderItems.map((it) {
                          final pid = it['productId'] ?? '';
                          final name = (it['name'] ?? pid).toString();
                          final received = it['itemReceived'] == true;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Text(name, style: const TextStyle(fontSize: 14))),
                                received
                                    ? Row(children: const [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 6), Text('Verified')])
                                    : Row(children: [Text(pid, style: const TextStyle(color: Colors.black54)), const SizedBox(width: 8), const Text('Pending', style: TextStyle(color: Colors.orange))]),
                              ],
                            ),
                          );
                        }).toList(),
                      ),

                    const SizedBox(height: 12),

                    // success animation
                    if (_showSuccessAnim)
                      Column(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 48),
                          const SizedBox(height: 6),
                          Text(_lastScannedName ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                        ],
                      ),

                    const SizedBox(height: 10),
                    Text(
                      _isScanning ? 'Scanner is active...' : (_isProcessing ? 'Processing scan...' : 'Scan paused.'),
                      style: TextStyle(color: _isScanning ? Colors.blue : Colors.red),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class QRScannerOverlay extends StatelessWidget {
  final Color overlayColour;

  const QRScannerOverlay({super.key, required this.overlayColour});

  @override
  Widget build(BuildContext context) {
    // CustomPaint is often used for creating a transparent hole in the center
    // and an outer border for the scanning area. This is a basic placeholder.
    return Center(
      child: Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.redAccent, width: 3),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}