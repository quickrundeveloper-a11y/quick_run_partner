import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:characters/characters.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../porter_driver/driver_dashboard.dart';
import '../seller_bottomnav.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';


class OtpAuth extends StatefulWidget {
  final String? phone; // optional phone to display like +91 928478743
  final String userType;
  final bool staticBypass;
  const OtpAuth({super.key, this.phone, required this.userType, required this.staticBypass});

  @override
  State<OtpAuth> createState() => _OtpAuthState();
}

class _OtpAuthState extends State<OtpAuth> {
  static const String twilioAccountSID = String.fromEnvironment('TWILIO_ACCOUNT_SID', defaultValue: '');
  static const String twilioAuthToken = String.fromEnvironment('TWILIO_AUTH_TOKEN', defaultValue: '');
  static const String twilioServiceID = String.fromEnvironment('TWILIO_SERVICE_SID', defaultValue: '');
  final _formKey = GlobalKey<FormState>();
  final int _otpLength = 6;
  late final List<TextEditingController> _controllers;
  late final FocusNode _inputFocus;
  final ValueNotifier<bool> _isOtpComplete = ValueNotifier(false);
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _inputFocus = FocusNode();
    _controllers = List.generate(_otpLength, (_) => TextEditingController());
  }

  @override
  void dispose() {
    _inputFocus.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  // Helper getter to combine all controller values
  String get _otpValue => _controllers.map((c) => c.text).join();

  void _updateControllers(String value) {
    final chars = value.characters.toList();
    for (int i = 0; i < _otpLength; i++) {
      if (i < chars.length) {
        _controllers[i].text = chars[i];
      } else {
        _controllers[i].clear();
      }
    }
    _isOtpComplete.value = _controllers.every((c) => c.text.isNotEmpty);
    // Keep the keyboard always open
    if (!_inputFocus.hasFocus) {
      Future.delayed(Duration(milliseconds: 100), () {
        if (mounted) _inputFocus.requestFocus();
      });
    }
  }

  Widget _buildOtpBox(int index) {
    final digit = _controllers[index].text;
    return Padding(
      padding: const EdgeInsets.all(3.0),
      child: GestureDetector(
        onTap: () {
          if (!_inputFocus.hasFocus) {
            Future.delayed(Duration(milliseconds: 50), () {
              if (mounted) {
                _inputFocus.requestFocus();
                SystemChannels.textInput.invokeMethod('TextInput.show');
              }
            });
          } else {
            SystemChannels.textInput.invokeMethod('TextInput.show');
          }
        },
        child: Container(
          width: 50,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF4F4F4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: digit.isNotEmpty ? Colors.black87 : Colors.black12,
              width: digit.isNotEmpty ? 1.2 : 1,
            ),
          ),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controllers[index],
            builder: (context, value, _) => Text(
              value.text,
              style: GoogleFonts.kumbhSans(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onLogin() async {
    FocusScope.of(context).unfocus();

    // 🧪 DEV MODE: Skip OTP verification (save money during development)
    if (!kReleaseMode) {
      if (_otpValue.isEmpty) {
        // auto-fill dummy OTP in dev
        for (final c in _controllers) {
          c.text = '1';
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('driverAuthID', widget.phone ?? '');
      await prefs.setString('userType', widget.userType);

      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await FirebaseFirestore.instance
            .collection('retailers')
            .doc(widget.phone)
            .set({'fcmId': fcmToken}, SetOptions(merge: true));
      }

      if (!mounted) return;
      if (widget.userType == "driver") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => DriverDashboard(widget.phone ?? "")),
        );
      } else if (widget.userType == "seller") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => SellerBottomnav(widget.phone ?? "")),
        );
      }
      return;
    }

    // STATIC OTP BYPASS (always 123456)
    if (widget.staticBypass == true) {
      if (_otpValue != "123456") {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter static OTP: 123456')),
        );
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('driverAuthID', widget.phone ?? '');
      await prefs.setString('userType', widget.userType);

      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        // Update in retailers/{phone}
        await FirebaseFirestore.instance
            .collection('retailers')
            .doc(widget.phone)
            .set({'fcmId': fcmToken}, SetOptions(merge: true));

        // OPTION A — Find driver doc by phone, update if exists
        final allDriversSnap = await FirebaseFirestore.instance
            .collection('QuickRunDrivers')
            .get();

        String? matchedDriverDocId;

        for (var doc in allDriversSnap.docs) {
          final data = doc.data();
          if (data != null && data['phone'] == widget.phone) {
            matchedDriverDocId = doc.id;
            break;
          }
        }

        if (matchedDriverDocId != null) {
          await FirebaseFirestore.instance
              .collection('QuickRunDrivers')
              .doc(matchedDriverDocId)
              .set({'fcmId': fcmToken}, SetOptions(merge: true));
        } else {
          print("❌ No driver doc found matching phone ${widget.phone}. No FCM saved.");
        }

        /* Update in Restaurent_shop/{restaurantDocId} where phone matches */
        final rQ = await FirebaseFirestore.instance
            .collection('Restaurent_shop')
            .where('phone', isEqualTo: widget.phone)
            .limit(1)
            .get();

        if (rQ.docs.isNotEmpty) {
          final restDocId = rQ.docs.first.id;
          await FirebaseFirestore.instance
              .collection('Restaurent_shop')
              .doc(restDocId)
              .set({'fcmId': fcmToken}, SetOptions(merge: true));
        } else {
          print("❌ No restaurant found matching phone ${widget.phone}. Not creating account.");
        }
      }

      if (!mounted) return;
      if (widget.userType == "driver") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => DriverDashboard(widget.phone ?? "")),
        );
      } else if (widget.userType == "seller") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => SellerBottomnav(widget.phone ?? "")),
        );
      }
      return;
    }

    if (_otpValue.length != _otpLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the 6-digit OTP')),
      );
      return;
    }

    setState(() => _verifying = true);

    try {
      final url = Uri.parse(
        "https://verify.twilio.com/v2/Services/$twilioServiceID/VerificationCheck"
      );

      final response = await http.post(
        url,
        headers: {
          "Authorization": "Basic ${base64Encode(utf8.encode('$twilioAccountSID:$twilioAuthToken'))}",
        },
        body: {
          "To": "+91${widget.phone}",
          "Code": _otpValue,
        },
      );

      final data = jsonDecode(response.body);

      if (data["status"] == "approved") {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('driverAuthID', widget.phone ?? '');
        await prefs.setString('userType', widget.userType);

        final fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null) {
          await FirebaseFirestore.instance
              .collection('retailers')
              .doc(widget.phone)
              .set({'fcmId': fcmToken}, SetOptions(merge: true));

          final allDriversSnap = await FirebaseFirestore.instance
              .collection('QuickRunDrivers')
              .get();

          String? matchedDriverDocId;

          for (var doc in allDriversSnap.docs) {
            final data = doc.data();
            if (data != null && data['phone'] == widget.phone) {
              matchedDriverDocId = doc.id;
              break;
            }
          }

          if (matchedDriverDocId != null) {
            await FirebaseFirestore.instance
                .collection('QuickRunDrivers')
                .doc(matchedDriverDocId)
                .set({'fcmId': fcmToken}, SetOptions(merge: true));
          } else {
            print("❌ No driver doc found matching phone ${widget.phone}. No FCM saved.");
          }

          /* Update in Restaurent_shop/{restaurantDocId} where phone matches */
          final rQ = await FirebaseFirestore.instance
              .collection('Restaurent_shop')
              .where('phone', isEqualTo: widget.phone)
              .limit(1)
              .get();

          if (rQ.docs.isNotEmpty) {
            final restDocId = rQ.docs.first.id;
            await FirebaseFirestore.instance
                .collection('Restaurent_shop')
                .doc(restDocId)
                .set({'fcmId': fcmToken}, SetOptions(merge: true));
          } else {
            print("❌ No restaurant found matching phone ${widget.phone}. Not creating account.");
          }
        }

        if (!mounted) return;
        if (widget.userType == "driver") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => DriverDashboard(widget.phone ?? "")),
          );
        } else if (widget.userType == "seller") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => SellerBottomnav(widget.phone ?? "")),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Unknown user type")),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("OTP verification failed")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error verifying OTP: $e")),
      );
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final phoneText = widget.phone != null && widget.phone!.isNotEmpty
        ? widget.phone!
        : '928478743';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Text(
                  'ENTER OTP',
                  style: GoogleFonts.kronaOne(color: Colors.black, fontSize: 32, letterSpacing: 3),
                ),
                const SizedBox(height: 55),
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.kumbhSans(color: Colors.black, fontSize: 14),
                    children: [
                      const TextSpan(text: 'Enter the OTP sent to '),
                      TextSpan(
                        text: '+91 $phoneText',
                        style: GoogleFonts.kumbhSans(
                          fontSize: 14,
                          color: const Color(0xFF1E88E5),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 25),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_otpLength, _buildOtpBox),
                ),
                const SizedBox(height: 120), // space before bottom button
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: EdgeInsets.only(
          left: 24,
          right: 24,
          // Adjust bottom padding based on keyboard visibility
          bottom: insets > 0 ? 16 + insets : 24,
        ),
        child: SizedBox(
          height: 56,
          child: ValueListenableBuilder<bool>(
            valueListenable: _isOtpComplete,
            builder: (context, ready, _) => ElevatedButton(
              onPressed: (ready && !_verifying) ? _onLogin : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                elevation: 0,
                disabledBackgroundColor: Colors.grey[300],
                disabledForegroundColor: Colors.grey[600],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _verifying
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'Log In',
                      style: GoogleFonts.kumbhSans(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 0.4),
                    ),
            ),
          ),
        ),
      ),
      // Hidden TextField to capture input
      persistentFooterButtons: [
        SizedBox(
          height: 0,
          width: 0,
          child: TextField(
            focusNode: _inputFocus,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(_otpLength)],
            onChanged: (value) {
              _updateControllers(value);
            },
            // No decoration to keep it hidden
            decoration: const InputDecoration(border: InputBorder.none, isCollapsed: true, contentPadding: EdgeInsets.zero),
            // Hide cursor and text
            cursorWidth: 0,
            style: const TextStyle(height: 0, color: Colors.transparent),
          ),
        ),
      ],
    );
  }
}
