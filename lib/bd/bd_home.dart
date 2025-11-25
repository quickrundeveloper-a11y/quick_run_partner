import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'add_retailer.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

class BdHome extends StatefulWidget {
  final String bdId;
  const BdHome(this.bdId, {super.key});

  @override
  State<BdHome> createState() => _BdHomeState();
}

class _BdHomeState extends State<BdHome> {
  final FlutterLocalNotificationsPlugin localNotif = FlutterLocalNotificationsPlugin();

  Position? currentPos;
  bool isOnline = false;
  String? bdName;

  static const platform = MethodChannel('floating.chat.head');

  Future<void> _startBubble() async {
    try {
      await platform.invokeMethod("startBubble");
      print("🟢 BD ONLINE → Starting bubble...");
    } catch (e) {
      print("❌ Error starting bubble: $e");
    }
  }

  Future<void> _stopBubble() async {
    try {
      await platform.invokeMethod("stopBubble");
      print("🔴 BD OFFLINE → Stopping bubble...");
    } catch (e) {
      print("❌ Error stopping bubble: $e");
    }
  }

  Future<void> _loadOnlineStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isOnline = prefs.getBool('bd_online_status') ?? false;
    });
  }

  Future<void> _saveOnlineStatus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bd_online_status', isOnline);
  }

  Future<void> _loadBdName() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('bd_profiles')
          .doc(widget.bdId)
          .get();

      if (doc.exists) {
        setState(() {
          bdName = doc.data()?['name'] ?? 'Business Developer';
        });
      }
    } catch (e) {
      print('❌ Error loading BD name: $e');
    }
  }

  // Pagination state
  final ScrollController _scrollController = ScrollController();
  List<DocumentSnapshot> _retailerRefs = [];
  Map<String, Map<String, dynamic>> _shopCache = {};
  bool _isLoading = false;
  bool _hasMore = true;
  static const int _perPage = 15;

  @override
  void initState() {
    super.initState();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    localNotif.initialize(initSettings);
    _loadOnlineStatus();
    _loadBdName();

    // Pagination listener
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        if (!_isLoading && _hasMore) {
          _loadMoreRetailers();
        }
      }
    });

    // initial load
    _loadInitialRetailers();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialRetailers() async {
    _retailerRefs = [];
    _shopCache.clear();
    _hasMore = true;
    await _loadMoreRetailers();
  }

  Future<void> _loadMoreRetailers() async {
    if (!_hasMore) return;
    _isLoading = true;
    setState(() {});

    try {
      Query q = FirebaseFirestore.instance
          .collection('bd_profiles')
          .doc(widget.bdId)
          .collection('registered_retailers')
          .orderBy('created_at', descending: true)
          .limit(_perPage);

      if (_retailerRefs.isNotEmpty) {
        q = q.startAfterDocument(_retailerRefs.last);
      }

      final snap = await q.get();
      final docs = snap.docs;

      if (docs.isEmpty) {
        _hasMore = false;
      } else {
        _retailerRefs.addAll(docs);

        // Batch fetch shop details
        final idsToFetch = docs
            .map((d) => d['retailer_doc_id'] as String)
            .where((id) => !_shopCache.containsKey(id))
            .toList();

        if (idsToFetch.isNotEmpty) {
          final batch = FirebaseFirestore.instance.batch();
          final shopRefs = idsToFetch
              .map((id) => FirebaseFirestore.instance
              .collection('Restaurent_shop')
              .doc(id))
              .toList();

          final results = await Future.wait(
            shopRefs.map((ref) => ref.get()),
          );

          for (final result in results) {
            if (result.exists) {
              _shopCache[result.id] = result.data()!;
            }
          }
        }

        if (docs.length < _perPage) {
          _hasMore = false;
        }
      }
    } catch (e) {
      print('❌ Error loading retailers: $e');
    }

    _isLoading = false;
    setState(() {});
  }

  Future<void> _toggleOnlineStatus() async {
    final newStatus = !isOnline;
    setState(() {
      isOnline = newStatus;
    });

    await _saveOnlineStatus();

    if (isOnline) {
      await _startBubble();
      _showOnlineNotification();
    } else {
      await _stopBubble();
      _showOfflineNotification();
    }

    // Update Firestore
    try {
      await FirebaseFirestore.instance
          .collection("bd_profiles")
          .doc(widget.bdId)
          .update({"activeBD": isOnline});
    } catch (e) {
      print("❌ Error updating activeBD: $e");
    }

    // Save location activity
    try {
      Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final lat = pos.latitude;
      final lng = pos.longitude;

      final now = DateTime.now();
      final dateString =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      await FirebaseFirestore.instance
          .collection('bd_profiles')
          .doc(widget.bdId)
          .collection('locationActivity')
          .doc(dateString)
          .collection('clicks')
          .add({
        'lat': lat,
        'lng': lng,
        'status': isOnline ? 'online' : 'offline',
        'clickedAtClient': now.toIso8601String(),
        'clickedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('❌ Error saving location click: $e');
    }
  }

  Future<void> _showOnlineNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'bd_status_channel',
      'BD Status',
      importance: Importance.high,
      priority: Priority.high,
    );
    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

    await localNotif.show(
      0,
      'You are now online',
      'You will receive messages from retailers',
      platformChannelSpecifics,
    );
  }

  Future<void> _showOfflineNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'bd_status_channel',
      'BD Status',
      importance: Importance.high,
      priority: Priority.high,
    );
    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

    await localNotif.show(
      1,
      'You are now offline',
      'You will not receive new messages',
      platformChannelSpecifics,
    );
  }

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateDay = DateTime(date.year, date.month, date.day);

    if (dateDay == today) {
      return 'Today, ${_formatTime(date)}';
    } else if (dateDay == yesterday) {
      return 'Yesterday, ${_formatTime(date)}';
    } else {
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${date.day} ${months[date.month - 1]} ${date.year}';
    }
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildStatusIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isOnline ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOnline ? Colors.green : Colors.red,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isOnline ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isOnline ? 'Online' : 'Offline',
            style: GoogleFonts.lexend(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isOnline ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRetailerCard(int index, DocumentSnapshot retailerRef, Map<String, dynamic> data) {
    final createdAt = data['created_at'] as Timestamp?;
    final shopName = data['name'] ?? 'No Name';
    final ownerName = data['owner_name'] ?? 'N/A';
    final phone = data['phone'] ?? 'N/A';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // Handle retailer tap - could navigate to details page
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _getColorFromIndex(index).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          (index + 1).toString(),
                          style: GoogleFonts.lexend(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _getColorFromIndex(index),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shopName,
                            style: GoogleFonts.lexend(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Owner: $ownerName',
                            style: GoogleFonts.lexend(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: Colors.grey[200]),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildInfoItem(Icons.phone, phone),
                    const SizedBox(width: 16),
                    _buildInfoItem(
                      Icons.calendar_today,
                      createdAt != null ? _formatDate(createdAt) : 'N/A',
                    ),
                  ],
                ),
                if (data['address'] != null && data['address'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 16,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            data['address'].toString(),
                            style: GoogleFonts.lexend(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String text) {
    return Expanded(
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: Colors.grey[500],
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.lexend(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Color _getColorFromIndex(int index) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
    ];
    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome',
              style: GoogleFonts.lexend(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            Text(
              bdName ?? 'Business Developer',
              style: GoogleFonts.lexend(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _buildStatusIndicator(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Colors.grey[200],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddRetailer(widget.bdId),
            ),
          );
        },
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add, size: 20),
        label: Text(
          'Add Retailer',
          style: GoogleFonts.lexend(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          // Header with stats and toggle
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Retailers',
                          style: GoogleFonts.lexend(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          ((_retailerRefs.length - 1).clamp(0, 999999)).toString(),
                          style: GoogleFonts.lexend(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Status',
                          style: GoogleFonts.lexend(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        GestureDetector(
                          onTap: _toggleOnlineStatus,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 80,
                            height: 40,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(25),
                              color: isOnline ? Colors.green : Colors.grey[300],
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Stack(
                              children: [
                                AnimatedAlign(
                                  duration: const Duration(milliseconds: 300),
                                  alignment: isOnline
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    child: Container(
                                      width: 38,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withOpacity(0.2),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                    children: [
                                      Icon(
                                        Icons.power_settings_new,
                                        size: 16,
                                        color: isOnline
                                            ? Colors.white
                                            : Colors.grey[500],
                                      ),
                                      Icon(
                                        Icons.power_settings_new,
                                        size: 16,
                                        color: isOnline
                                            ? Colors.grey[500]
                                            : Colors.white,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  isOnline
                      ? 'You are online and ready to receive messages'
                      : 'Go online to start receiving messages',
                  style: GoogleFonts.lexend(
                    fontSize: 12,
                    color: isOnline ? Colors.green : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // Retailers List
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshAll,
              backgroundColor: Colors.white,
              color: Colors.black,
              child: _retailerRefs.isEmpty && _isLoading
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.black),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading retailers...',
                      style: GoogleFonts.lexend(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              )
                  : _retailerRefs.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.storefront_outlined,
                      size: 80,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No retailers yet',
                      style: GoogleFonts.lexend(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap the + button to add your first retailer',
                      style: GoogleFonts.lexend(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _retailerRefs.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _retailerRefs.length) {
                    return _hasMore
                        ? Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 20),
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                          AlwaysStoppedAnimation<Color>(
                              Colors.grey[400]!),
                        ),
                      ),
                    )
                        : Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 20),
                      child: Center(
                        child: Text(
                          'No more retailers',
                          style: GoogleFonts.lexend(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  }

                  final retailerRef = _retailerRefs[index];
                  final retailerDocId =
                  retailerRef['retailer_doc_id'] as String;
                  final data = _shopCache[retailerDocId];

                  if (data == null) {
                    // Show skeleton loader while fetching
                    return _buildSkeletonLoader(index);
                  }

                  return _buildRetailerCard(index, retailerRef, data);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoader(int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 16,
                      color: Colors.grey[200],
                      margin: const EdgeInsets.only(bottom: 8),
                    ),
                    Container(
                      width: 120,
                      height: 12,
                      color: Colors.grey[200],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: Colors.grey[200]),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      color: Colors.grey[200],
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 80,
                      height: 12,
                      color: Colors.grey[200],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      color: Colors.grey[200],
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 80,
                      height: 12,
                      color: Colors.grey[200],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _refreshAll() async {
    _retailerRefs = [];
    _shopCache.clear();
    _hasMore = true;
    await _loadBdName();
    await _loadInitialRetailers();
  }
}