import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Core imports for background functionality
import 'package:firebase_messaging/firebase_messaging.dart';
import 'login/phone_number_auth.dart';
import 'choose_service.dart'; // Assumed to lead to driver functionalities
import 'package:shared_preferences/shared_preferences.dart';
import 'bd/bd_home.dart';

// --- FIREBASE OPTIONS (Centralized for main and background handler) ---
const firebaseOptions = FirebaseOptions(
  apiKey: "AIzaSyBTbJpF4hcn5YqWtoLyPorBP3RVFwHn7Zg",
  appId: "1:668265951981:android:a3c0b3d3a779c896e852e4",
  messagingSenderId: "668265951981",
  storageBucket: "quick-run-c74ff.firebasestorage.app",
  projectId: "quick-run-c74ff",
);

// Function to handle fetching and saving the FCM token
Future<void> _initMessagingAndSaveToken(String driverId) async {
  final fcm = FirebaseMessaging.instance;
  // Request FCM permissions
  await fcm.requestPermission();
  final fcmToken = await fcm.getToken();

  if (fcmToken != null) {
    debugPrint("FCM Token: $fcmToken");
    // Save this token to the 'Drivers' collection for the Cloud Function to use
    await FirebaseFirestore.instance.collection('Drivers').doc(driverId).set({
      'fcmToken': fcmToken,
      'lastActive': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

// Function to request the crucial overlay permission
Future<void> _requestOverlayPermission() async {
  // Overlay permission request removed as FlutterOverlayWindowPlus is removed
}

// --- MAIN ENTRY POINT ---

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Initialize Firebase once
    await Firebase.initializeApp(options: firebaseOptions);
  } catch (e, st) {
    debugPrint('Firebase init failed: $e');
    debugPrintStack(stackTrace: st);
  }

  // Removed background message handler registration
  // FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Request required system permissions
  final status = await Permission.locationWhenInUse.request();
  if (!status.isGranted) {
    debugPrint('⚠️ Location permission not granted. Some features may not work properly.');
  }

  final cameraStatus = await Permission.camera.request();
  if (!cameraStatus.isGranted) {
    debugPrint('⚠️ Camera permission not granted. QR code scanning may not work.');
  }

  // Removed overlay permission request

  runApp(const MyApp());
}

// --- APP WIDGETS ---

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
          final bdId = prefs.getString("bdId");

          if (bdId != null && bdId.isNotEmpty) {
            return BdHome(bdId);
          }
          return const AuthGate();
        },
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Waiting for Firebase to give us the current auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // If logged in -> initialize FCM token and proceed
        if (snapshot.hasData) {
          // Use the initializer to ensure FCM token is saved before navigating
          return PostAuthInitializer(userId: snapshot.data!.uid);
        }

        // Not logged in -> go to PhoneNumberAuth
        return const PhoneNumberAuth();
      },
    );
  }
}

// New widget to handle post-login initialization tasks (FCM token saving)
class PostAuthInitializer extends StatefulWidget {
  final String userId;
  const PostAuthInitializer({required this.userId, super.key});

  @override
  State<PostAuthInitializer> createState() => _PostAuthInitializerState();
}

class _PostAuthInitializerState extends State<PostAuthInitializer> {
  late Future<void> _initializationFuture;

  @override
  void initState() {
    super.initState();
    // Start the FCM token saving process right after authentication
    _initializationFuture = _initMessagingAndSaveToken(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initializationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Show a spinner while saving the FCM token
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Once FCM token is saved, proceed to the main app screen
        return const ChooseService();
      },
    );
  }
}