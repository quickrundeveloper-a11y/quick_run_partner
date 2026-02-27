import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:quick_run_driver/bd/bd_home.dart';
import 'package:quick_run_driver/login/phone_number_auth.dart';
import 'package:quick_run_driver/notifications/pending_order.dart';
import 'package:quick_run_driver/porter_driver/driver_dashboard.dart';
import 'package:quick_run_driver/seller_bottomnav.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quick_run_driver/eat/eat_login.dart';
import 'package:quick_run_driver/eat/driver_home.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

// IMPORTANT: Android 8+ notification sound is controlled by the CHANNEL.
// Changing the sound requires a new channel id (or uninstall).
const AndroidNotificationChannel _orderChannel = AndroidNotificationChannel(
  'new_order_channel_v2',
  'New Orders',
  description: 'Incoming order alerts',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
  showBadge: true,
);

bool _orderChannelCreated = false;

/// Extract `orderId` from a data message.
/// We intentionally support both `orderId` and `order_id` to be resilient
/// across backend implementations.
String? _extractOrderIdFromData(Map<String, dynamic> data) {
  final v = data['orderId'] ?? data['order_id'];
  final s = v?.toString().trim();
  if (s == null || s.isEmpty) return null;
  return s;
}

Future<void> _ensureOrderChannelCreated() async {
  // Required: Android notification channels must exist before showing
  // notifications on Android 8.0+.
  // We guard this to avoid repeatedly re-creating the channel.
  if (_orderChannelCreated) return;
  final androidPlatform =
      _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  // Ensure the custom sound is applied on Android 8+:
  // recreate the channel (or new id) with the desired sound.
  const newChannel = AndroidNotificationChannel(
    'new_order_channel_v2',
    'New Orders',
    description: 'Incoming order alerts',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
    sound: RawResourceAndroidNotificationSound('order_notification'),
  );
  await androidPlatform?.createNotificationChannel(newChannel);
  _orderChannelCreated = true;
  debugPrint('[NOTIF] Created Android channel: ${newChannel.id}');
}

Future<void> _showNewOrderNotification({
  required String title,
  required String body,
  required String orderId,
}) async {
  await _ensureOrderChannelCreated();
  debugPrint('[FCM] NEW_ORDER received | orderId=$orderId');
  debugPrint('[NOTIF] Showing NEW ORDER notification. orderId=$orderId title="$title" body="$body"');

  // Use the same channel everywhere; only the payload changes.
  const androidDetails = AndroidNotificationDetails(
    'new_order_channel_v2',
    'New Orders',
    channelDescription: 'Incoming order alerts',
    importance: Importance.max,
    priority: Priority.max,
    // Category "call" + fullScreenIntent helps Android treat this as
    // urgent (heads-up / full-screen where allowed).
    category: AndroidNotificationCategory.call,
    fullScreenIntent: true,
    visibility: NotificationVisibility.public,
    ticker: 'New order',
    playSound: true,
    // Use custom sound from Android res/raw/order_notification.mp3
    sound: RawResourceAndroidNotificationSound('order_notification'),
    enableVibration: true,
    ongoing: false,
    autoCancel: true,
  );
  const details = NotificationDetails(android: androidDetails);

  await _localNotifications.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    details,
    // Production-safe: keep payload tiny + stable.
    // We only pass orderId (not data.toString()) to avoid parsing issues.
    payload: orderId,
  );
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Required: background handler runs in a separate isolate.
  // Using Firebase.initializeApp() (no explicit options) is the most stable
  // approach here and avoids isolate crashes from mismatched options.
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Ignore: can already be initialized.
  }

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await _localNotifications.initialize(initSettings);

  final data = message.data;
  debugPrint('[NOTIF][BG] Message received. messageId=${message.messageId} data=$data');
  final type = (data['type'] ?? '').toString().toUpperCase();
  final orderId = _extractOrderIdFromData(data);
  final isOrder = type == 'NEW_ORDER' || orderId != null;
  if (!isOrder) {
    debugPrint('[NOTIF][BG] Ignored (not an order). type="$type" orderId=$orderId');
    return;
  }
  if (orderId == null) {
    debugPrint('[NOTIF][BG] Ignored (missing orderId). type="$type" data=$data');
    return;
  }

  // Extra debug: print session info if available (helps confirm seller vs driver).
  try {
    final prefs = await SharedPreferences.getInstance();
    final userType = prefs.getString('userType');
    final driverAuthId = prefs.getString('driverAuthID');
    debugPrint('[NOTIF][BG] NEW_ORDER confirmed. userType=$userType driverAuthID=$driverAuthId orderId=$orderId');
  } catch (e) {
    debugPrint('[NOTIF][BG] Could not read SharedPreferences: $e');
  }

  final title = (data['title'] ?? message.notification?.title ?? 'New Order')
      .toString();
  final body = (data['body'] ??
          message.notification?.body ??
          'You have a new order request')
      .toString();
  await _showNewOrderNotification(title: title, body: body, orderId: orderId);
  debugPrint('[NOTIF][BG] NEW_ORDER local notification shown for orderId=$orderId');
}

/// TOP-LEVEL background registration (Firebase requirement for Android):
/// Dart doesn't allow a bare statement at top-level, so we register via a
/// top-level initializer. This ensures the handler is registered before `main`
/// runs and before any isolates are spawned for background delivery.
// ignore: unused_element
final int _firebaseBackgroundHandlerRegistration = (() {
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  return 1;
})();

Future<void> _navigateForOrderTap({required String? orderId}) async {
  // We keep navigation logic minimal and do NOT change UI/business logic.
  // Open the correct home based on current session userType.
  final prefs = await SharedPreferences.getInstance();
  final driverAuthId = prefs.getString("driverAuthID");
  final userType = prefs.getString("userType");
  debugPrint('[NOTIF] Tap received. orderId=$orderId driverAuthID=$driverAuthId userType=$userType');

  // Store pending orderId so the driver UI can immediately show the order popup
  // once it has data (Flutter cannot show UI while app is background).
  PendingOrder.set(orderId);

  if (driverAuthId == null || driverAuthId.isEmpty) {
    debugPrint('[NOTIF] Not navigating (missing session).');
    return;
  }

  if (userType == "driver") {
    debugPrint('[NOTIF] Navigating to DriverDashboard($driverAuthId)');
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => DriverDashboard(driverAuthId)),
      (route) => false,
    );
    return;
  }

  if (userType == "seller") {
    debugPrint('[NOTIF] Navigating to SellerBottomnav($driverAuthId)');
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => SellerBottomnav(driverAuthId)),
      (route) => false,
    );
    return;
  }

  debugPrint('[NOTIF] Not navigating (unknown userType="$userType").');
}

Future<void> _onNotificationTap(NotificationResponse response) async {
  // Payload is a plain `orderId` string (or null).
  final orderId = response.payload?.toString().trim();
  debugPrint('[NOTIF] Local notification tapped. payload(orderId)="$orderId"');
  await _navigateForOrderTap(orderId: (orderId?.isEmpty ?? true) ? null : orderId);
}

Future<void> _initNotifications() async {
  final fcmPerm = await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
  );
  debugPrint('[NOTIF] FCM permission status: ${fcmPerm.authorizationStatus}');

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await _localNotifications.initialize(
    initSettings,
    onDidReceiveNotificationResponse: _onNotificationTap,
    onDidReceiveBackgroundNotificationResponse: _onNotificationTap,
  );

  await _ensureOrderChannelCreated();

  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    final data = message.data;
    debugPrint('[NOTIF][FG] Message received. messageId=${message.messageId} data=$data');
    final type = (data['type'] ?? '').toString().toUpperCase();
    final orderId = _extractOrderIdFromData(data);
    final isOrder = type == 'NEW_ORDER' || orderId != null;
    if (!isOrder) {
      debugPrint('[NOTIF][FG] Ignored (not an order). type="$type" orderId=$orderId');
      return;
    }
    if (orderId == null) {
      debugPrint('[NOTIF][FG] Ignored (missing orderId). type="$type" data=$data');
      return;
    }

    final title =
        (data['title'] ?? message.notification?.title ?? 'New Order').toString();
    final body = (data['body'] ??
            message.notification?.body ??
            'You have a new order request')
        .toString();
    await _showNewOrderNotification(title: title, body: body, orderId: orderId);
  });

  // When user taps an FCM notification and the app opens from background.
  // IMPORTANT: Use the *real message* to extract orderId. No fake responses.
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
    final orderId = _extractOrderIdFromData(message.data);
    debugPrint('[NOTIF] onMessageOpenedApp fired. orderId=$orderId data=${message.data}');
    PendingOrder.set(orderId);
    await _navigateForOrderTap(orderId: orderId);
  });

  // Terminated -> opened by notification tap.
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    final orderId = _extractOrderIdFromData(initialMessage.data);
    debugPrint('[NOTIF] getInitialMessage found. orderId=$orderId data=${initialMessage.data}');
    PendingOrder.set(orderId);
    await _navigateForOrderTap(orderId: orderId);
  } else {
    debugPrint('[NOTIF] getInitialMessage: null');
  }

  final token = await FirebaseMessaging.instance.getToken();
  debugPrint('[NOTIF] FCM token (device): $token');
}



const firebaseOptions = FirebaseOptions(
  apiKey: "AIzaSyDWfC0Wn4ClqHeFuHaW5yGi5fdcCY61Drs",
  appId: "1:802086575104:android:b73cdb49cfa338f5758ce5",
  messagingSenderId: "802086575104",
  storageBucket: "quickrun-eat.firebasestorage.app",
  projectId: "quickrun-eat",
);


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };

  try {
    // Initialize Firebase once
    await Firebase.initializeApp(options: firebaseOptions);
  } catch (e, st) {
    debugPrint('Firebase init failed: $e');
    debugPrintStack(stackTrace: st);
  }

  try {
    await _initNotifications();
  } catch (e, st) {
    debugPrint('Notification init failed: $e');
    debugPrintStack(stackTrace: st);
  }


  final status = await Permission.locationWhenInUse.request();
  if (!status.isGranted) {
    debugPrint('⚠️ Location permission not granted. Some features may not work properly.');
  }

  final cameraStatus = await Permission.camera.request();
  if (!cameraStatus.isGranted) {
    debugPrint('⚠️ Camera permission not granted. QR code scanning may not work.');
  }

  final notifStatus = await Permission.notification.request();
  if (!notifStatus.isGranted) {
    debugPrint("⚠️ Notification permission not granted. Foreground service notification may not show.");
  }

  try {
    final currentAlwaysStatus = await Permission.locationAlways.status;

    if (!currentAlwaysStatus.isGranted) {
      final requested = await Permission.locationAlways.request();

      if (!requested.isGranted) {
        debugPrint("⚠️ Please enable 'Allow all the time' manually in settings.");
      }
    }
  } catch (e) {
    debugPrint("❌ Always Location request failed: $e");
  }


  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: FutureBuilder(
        future: SharedPreferences.getInstance(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final prefs = snap.data!;
          final loggedInDriverId = prefs.getString("driverAuthID");

          if (loggedInDriverId != null && loggedInDriverId.isNotEmpty) {
            // Refresh driver ID in SharedPreferences on every app open
             prefs.setString("driverAuthID", loggedInDriverId);
          }
          final bdId = prefs.getString("bdId");
          if (bdId != null && bdId.isNotEmpty) {
            // Save userType as BD Executive
            prefs.setString("userType", "BD_executive");
            print("BD DEBUG → userType = BD_executive");
            print("BD DEBUG → userType = BD_executive");
            print("BD DEBUG → userType = BD_executive");
            print("BD DEBUG → userType = BD_executive");
            print("BD DEBUG → userType = BD_executive");
            print("BDwq  DEBUG → userType = BD_executive");

            // Debug print to show bdId every time
            print("BD DEBUG → bdId = $bdId");

            return BdHome(bdId);
          }
          final driverAuthId = prefs.getString("driverAuthID");
          final userType = prefs.getString("userType");
          final isLoggedInEat = prefs.getBool('is_logged_in') ?? false;

          print("MAIN DEBUG → driverAuthId = $driverAuthId | userType = $userType | eatLoggedIn = $isLoggedInEat");
          
          if (isLoggedInEat) {
            return const DriverHome();
          }

          if (driverAuthId != null && driverAuthId.isNotEmpty && userType != null) {
            if (userType == "driver") return DriverDashboard(driverAuthId);
            if (userType == "seller") return SellerBottomnav(driverAuthId);
          }
          return const EatLoginPage();
        },
      ),
    );
  }
}
