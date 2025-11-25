import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/gestures.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
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
  String? _verificationId;
  int? _resendToken;

  Future<void> _startPhoneVerification() async {
    final raw = _phoneController.text.trim();

    // ✅ Validate Indian 10‑digit mobile numbers
    if (raw.length != 10 || int.tryParse(raw) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 10-digit phone number')),
      );
      return;
    }

    final phone = '+91$raw';
    setState(() => _sending = true);

    try {
      // ✅ Ensure Firebase is initialized (defensive)
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      // ✅ Platform guard: Only allow on Android/iOS
      if (!(defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Phone auth is only supported on Android/iOS devices.')),
        );
        return;
      }

      debugPrint('Starting verifyPhoneNumber for: ' + phone);
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // You may auto-sign in here if you want:
          // await FirebaseAuth.instance.signInWithCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _sending = false);
          final msg = e.message ?? e.code;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Verification failed: $msg')),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          setState(() => _sending = false);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OtpAuth(
                phone: raw,
                verificationId: verificationId,
              ),
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
          setState(() => _sending = false);
        },
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Auth error: ${e.message ?? e.code}')),
      );
    } on PlatformException catch (e) {
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Channel error: ${e.code} — ${e.message}\n${e.details ?? ''}')),
      );
    } catch (e) {
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting verification: $e')),
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
