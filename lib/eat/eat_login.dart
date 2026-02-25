import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart';

class EatLoginPage extends StatefulWidget {
  const EatLoginPage({super.key});

  @override
  State<EatLoginPage> createState() => _EatLoginPageState();
}

class _EatLoginPageState extends State<EatLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneCtrl = TextEditingController();
  final int _otpLength = 6;
  final List<TextEditingController> _otpCtrls = List.generate(6, (_) => TextEditingController());
  final FocusNode _otpFocus = FocusNode();
  bool _acceptedTerms = false;
  bool _sending = false;
  bool _verifying = false;
  bool _showOtp = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpFocus.dispose();
    for (final c in _otpCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  String get _otpValue => _otpCtrls.map((c) => c.text).join();

  Future<void> _sendOtp() async {
    final raw = _phoneCtrl.text.trim();
    if (raw.length != 10 || int.tryParse(raw) == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid 10-digit phone number')));
      return;
    }
    setState(() => _sending = true);
    try {
      debugPrint("✅ OTP requested for $raw");
      setState(() {
        _showOtp = true;
      });
    } catch (e) {
      debugPrint("❌ OTP UI error: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OTP UI error: $e')));
    } finally {
      setState(() => _sending = false);
    }
  }

  Future<void> _verifyOtp() async {
    final raw = _phoneCtrl.text.trim();
    if (!kReleaseMode) {
      for (final c in _otpCtrls) {
        if (c.text.isEmpty) c.text = '1';
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logged in ✅')));
      return;
    }
    if (_otpValue.length != _otpLength) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter the 6-digit OTP')));
      return;
    }
    setState(() => _verifying = true);
    try {
      debugPrint("✅ OTP verified for $raw");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logged in ✅')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Verification UI error: $e")));
    } finally {
      setState(() => _verifying = false);
    }
  }

  void _onOtpChanged(String value) {
    final chars = value.split("");
    for (int i = 0; i < _otpLength; i++) {
      if (i < chars.length) {
        _otpCtrls[i].text = chars[i];
      } else {
        _otpCtrls[i].clear();
      }
    }
    if (!_otpFocus.hasFocus) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _otpFocus.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0E0E0E), Color(0xFF2C2C2C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'QuickRun Eat',
                      style: GoogleFonts.kronaOne(color: Colors.white, fontSize: 28, letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sign in to manage your store',
                      style: GoogleFonts.kumbhSans(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Form(
                  key: _formKey,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Phone Number', style: GoogleFonts.kumbhSans(fontWeight: FontWeight.w600, fontSize: 14)),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            maxLength: 10,
                            decoration: InputDecoration(
                              counterText: '',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                              filled: true,
                              fillColor: const Color(0xFFF4F4F4),
                              prefixIcon: Container(
                                width: 64,
                                alignment: Alignment.center,
                                child: Text('+91', style: GoogleFonts.kumbhSans(fontWeight: FontWeight.w600)),
                              ),
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
                              if (value.length != 10 || int.tryParse(value) == null) return 'Enter a valid 10-digit number';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
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
                                child: Text('I accept the Terms & Conditions', style: GoogleFonts.kumbhSans(color: Colors.black87, fontSize: 13)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: (_acceptedTerms && _formKey.currentState != null && _formKey.currentState!.validate() && !_sending)
                                  ? _sendOtp
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                disabledBackgroundColor: Colors.black26,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                minimumSize: const Size.fromHeight(54),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _sending
                                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : Text('GET OTP', style: GoogleFonts.kumbhSans(letterSpacing: 1.2, fontSize: 14)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_showOtp) ...[
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Enter OTP', style: GoogleFonts.kumbhSans(fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              _otpLength,
                              (i) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Container(
                                  width: 48,
                                  height: 60,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF4F4F4),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _otpCtrls[i].text.isNotEmpty ? Colors.black87 : Colors.black12,
                                      width: _otpCtrls[i].text.isNotEmpty ? 1.2 : 1,
                                    ),
                                  ),
                                  child: ValueListenableBuilder<TextEditingValue>(
                                    valueListenable: _otpCtrls[i],
                                    builder: (context, value, _) => Text(
                                      value.text,
                                      style: GoogleFonts.kumbhSans(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.black),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: !_verifying ? _verifyOtp : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                minimumSize: const Size.fromHeight(54),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _verifying
                                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : Text('Log In', style: GoogleFonts.kumbhSans(fontSize: 16, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _showOtp
          ? SafeArea(
              top: false,
              minimum: EdgeInsets.only(left: 24, right: 24, bottom: insets > 0 ? 16 + insets : 24),
              child: SizedBox(
                height: 0,
                child: const SizedBox.shrink(),
              ),
            )
          : null,
      persistentFooterButtons: _showOtp
          ? [
              SizedBox(
                height: 0,
                width: 0,
                child: TextField(
                  focusNode: _otpFocus,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(_otpLength)],
                  onChanged: _onOtpChanged,
                  decoration: const InputDecoration(border: InputBorder.none, isCollapsed: true, contentPadding: EdgeInsets.zero),
                  cursorWidth: 0,
                  style: const TextStyle(height: 0, color: Colors.transparent),
                ),
              ),
            ]
          : null,
    );
  }
}
