import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// NEW IMPORT: Required to get the unique device token
import 'package:firebase_messaging/firebase_messaging.dart';

class CreateDriverAccount extends StatefulWidget {
  const CreateDriverAccount({super.key});

  @override
  State<CreateDriverAccount> createState() => _CreateDriverAccountState();
}

class _CreateDriverAccountState extends State<CreateDriverAccount> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _vehicleNumberCtrl = TextEditingController();
  final _vehicleModelCtrl = TextEditingController();

  String? _gender; // Male / Female / Other
  File? _profileImageFile; // optional (not uploaded in this patch)

  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _vehicleNumberCtrl.dispose();
    _vehicleModelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null) return;
    if (!form.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not logged in. Please sign in again.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      // 1. GET FCM TOKEN
      // We assume permissions were already requested in main.dart
      final fcmToken = await FirebaseMessaging.instance.getToken();

      final data = {
        'driverId': user.uid, // current logged-in id
        'driverName': _nameCtrl.text.trim(),
        'vehicleNumber': _vehicleNumberCtrl.text.trim(),
        'gender': _gender,
        'vehicleModel': _vehicleModelCtrl.text.trim(),
        'profileImageUrl': null, // optional; can be updated later when uploaded
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        // 2. SAVE THE TOKEN
        'fcmToken': fcmToken,
        'isAvailable': true, // Assuming new driver is available by default
      };

      // Use uid as the doc id so each driver has exactly one document
      await FirebaseFirestore.instance
          .collection('QuickRunDrivers')
          .doc(user.uid)
          .set(data, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver account created!')),
      );

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Driver Account'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Optional Profile Image placeholder (no upload wired here)
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundImage:
                        _profileImageFile != null ? FileImage(_profileImageFile!) : null,
                        child: _profileImageFile == null
                            ? const Icon(Icons.person, size: 44)
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Material(
                          color: Colors.transparent,
                          child: IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () {
                              // Optional image picking can be added later using image_picker
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Profile image is optional. You can add it later.'),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                TextFormField(
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Driver Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter driver name' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _vehicleNumberCtrl,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle Number',
                    hintText: 'e.g. DL01AB1234',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter vehicle number' : null,
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  value: _gender,
                  items: const [
                    DropdownMenuItem(value: 'Male', child: Text('Male')),
                    DropdownMenuItem(value: 'Female', child: Text('Female')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (val) => setState(() => _gender = val),
                  decoration: const InputDecoration(
                    labelText: 'Gender',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Select gender' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _vehicleModelCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle Model',
                    hintText: 'e.g. Tata Ace, Bolero Pickup',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter vehicle model' : null,
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text('Create Account'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}