import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:async/async.dart';
import 'package:qr_flutter/qr_flutter.dart';

class OrderAcceptGrocerry extends StatefulWidget {
  const OrderAcceptGrocerry({super.key});

  @override
  State<OrderAcceptGrocerry> createState() => _OrderAcceptGrocerryState();
}

class _OrderAcceptGrocerryState extends State<OrderAcceptGrocerry> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF1F0F5),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('Customer').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
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
            final customerDocs = snapshot.data!.docs;
            final streams = customerDocs.map((doc) {
              return FirebaseFirestore.instance
                  .collection('Customer')
                  .doc(doc.id)
                  .collection('current_order')
                  .snapshots();
            }).toList();

            return StreamBuilder<List<QuerySnapshot>>(
              stream: StreamZip(streams),
              builder: (context, snapshotOrders) {
                if (snapshotOrders.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshotOrders.hasData) {
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
                final allOrderDocs = snapshotOrders.data!
                    .expand((querySnapshot) => querySnapshot.docs)
                    .toList();

                if (allOrderDocs.isEmpty) {
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

                return ListView.builder(
                  itemCount: allOrderDocs.length,
                  itemBuilder: (context, index) {
                    final data =
                    allOrderDocs[index].data() as Map<String, dynamic>;
                    final address = data['address'] ?? {};
                    final userId = data['userId'] ?? 'N/A';
                    final payment = data['paymentMethod'] ?? {};
                    final List<dynamic> items = data['items'] ?? [];
                    final String currentRestId = FirebaseAuth.instance.currentUser?.uid ?? '';

                    // Check if the restaurant has accepted
                    final bool isRestaurantAccepted = data['restaurentAccpetedId'] != null;

                    return Card(
                      color: Colors.white,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(40),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40.0,horizontal: 20),
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
                                    text: allOrderDocs[index].id.toString().toUpperCase().substring(allOrderDocs[index].id.length - 7),
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
                                    ...items.map((item) {
                                      if (item['restaurentId'] != currentRestId) {
                                        return SizedBox.shrink();
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 8.0),
                                        child: Column(
                                          children: [
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                if (item['image'] != null && item['image'] != "")
                                                  ClipRRect(
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Image.network(
                                                      item['image'],
                                                      height: 110,
                                                      width: 110,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: [
                                                          Text(
                                                            "ITEM NAME",
                                                            style: GoogleFonts.lexend(
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.w400,
                                                              color: Color(0xFF555555),
                                                            ),
                                                          ),
                                                          (item['isVeg'] != null)
                                                              ? Container(
                                                                  height: 20,
                                                                  width: 20,
                                                                  decoration: BoxDecoration(
                                                                    border: Border.all(
                                                                      color: item['isVeg'] == 'veg' ? Colors.green : Colors.red,
                                                                      width: 2,
                                                                    ),
                                                                    borderRadius: BorderRadius.circular(4),
                                                                  ),
                                                                  child: Center(
                                                                    child: Container(
                                                                      height: 10,
                                                                      width: 10,
                                                                      decoration: BoxDecoration(
                                                                        color: item['isVeg'] == 'veg' ? Colors.green : Colors.red,
                                                                        shape: BoxShape.circle,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                )
                                                              : SizedBox(width: 20),
                                                        ],
                                                      ),
                                                      Text(
                                                        item['name'] ?? 'Unknown Item',
                                                        overflow: TextOverflow.ellipsis,
                                                        style: GoogleFonts.lexend(
                                                          fontSize: 19,
                                                          fontWeight: FontWeight.w400,
                                                          color: Colors.black,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 10),
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: [
                                                          Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Text(
                                                                "PRICE",
                                                                style: GoogleFonts.lexend(
                                                                  fontSize: 12,
                                                                  fontWeight: FontWeight.w400,
                                                                  color: Color(0xFF555555),
                                                                ),
                                                              ),
                                                              Text(
                                                                "₹ ${(item['price'] is num) ? item['price'].toInt() : item['price']}",
                                                                style: GoogleFonts.lexend(
                                                                  fontSize: 19,
                                                                  fontWeight: FontWeight.w400,
                                                                  color: Colors.black,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Text(
                                                                "QUANTITY",
                                                                style: GoogleFonts.lexend(
                                                                  fontSize: 12,
                                                                  fontWeight: FontWeight.w400,
                                                                  color: Color(0xFF555555),
                                                                ),
                                                              ),
                                                              Text(
                                                                "${item['quantity']} ${item['unit']}".toUpperCase(),
                                                                style: GoogleFonts.lexend(
                                                                  fontSize: 19,
                                                                  fontWeight: FontWeight.w400,
                                                                  color: Colors.black,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                      // INSERTED QR BLOCK HERE
                                                      const SizedBox(height: 12),
                                                      QrImageView(
                                                        data: "orderId:${allOrderDocs[index].id},productId:${item['productId']}",
                                                        version: QrVersions.auto,
                                                        size: 120,
                                                      ),
                                                      const SizedBox(height: 20),
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
                                    SizedBox.shrink(),
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
    );
  }
}