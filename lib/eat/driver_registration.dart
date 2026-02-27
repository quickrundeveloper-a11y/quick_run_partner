import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'driver_home.dart';

class DriverRegistrationPage extends StatefulWidget {
  final String phoneNumber;
  const DriverRegistrationPage({super.key, required this.phoneNumber});

  @override
  State<DriverRegistrationPage> createState() => _DriverRegistrationPageState();
}

class _DriverRegistrationPageState extends State<DriverRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _vehicleNumberCtrl = TextEditingController();
  String _vehicleType = 'Bike';
  bool _isSaving = false;

  final List<String> _vehicleTypes = ['Bike', 'Scooter', 'Car', 'Van', 'Truck'];

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final driverData = {
        'name': _nameCtrl.text.trim(),
        'phoneNumber': widget.phoneNumber,
        'vehicleType': _vehicleType,
        'vehicleNumber': _vehicleNumberCtrl.text.trim().toUpperCase(),
        'createdAt': FieldValue.serverTimestamp(),
        'isOnline': false,
        'status': 'active',
      };

      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(widget.phoneNumber)
          .set(driverData);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', true);
      await prefs.setString('user_phone', widget.phoneNumber);
      await prefs.setString('user_name', _nameCtrl.text.trim());

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const DriverHome()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint("❌ Error saving driver profile: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _vehicleNumberCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Complete Profile',
          style: GoogleFonts.kumbhSans(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tell us more about yourself',
                style: GoogleFonts.kumbhSans(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 32),
              
              Text('Full Name', style: GoogleFonts.kumbhSans(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  hintText: 'Enter your full name',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black12),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Please enter your name' : null,
              ),
              
              const SizedBox(height: 20),
              
              Text('Vehicle Type', style: GoogleFonts.kumbhSans(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _vehicleType,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black12),
                  ),
                ),
                items: _vehicleTypes.map((type) => DropdownMenuItem(
                  value: type,
                  child: Text(type),
                )).toList(),
                onChanged: (val) => setState(() => _vehicleType = val!),
              ),
              
              const SizedBox(height: 20),
              
              Text('Vehicle Number', style: GoogleFonts.kumbhSans(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _vehicleNumberCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'e.g. MH 12 AB 1234',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black12),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Please enter vehicle number' : null,
              ),
              
              const SizedBox(height: 40),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Complete Registration', style: GoogleFonts.kumbhSans(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
