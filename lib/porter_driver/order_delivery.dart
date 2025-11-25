import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
// Note: You must add the 'slide_to_confirm' package to your pubspec.yaml
import 'package:slide_to_confirm/slide_to_confirm.dart';
import 'package:firebase_auth/firebase_auth.dart'; // To get the current driver's ID
// Firestore dependencies
import 'package:cloud_firestore/cloud_firestore.dart';

// --- Placeholder for Main Application Structure ---
// In a real application, ensure you call Firebase.initializeApp() here
// before using Firestore.

// --- OrderDelivery Widget (Updated) ---

class OrderDelivery extends StatefulWidget {
  final String customerId;
  final String orderId;

  const OrderDelivery({
    super.key,
    required this.customerId,
    required this.orderId,
  });

  @override
  State<OrderDelivery> createState() => _OrderDeliveryState();
}

class _OrderDeliveryState extends State<OrderDelivery> {
  bool _isSaving = false;

  /// Handles the logic when the swipe is completed, including saving to Firestore.
  Future<void> _completeOrder() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true; // Set loading state
    });

    try {
      // 1. Get Firestore instance
      final db = FirebaseFirestore.instance;

      // 2. Define the path to the current order document:
      // Customer -> {customerId} -> current_order -> {orderId}
      final currentOrderPath =
          'Customer/${widget.customerId}/current_order/${widget.orderId}';
      final currentOrderRef = db.doc(currentOrderPath);

      // 3. Retrieve the current order data
      final orderSnapshot = await currentOrderRef.get();

      if (!orderSnapshot.exists) {
        throw Exception(
            'Current order document not found at: $currentOrderPath');
      }

      // 4. Extract existing data and prepare history data
      Map<String, dynamic> existingOrderData =
      orderSnapshot.data() as Map<String, dynamic>;

      // NEW: Get the current logged-in driver's ID
      final driverId = FirebaseAuth.instance.currentUser?.uid;
      if (driverId == null) {
        throw Exception('No driver is currently logged in.');
      }

      // NEW: Extract restaurant and payment details for the driver's history
      final restaurantAcceptedId = existingOrderData['restaurentAccpetedId'];
      final paymentMethod = existingOrderData['paymentMethod'] as Map<String, dynamic>? ?? {};
      final paymentBrand = paymentMethod['brand'];
      final paymentLabel = paymentMethod['label'];


      // 5. Merge existing data with completion metadata
      // This ensures all original fields (items, address, etc.) are preserved in history.
      final Map<String, dynamic> historyData = {
        ...existingOrderData, // Include all fields from the original order
        'orderId': widget.orderId, // Ensure key fields are present
        'customerId': widget.customerId,
        'completedAt': FieldValue.serverTimestamp(), // Get accurate server time
        'status': 'DELIVERED', // Update status to final
        'deliveryDriverId': driverId, // Use the actual driver's ID
      };

      // 6. Define the path for the new document in the OrderHistory subcollection
      // using the orderId as the document ID.
      // Customer -> {customerId} -> OrderHistory -> {orderId}
      final orderHistoryDocRef = db
          .collection('Customer') // Go to the root 'Customer' collection
          .doc(widget.customerId)
          .collection('OrderHistory') // Go to the 'OrderHistory' subcollection
          .doc(widget.orderId); // Specify the document ID to be the orderId

      // 7. Set the data for the document using the specified orderId.
      await orderHistoryDocRef.set(historyData);

      // NEW: Create a record in the driver's own `previousOrder` collection
      // QuickRunDrivers -> {driverId} -> previousOrder -> {orderId}
      final driverHistoryRef = db
          .collection('QuickRunDrivers')
          .doc(driverId)
          .collection('previousOrder')
          .doc(widget.orderId);

      await driverHistoryRef.set({
        'orderId': widget.orderId,
        'restaurentAccpetedId': restaurantAcceptedId,
        'paymentBrand': paymentBrand,
        'paymentLabel': paymentLabel,
        'completedAt': FieldValue.serverTimestamp(),
      });
      // 8. Delete the original document from the 'current_order' subcollection
      await currentOrderRef.delete();

      // Success feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Order complete, archived, and removed from current list!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      }
      print('Order ${widget.orderId} successfully archived to OrderHistory and deleted from $currentOrderPath.');
    } catch (e) {
      // Error handling
      print('Error completing order: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Failed to complete order. Error: ${e.toString().split(':')[0]}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false; // Clear loading state
        });
      }
      // In a real app, you would likely pop the screen here:
      // Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Delivery'),
        backgroundColor: const Color(0xFF34a853), // Matching theme color
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Delivering Order:',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                widget.orderId,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF34a853),
                  fontFamily: GoogleFonts.lexend().fontFamily,
                ),
              ),
              const SizedBox(height: 20),
              if (_isSaving)
                const Column(
                  children: [
                    SizedBox(height: 20),
                    CircularProgressIndicator(color: Color(0xFF34a853)),
                    SizedBox(height: 10),
                    Text('Finalizing delivery...'),
                  ],
                ),
              const SizedBox(height: 40),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      const Icon(Icons.person,
                          size: 30, color: Color(0xFF34a853)),
                      const SizedBox(height: 10),
                      Text(
                        'Customer ID: ${widget.customerId}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const Divider(),
                      const Text(
                          'Add more details here like address and items...',
                          style: TextStyle(fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
      ),
      // We use a Container in the bottomNavigationBar property
      // to get the correct placement and safe area handling.
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(
            20, 10, 20, 30), // Add padding, especially for the bottom safe area
        color: Colors.white, // Background color for the bar
        child: IgnorePointer(
          ignoring: _isSaving, // Disable swipe when saving
          child: ConfirmationSlider(
            text: _isSaving ? 'Processing...' : 'Swipe to done order',
            textStyle: GoogleFonts.lexend(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w400,
            ),
            onConfirmation: _completeOrder,
            height: 75,
            backgroundColor: _isSaving
                ? Colors.grey
                : const Color(0xFF34a853), // Main green background
            backgroundColorEnd:
            Colors.grey.shade700, // Color after confirmation
            foregroundColor: _isSaving
                ? Colors.grey.shade600
                : const Color(0xFF2e8b45), // Darker green for the slider button
            sliderButtonContent: _isSaving
                ? const Padding(
              padding: EdgeInsets.all(12.0),
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 3),
            )
                : const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white,
            ),
            shadow: const BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
            backgroundShape: BorderRadius.circular(50),
            foregroundShape: BorderRadius.circular(50),
          ),
        ),
      ),
    );
  }
}