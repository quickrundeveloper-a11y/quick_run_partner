import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SellerEarning extends StatefulWidget {
  final String driverAuthId;
  const SellerEarning(this.driverAuthId, {super.key});

  @override
  State<SellerEarning> createState() => _SellerEarningState();
}

class _SellerEarningState extends State<SellerEarning> {
  int selectedTab = 0;
  String currentRestId = "";

  Future<void> _loadCurrentRestId() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('Restaurent_shop').get();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data != null && data['phone'] == widget.driverAuthId) {
          setState(() {
            currentRestId = doc.id;
          });
          print('🍽️ Found currentRestId: $currentRestId for ${widget.driverAuthId}');
          break;
        }
      }
    } catch (e) {
      print('❌ Error loading restaurant id: $e');
    }
  }

  Future<Map<String, dynamic>> _calculateTotals() async {
    if (currentRestId.isEmpty) return {"orders": 0, "earnings": 0};

    int totalOrders = 0;
    int totalEarnings = 0;

    final deliveredSnap = await FirebaseFirestore.instance
        .collection('Restaurent_shop')
        .doc(currentRestId)
        .collection('deliveredItem')
        .get();

    final now = DateTime.now();

    bool isSameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    bool isSameWeek(DateTime a, DateTime b) {
      final diff = a.difference(b).inDays;
      return diff.abs() < 7 && a.weekday >= b.weekday;
    }

    bool isSameMonth(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month;

    for (var dateDoc in deliveredSnap.docs) {
      final data = dateDoc.data();
      final List items = (data["items"] as List?) ?? [];

      final dateString = dateDoc.id; // YYYY-MM-DD
      final parts = dateString.split("-");
      if (parts.length != 3) continue;
      final date = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );

      bool include = false;

      if (selectedTab == 0 && isSameDay(date, now)) include = true;
      if (selectedTab == 1 && isSameWeek(date, now)) include = true;
      if (selectedTab == 2 && isSameMonth(date, now)) include = true;

      if (!include) continue;

      totalOrders += items.length.toInt();

      for (var item in items) {
        if (item["totalAmount"] != null) {
          final amt = item["totalAmount"];
          if (amt is num) totalEarnings += amt.toInt();
        }
      }
    }

    return {"orders": totalOrders, "earnings": totalEarnings};
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentRestId();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.only(top: 40.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  selectedTab = 0;
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 12.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: selectedTab == 0 ? Colors.blue : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(38),
                  ),
                  child: Text(
                    "Today",
                    style: GoogleFonts.lexend(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: selectedTab == 0 ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                setState(() {
                  selectedTab = 1;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: selectedTab == 1 ? Colors.blue : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(38),
                ),
                child: Text(
                  "This Week",
                  style: GoogleFonts.lexend(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: selectedTab == 1 ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                setState(() {
                  selectedTab = 2;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: selectedTab == 2 ? Colors.blue : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(38),
                ),
                child: Text(
                  "This Month",
                  style: GoogleFonts.lexend(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: selectedTab == 2 ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 25),

        FutureBuilder<Map<String, dynamic>>(
          future: _calculateTotals(),
          builder: (context, snapshot) {
            final totalOrders = snapshot.data?["orders"] ?? 0;
            final totalEarnings = snapshot.data?["earnings"] ?? 0;

            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[300]!),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Total Orders",
                              style: GoogleFonts.lexend(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "$totalOrders",
                              style: GoogleFonts.lexend(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 1,
                        height: 45,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Total Earnings",
                              style: GoogleFonts.lexend(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "₹$totalEarnings",
                              style: GoogleFonts.lexend(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    ),
  ),
    );
  }
}
