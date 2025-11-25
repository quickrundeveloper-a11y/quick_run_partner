import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:quick_run_driver/porter_driver/porter_home.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DriverDashboard extends StatefulWidget {
  final String driverAuthId;

  const DriverDashboard(this.driverAuthId, {Key? key}) : super(key: key);

  @override
  _DriverDashboardState createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  bool _isOnline = false;
  int _todayOrders = 0;
  int _todayEarning = 0;
  bool _isOnlineLoaded = false;

  @override
  void initState() {
    super.initState();
    // Driver starts as ONLINE, so offline timer should not run initially.
    _fetchTodayOrders();
    _initOnlineState();
  }

  Future<void> _initOnlineState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool('driverIsOnline');

      bool nextOnline = saved ?? false;

      // If not saved locally yet, fall back to Firestore field `activeDriver`
      if (saved == null) {
        final snap = await FirebaseFirestore.instance
            .collection('QuickRunDrivers')
            .where('phone', isEqualTo: widget.driverAuthId)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final data = snap.docs.first.data();
          final v = data['activeDriver'];
          if (v is bool) nextOnline = v;
        }
      }

      if (!mounted) return;
      setState(() {
        _isOnline = nextOnline;
        _isOnlineLoaded = true;
      });

      // Ensure local prefs is set for future fast restores
      await prefs.setBool('driverIsOnline', nextOnline);

      // Ensure bubble service matches state
      await _applyOnlineState(nextOnline, updateFirestore: false);
    } catch (e) {
      // If anything fails, don't block UI; keep defaults.
      if (!mounted) return;
      setState(() => _isOnlineLoaded = true);
      print('❌ Online init error: $e');
    }
  }

  Future<void> _applyOnlineState(bool online, {required bool updateFirestore}) async {
    // Persist locally
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('driverIsOnline', online);
    } catch (_) {}

    // Update Firestore activeDriver true/false
    if (updateFirestore) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('QuickRunDrivers')
            .where('phone', isEqualTo: widget.driverAuthId)
            .limit(1)
            .get();

        if (snap.docs.isNotEmpty) {
          final driverId = snap.docs.first.id;
          await FirebaseFirestore.instance
              .collection('QuickRunDrivers')
              .doc(driverId)
              .update({"activeDriver": online});
          print("🔥 Firestore updated activeDriver = $online");
        } else {
          print("❌ Driver not found for Firestore update");
        }
      } catch (e) {
        print("❌ Firestore update error: $e");
      }
    }

    // Start/Stop Floating Service (it will hide while app is foreground)
    const platform = MethodChannel('floating.chat.head');
    try {
      if (online) {
        print("🟢 Driver ONLINE → Starting bubble...");
        await platform.invokeMethod("startBubble");
      } else {
        print("🔴 Driver OFFLINE → Stopping bubble...");
        await platform.invokeMethod("stopBubble");
      }
    } catch (e) {
      print("❌ Bubble toggle error: $e");
    }
  }
  Future<void> _fetchTodayOrders() async {
    try {
      final firestore = FirebaseFirestore.instance;

      // find driver doc by phone == driverAuthId
      final snap = await firestore
          .collection('QuickRunDrivers')
          .where('phone', isEqualTo: widget.driverAuthId)
          .get();

      if (snap.docs.isEmpty) {
        setState(() { _todayOrders = 0; _todayEarning = 0; });
        return;
      }

      final driverRef = snap.docs.first.reference;

      // today's date collection name
      final now = DateTime.now();
      final dateString = "${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}";

      final ordersSnap = await driverRef.collection(dateString).get();

      final count = ordersSnap.docs.length;

      setState(() {
        _todayOrders = count;
        _todayEarning = count * 10;
      });
    } catch (e) {
      print('Error: $e');
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isOnlineLoaded) {
      return const Scaffold(
        backgroundColor: Color(0xFFF1F0F5),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: Color(0xFFF1F0F5), // Set the background to dark blue
      appBar: AppBar(
        backgroundColor: Color(0xFFF1F0F5),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () async {
                final next = !_isOnline;
                setState(() => _isOnline = next);
                await _applyOnlineState(next, updateFirestore: true);
                try {
                  Position pos = await Geolocator.getCurrentPosition(
                      desiredAccuracy: LocationAccuracy.high);

                  final lat = pos.latitude;
                  final lng = pos.longitude;

                  final now = DateTime.now();
                  final dateString =
                      "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

                  final snap2 = await FirebaseFirestore.instance
                      .collection("QuickRunDrivers")
                      .where("phone", isEqualTo: widget.driverAuthId)
                      .limit(1)
                      .get();

                  if (snap2.docs.isNotEmpty) {
                    final driverId = snap2.docs.first.id;

                    await FirebaseFirestore.instance
                        .collection("QuickRunDrivers")
                        .doc(driverId)
                        .collection("locationActivity")
                        .doc(dateString)
                        .collection("clicks")
                        .add({
                      "lat": lat,
                      "lng": lng,
                      "status": _isOnline ? "online" : "offline",
                      "clickedAtClient": now.toIso8601String(),
                      "clickedAt": FieldValue.serverTimestamp(),
                    });

                    print("🔥 Saved driver click → $lat , $lng status=$_isOnline");
                  }
                } catch (e) {
                  print("❌ Error saving driver click: $e");
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 145,
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
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
            child: Center(
              child: Text(
                "This app is intended only for registered QuickRun delivery partners.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(


              children: [
                 Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Color(0xFFFFFFFF),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Today's Earning",
                                    style: GoogleFonts.lexend(
                                      fontSize: 20,
                                      color: Color(0xFF7E7E7E),
                                      fontWeight: FontWeight.w600,
                                    )),
                                Text("34 km",
                                    style: GoogleFonts.lexend(
                                      color: Colors.grey[600],
                                      fontSize: 13,
                                    )),
                              ],
                            ),
                            SizedBox(height: 15),

                            Container(height: 1,width: double.infinity,color: Color(0xFFF2F2F2),),
                            SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 18.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("Total Earning",
                                            style: GoogleFonts.lexend(
                                              color: Colors.black,
                                              fontSize: 12,
                                            )),
                                        SizedBox(height: 4),
                                        Text("₹ $_todayEarning",
                                            style: GoogleFonts.lexend(
                                              color: Color(0xFF6E6E6E),
                                              fontSize: 27,
                                              fontWeight: FontWeight.bold,
                                            )),
                                      ],
                                    ),
                                  ),
                                ),
                                SizedBox(width: 60,),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text("Total Orders",
                                          style: GoogleFonts.lexend(
                                            color: Colors.black,
                                            fontSize: 12,
                                          )),
                                      SizedBox(height: 4),
                                      Text("$_todayOrders",
                                          style: GoogleFonts.lexend(
                                            color: Color(0xFF6E6E6E),
                                            fontSize: 27,
                                            fontWeight: FontWeight.bold,
                                          )),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),

                            Container(height: 1,width: double.infinity,color: Color(0xFFF2F2F2),),

                            // SizedBox(height: 4),
                            // Center(
                            //   child: TextButton.icon(
                            //     onPressed: () {},
                            //     label: Text(
                            //       "See Details",
                            //       style: GoogleFonts.lexend(
                            //         color: Colors.black87,
                            //         fontWeight: FontWeight.w500,
                            //       ),
                            //     ),
                            //     icon: Icon(Icons.arrow_forward, size: 16, color: Colors.black87),
                            //
                            //   ),
                            // ),
                          ],
                        ),
                      ),
                      SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            "🎉 You’re doing well. Keep it up !",
                            style: GoogleFonts.lexend(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                    ],
                  ),
              ],
            ),
          ),
          Expanded(child: PorterHome(widget.driverAuthId)),
        ],
      ),
    );
  }
}