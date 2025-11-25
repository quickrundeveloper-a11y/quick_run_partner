import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:quick_run_driver/main.dart';
import 'package:slide_to_confirm/slide_to_confirm.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

// --- Placeholder for Main Application Structure ---
// In a real application, ensure you call Firebase.initializeApp() here
// before using Firestore.

// --- OrderDelivery Widget (Updated) ---

class OrderDelivery extends StatefulWidget {
  final String customerId;
  final String orderId;
  final String driverAuthId;
  const OrderDelivery({
    super.key,
    required this.customerId,
    required this.orderId,
    required this.driverAuthId,
  });

  @override
  State<OrderDelivery> createState() => _OrderDeliveryState();
}

class _OrderDeliveryState extends State<OrderDelivery> {
  bool _isSaving = false;
  String? _driverId;

  Map<String, dynamic>? _orderData;
  bool _loadingOrder = true;

  Future<void> _fetchDriverIdFromPhone() async {
    final snap = await FirebaseFirestore.instance.collection('QuickRunDrivers').get();
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['phone'] == widget.driverAuthId) {
        setState(() {
          _driverId = doc.id;
        });
        break;
      }
    }
  }

  Future<void> _loadOrderDetails() async {
    final db = FirebaseFirestore.instance;
    final snap = await db
        .doc('Customer/${widget.customerId}/current_order/${widget.orderId}')
        .get();
    if (snap.exists) {
      setState(() {
        _orderData = snap.data() as Map<String, dynamic>;
        _loadingOrder = false;
      });
    } else {
      setState(() => _loadingOrder = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchDriverIdFromPhone();
    _loadOrderDetails();
  }

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
      // Customer -> {customerId} -> current_ordser -> {orderId}
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

      // NEW: Use the resolved driver ID
      final driverId = _driverId;
      if (driverId == null) {
        throw Exception('Driver ID not resolved.');
      }

      // NEW: Extract restaurant and payment details for the driver's history
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

      // Use today's date as collection name
      final today = DateTime.now();
      final dateString = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

      final driverHistoryRef = db
          .collection('QuickRunDrivers')
          .doc(driverId)
          .collection(dateString)
          .doc(widget.orderId);

      await driverHistoryRef.set({
        ...existingOrderData, // include everything from customer order
        'orderId': widget.orderId,
        'customerId': widget.customerId,
        'completedAt': FieldValue.serverTimestamp(),
        'status': 'DELIVERED',
        'deliveryDriverId': driverId,
        'paymentBrand': paymentBrand,
        'paymentLabel': paymentLabel,
      });
      // 8. Delete the original document from the 'current_order' subcollection
      await currentOrderRef.delete();

      // Calculate delivery time based on acceptedAt and now
      final acceptedAtTs = existingOrderData['acceptedAt'] as Timestamp?;
      final acceptedAt =
          acceptedAtTs != null ? acceptedAtTs.toDate() : DateTime.now();
      final completedAt = DateTime.now();
      final deliveryDuration = completedAt.difference(acceptedAt);

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OrderSuccessScreen(duration: deliveryDuration),
          ),
        );

        await Future.delayed(const Duration(seconds: 5));

        if (mounted) Navigator.of(context).pop();
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

  Future<void> _launchCall(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openMap(double lat, double lng) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildPaymentCard() {
    final method = _orderData?['paymentMethod'] ?? {};
    final label = method['label'] ?? 'N/A';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Payment Method",
          style: GoogleFonts.lexend(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Color(0xFFE3E3E3)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.lexend(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Image.asset("assets/cash.png",height: 40,width: 40,)
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddressCard() {
    final addr = _orderData?['address'] ?? {};
    final name = addr['name'] ?? '';
    final phone = addr['phone'] ?? '';
    final lat = (addr['lat'] as num?)?.toDouble();
    final lng = (addr['lng'] as num?)?.toDouble();

    return Container(
      decoration: BoxDecoration(
        color: Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Color(0xFFE3E3E3)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: const Icon(Icons.person_outline, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.lexend(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        phone,
                        style: GoogleFonts.lexend(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 58,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: (lat != null && lng != null)
                        ? () => _openMap(lat, lng)
                        : null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.near_me_outlined, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Get Direction',
                          style: GoogleFonts.lexend(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: Colors.grey.shade300,
                ),
                Expanded(
                  child: InkWell(
                    onTap: phone.toString().isNotEmpty
                        ? () => _launchCall(phone.toString())
                        : null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.call_outlined, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Call Now',
                          style: GoogleFonts.lexend(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList() {
    final items = _orderData?['items'] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Items",
          style: GoogleFonts.lexend(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: 240,
          child: items is List && items.isNotEmpty
              ? ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final item = items[index] as Map<String, dynamic>;
                    final name = item['name'] ?? 'NA';
                    final image = item['image'];
                    final qty = item['quantity'];
                    final unit = item['unit'] ?? '';
                    final price = item['price'];
                    final mrp = item['mrp'];

                    return Container(
                      width: 140,
                      decoration: BoxDecoration(
                        color: Color(0xFFF7F7F7),
                          border: Border.all(width: 1,color: Color(0xFFE3E3E3)),

                          borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                ),// ← White background for image area
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(18),
                                    topRight: Radius.circular(18),
                                  ),
                                  child: image != null
                                      ? Image.network(
                                          image,
                                          height: 120,
                                          width: 120,
                                          fit: BoxFit.contain,
                                        )
                                      : Container(
                                          height: 100,
                                          color: Colors.white,
                                          child: const Icon(Icons.image_outlined),
                                        ),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.lexend(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "${qty ?? ''} $unit",
                                  style: GoogleFonts.lexend(
                                    fontSize: 11,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Text(
                                      "₹${price ?? ''}",
                                      style: GoogleFonts.lexend(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    if (mrp != null && mrp != price)
                                      Text(
                                        "₹$mrp",
                                        style: GoogleFonts.lexend(
                                          fontSize: 11,
                                          color: Colors.black45,
                                          decoration: TextDecoration
                                              .lineThrough,
                                        ),
                                      ),
                                    const SizedBox(height: 6),

                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                )
              : Center(
                  child: Text(
                    "No items",
                    style: GoogleFonts.lexend(fontSize: 14),
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final shortId = widget.orderId.length > 7
        ? widget.orderId.substring(widget.orderId.length - 7).toUpperCase()
        : widget.orderId.toUpperCase();

    return Scaffold(
      backgroundColor: Color(0xFFF7F7F7),
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Color(0xFFF7F7F7),
        toolbarHeight: 80,
        automaticallyImplyLeading: false,
        leading: InkWell(
            onTap: () => Navigator.of(context).pop(),
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Container(
                decoration: const BoxDecoration(
                  border: Border.fromBorderSide(
                    BorderSide(color: Color(0xFFE3E3E3)),
                  ),
                  shape: BoxShape.circle,
                  color: Color(0xFFF0F0F0),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Color(0xFFE3E3E3), size: 20),
                ),
              ),
            ),
          ),
        ),
      body: _loadingOrder
          ? const Center(child: CircularProgressIndicator())
          : _orderData == null
              ? const Center(child: Text("Order not found"))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "ORDER ID",
                        style: GoogleFonts.lexend(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF929292),
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: "#",
                              style: GoogleFonts.lexend(
                                fontSize: 37,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF000000),
                              ),
                            ),
                            TextSpan(
                                text: shortId,
                                style: GoogleFonts.lexend(fontSize: 37, fontWeight: FontWeight.w600, color: Color(0xFF606060))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildAddressCard(),
                      const SizedBox(height: 24),
                      _buildPaymentCard(),
                      const SizedBox(height: 24),
                      _buildItemsList(),
                      const SizedBox(height: 120),
                    ],
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
                ? Colors.grey.shade400
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


class OrderSuccessScreen extends StatelessWidget {
  final Duration duration;
  const OrderSuccessScreen({super.key, required this.duration});

  @override
  Widget build(BuildContext context) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A7A4F),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF0A7A4F),
                const Color(0xFF0A7A4F).withOpacity(0.9),
                const Color(0xFF1B5E20),
              ],
            ),
          ),
          child: Stack(
            children: [
              // Floating circles in background
              Positioned(
                top: 50,
                right: 30,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.05),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 100,
                left: 40,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.05),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 150,
                left: 20,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.05),
                  ),
                ),
              ),

              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Success animation container
                      Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.white.withOpacity(0.2),
                              Colors.white.withOpacity(0.05),
                            ],
                          ),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.15),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Lottie.asset(
                            'assets/lottie/success.json',
                            width: 200,
                            height: 200,
                            repeat: false,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Success title with animation
                      TweenAnimationBuilder<double>(
                        duration: const Duration(milliseconds: 800),
                        tween: Tween(begin: 0.0, end: 1.0),
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 20 * (1 - value)),
                              child: child,
                            ),
                          );
                        },
                        child: Column(
                          children: [
                            Text(
                              'Order Delivered!',
                              style: GoogleFonts.lexend(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                                height: 1.2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Your order has been successfully delivered',
                              style: GoogleFonts.lexend(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Delivery time card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.timer_outlined,
                                  color: Colors.white.withOpacity(0.8),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Delivery Time',
                                  style: GoogleFonts.lexend(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Minutes
                                Column(
                                  children: [
                                    Text(
                                      minutes.toString().padLeft(2, '0'),
                                      style: GoogleFonts.lexend(
                                        color: Colors.white,
                                        fontSize: 48,
                                        fontWeight: FontWeight.w700,
                                        height: 0.9,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'MINUTES',
                                      style: GoogleFonts.lexend(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    ':',
                                    style: GoogleFonts.lexend(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 36,
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                                ),
                                // Seconds
                                Column(
                                  children: [
                                    Text(
                                      seconds.toString().padLeft(2, '0'),
                                      style: GoogleFonts.lexend(
                                        color: Colors.white,
                                        fontSize: 48,
                                        fontWeight: FontWeight.w700,
                                        height: 0.9,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'SECONDS',
                                      style: GoogleFonts.lexend(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withOpacity(0.8),
                                    Colors.white.withOpacity(0.2),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Continue button
                      TweenAnimationBuilder<double>(
                        duration: const Duration(milliseconds: 1200),
                        tween: Tween(begin: 0.0, end: 1.0),
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.scale(
                              scale: 0.8 + 0.2 * value,
                              child: child,
                            ),
                          );
                        },
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(builder: (_) => MyApp()),
                                (route) => false,
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF0A7A4F),
                              padding: const EdgeInsets.symmetric(
                                vertical: 18,
                                horizontal: 32,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 4,
                              shadowColor: Colors.black.withOpacity(0.2),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Continue Orders',
                                  style: GoogleFonts.lexend(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 22,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Thank you message
                      Text(
                        'Thank you for choosing us!',
                        style: GoogleFonts.lexend(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}