import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../bd/bd_login.dart';
import 'otp_auth.dart';

class PhoneNumberAuth extends StatefulWidget {
  const PhoneNumberAuth({super.key});

  @override
  State<PhoneNumberAuth> createState() => _PhoneNumberAuthState();
}

class _PhoneNumberAuthState extends State<PhoneNumberAuth> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneController = TextEditingController();
  bool _acceptedTerms = false;

  bool _sending = false;
  String? _twilioOtpSid;

  Future<void> _startPhoneVerification() async {
    final raw = _phoneController.text.trim();

    // 🧪 DEV MODE: Skip OTP sending (save money, testing only)
    if (!kReleaseMode) {
      debugPrint("🧪 DEV MODE: Skipping Twilio OTP send");

      // still validate user existence + userType
      String userType = "";
      final fs = FirebaseFirestore.instance;

      final driverSnap = await fs
          .collection("QuickRunDrivers")
          .where("phone", isEqualTo: raw)
          .limit(1)
          .get();

      final sellerSnap = await fs
          .collection("Restaurent_shop")
          .where("phone", isEqualTo: raw)
          .limit(1)
          .get();

      if (driverSnap.docs.isEmpty && sellerSnap.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("User doesn't exist")),
        );
        return;
      }

      if (driverSnap.docs.isNotEmpty) {
        userType = "driver";
      } else if (sellerSnap.docs.isNotEmpty) {
        userType = "seller";
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpAuth(
            phone: raw,
            userType: userType,
            staticBypass: true,
          ),
        ),
      );
      return;
    }

    // STATIC LOGIN BYPASS FOR TEST NUMBERS
    if (raw == "" || raw == "7597413791") {
      String userType = "";
      final fs = FirebaseFirestore.instance;

      // Detect user type manually
      final driverSnap = await fs
          .collection("QuickRunDrivers")
          .where("phone", isEqualTo: raw)
          .limit(1)
          .get();

      final sellerSnap = await fs
          .collection("Restaurent_shop")
          .where("phone", isEqualTo: raw)
          .limit(1)
          .get();

      if (driverSnap.docs.isNotEmpty) {
        userType = "driver";
      } else if (sellerSnap.docs.isNotEmpty) {
        userType = "seller";
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("User doesn't exist")),
        );
        return; // ❌ STOP login if no record exists
      }

      // DIRECT LOGIN WITHOUT OTP
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpAuth(
            phone: raw,
            userType: userType,
            staticBypass: true,
          ),
        ),
      );
      return;
    }

    if (raw.length != 10 || int.tryParse(raw) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 10-digit phone number')),
      );
      return;
    }

    final phone = '+91$raw';

    // CHECK IF USER EXISTS IN FIRESTORE
    final fs = FirebaseFirestore.instance;

    // Search in QuickRunDrivers
    final driverSnap = await fs
        .collection("QuickRunDrivers")
        .where("phone", isEqualTo: raw)
        .limit(1)
        .get();

    // Search in Restaurent_shop
    final sellerSnap = await fs
        .collection("Restaurent_shop")
        .where("phone", isEqualTo: raw)
        .limit(1)
        .get();

    if (driverSnap.docs.isEmpty && sellerSnap.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("User doesn't exist")),
      );
      return;
    }

    String userType = "";
    if (driverSnap.docs.isNotEmpty) {
      userType = "driver";
    } else if (sellerSnap.docs.isNotEmpty) {
      userType = "seller";
    }

    setState(() => _sending = true);

    const String accountSid = String.fromEnvironment('TWILIO_ACCOUNT_SID', defaultValue: '');
    const String authToken = String.fromEnvironment('TWILIO_AUTH_TOKEN', defaultValue: '');
    const String serviceSid = String.fromEnvironment('TWILIO_SERVICE_SID', defaultValue: '');

    final uri = Uri.parse(
        'https://verify.twilio.com/v2/Services/$serviceSid/Verifications');

    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Basic ' + base64Encode(utf8.encode('$accountSid:$authToken')),
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      body: {
        'To': phone,
        'Channel': 'sms',
      },
    );

    setState(() => _sending = false);

    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _twilioOtpSid = data["sid"];
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpAuth(
            phone: raw,
            userType: userType,
            staticBypass: false,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OTP send failed: ${response.body}')),
      );
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                const SizedBox(height: 12),
                // Title
                Text(
                  'WELCOME',
                  style: GoogleFonts.kronaOne(
                        color: Colors.black,
                    fontSize: 30
                      ),
                ),
                const SizedBox(height:50),

                // Label
                Text(
                  'Phone number',
                  style: GoogleFonts.kumbhSans(
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                ),
                const SizedBox(height: 12),

                // Phone field
                TextFormField(
                  cursorColor: Colors.black,
                  cursorWidth: 1,
                  cursorHeight: 26,
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  maxLength: 10,
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF4F4F4),
                    hintText: '',
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.black12, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.black87, width: 1.2),
                    ),
                  ),
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isEmpty) return 'Enter phone number';
                    if (value.length != 10 || int.tryParse(value) == null) {
                      return 'Enter a valid 10-digit number';
                    }
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),

                const SizedBox(height: 25),

                // Terms & Conditions
                Row(
                  children: [
                    Checkbox(
                      value: _acceptedTerms,
                      checkColor: Colors.white,
                      activeColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
                    ),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.kumbhSans(color: Colors.black87, fontSize: 13),
                          children: [
                            const TextSpan(text: 'Please accept the '),
                            TextSpan(
                              text: 'Terms & Conditions',
                              style: GoogleFonts.kumbhSans(
                                color: const Color(0xFF1E88E5),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Open Terms & Conditions')),
                                  );
                                },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 36),

                // GET OTP button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_acceptedTerms && _formKey.currentState != null && _formKey.currentState!.validate())
                        ? () {
                            FocusScope.of(context).unfocus();
                            _startPhoneVerification();
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      disabledBackgroundColor: Colors.black26,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _sending
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'GET OTP',
                            style: GoogleFonts.kumbhSans(
                              fontWeight: FontWeight.w400,
                              letterSpacing: 1.2,
                              fontSize: 14,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 20),

                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BdLogin(),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Color(0xFFF4F4F4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'LogIn as business executive',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lexend(
                      color: Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }
}
