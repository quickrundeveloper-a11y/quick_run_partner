import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DriverOnline extends StatefulWidget {
  final String? driverAuthId;
  const DriverOnline(this.driverAuthId, {super.key});

  @override
  State<DriverOnline> createState() => _DriverOnlineState();
}

class _DriverOnlineState extends State<DriverOnline> {
  static const platform = MethodChannel('floating.chat.head');
  static const locationChannel = MethodChannel('bubble_location');

  double? currentLat;
  double? currentLng;

  void _listenToBubbleLocation() {
    locationChannel.setMethodCallHandler((call) async {
      if (call.method == "locationUpdate") {
        final data = Map<String, dynamic>.from(call.arguments);
        final lat = data["lat"];
        final lng = data["lng"];
        debugPrint("🔥 Parsed bubble data → $data");
        debugPrint("📍 Bubble Location → $lat , $lng");

        setState(() {
          currentLat = lat;
          currentLng = lng;
        });

        if (widget.driverAuthId != null && lat != null && lng != null) {
          FirebaseFirestore.instance
              .collection("QuickRunDrivers")
              .where("phone", isEqualTo: widget.driverAuthId)
              .limit(1)
              .get()
              .then((snapshot) {
            if (snapshot.docs.isNotEmpty) {
              final docId = snapshot.docs.first.id;
              FirebaseFirestore.instance
                  .collection("QuickRunDrivers")
                  .doc(docId)
                  .collection("bubbleTestActivity")
                  .add({
                "lat": lat,
                "lng": lng,
                "time": FieldValue.serverTimestamp(),
              });
            }
          });
        }
      }
      return null;
    });
  }

  @override
  void initState() {
    super.initState();
    _listenToBubbleLocation();
  }

  Future<void> _startBubble() async {
    try {
      await platform.invokeMethod("startBubble");
    } catch (e, stack) {
      debugPrint("❌ Error starting bubble: $e");
      debugPrint("STACKTRACE: $stack");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Row(
              children: const [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 8),
                Text("Bubble start failed!", style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        );
      }
    }
  }

  Future<void> _stopBubble() async {
    try {
      await platform.invokeMethod("stopBubble");
    } catch (e, stack) {
      debugPrint("❌ Error stopping bubble: $e");
      debugPrint("STACKTRACE: $stack");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Row(
              children: const [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 8),
                Text("Bubble stop failed!", style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Driver Onlin"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Driver ID: ${widget.driverAuthId ?? 'NULL'}",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "Lat: ${currentLat?.toStringAsFixed(6) ?? '--'}",
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              "Lng: ${currentLng?.toStringAsFixed(6) ?? '--'}",
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _startBubble,
              child: const Text("Start Floating Bubble"),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _stopBubble,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("Stop Floating Bubble"),
            ),
          ],
        ),
      ),
    );
  }
}