import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// TODO: replace with your Google Geocoding API key (enable Geocoding API in Cloud Console)
const String kGoogleApiKey = 'AIzaSyCY7rArtF49q1sSkDDJaSmC0pLl04EKV7I';

class GrocceryAccountCreate extends StatefulWidget {
  final String driverAuthId;
  const GrocceryAccountCreate({super.key, required this.driverAuthId});

  @override
  State<GrocceryAccountCreate> createState() => _GrocceryAccountCreateState();
}

class _GrocceryAccountCreateState extends State<GrocceryAccountCreate> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _ownerCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  String _foodType = 'both'; // 'veg', 'nonveg', 'both'

  File? _imageFile;
  bool _isSaving = false;
  double? _latitude;
  double? _longitude;

  final ImagePicker _picker = ImagePicker();

  String? _restaurantId;

  @override
  void initState() {
    super.initState();
    _fetchRestaurantIdFromPhone();
  }

  Future<void> _fetchRestaurantIdFromPhone() async {
    final snap = await FirebaseFirestore.instance.collection('Restaurent_shop').get();
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['phone'] == widget.driverAuthId) {
        setState(() {
          _restaurantId = doc.id;
        });
        break;
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ownerCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<String?> _uploadImage(File file) async {
    try {
      final fileName = 'restaurants/${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
      final ref = FirebaseStorage.instance.ref().child(fileName);
      final uploadTask = await ref.putFile(file);
      final url = await uploadTask.ref.getDownloadURL();
      return url;
    } catch (e) {
      debugPrint('Image upload failed: $e');
      return null;
    }
  }

  Future<void> _getCurrentLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission denied')));
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission permanently denied')));
      return;
    }

    try {
      final Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
      });

      // Try reverse geocoding with Google Geocoding API to get a readable address
      if (_latitude != null && _longitude != null) {
        final address = await _reverseGeocode(_latitude!, _longitude!);
        if (address != null && address.isNotEmpty) {
          setState(() => _addressCtrl.text = address);
        } else {
          setState(() => _addressCtrl.text = 'Lat: ${_latitude!.toStringAsFixed(6)}, Lng: ${_longitude!.toStringAsFixed(6)}');
        }
      }
    } catch (e) {
      debugPrint('Failed to get location: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to get current location')));
    }
  }

  Future<String?> _reverseGeocode(double lat, double lng) async {
    try {
      if (kGoogleApiKey == 'YOUR_GOOGLE_API_KEY_HERE') {
        debugPrint('Google API key not set. Please set kGoogleApiKey.');
        return null;
      }

      final url = Uri.parse('https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$kGoogleApiKey');
      final resp = await http.get(url);
      if (resp.statusCode != 200) return null;
      final Map<String, dynamic> data = json.decode(resp.body);
      if (data['status'] == 'OK' && data['results'] != null && (data['results'] as List).isNotEmpty) {
        final first = data['results'][0];
        final formatted = first['formatted_address'] as String?;
        return formatted;
      }
      return null;
    } catch (e) {
      debugPrint('Reverse geocode failed: $e');
      return null;
    }
  }

  Future<void> _saveToFirestore() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      String? imageUrl;
      if (_imageFile != null) {
        imageUrl = await _uploadImage(_imageFile!);
      }

      final data = {
        'name': _nameCtrl.text.trim(),
        'owner_name': _ownerCtrl.text.trim(),
        'food_type': _foodType, // 'veg' | 'nonveg' | 'both'
        'address': _addressCtrl.text.trim(),
        'location': {
          'lat': _latitude,
          'lng': _longitude,
        },
        'image_url': imageUrl,
        'created_at': FieldValue.serverTimestamp(),
      };

      final restaurantId = _restaurantId;
      if (restaurantId == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Restaurant ID not resolved')));
        setState(() => _isSaving = false);
        return;
      }

      await FirebaseFirestore.instance
          .collection('Restaurent_shop')
          .doc(restaurantId)
          .set(data);

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Restaurant account created successfully')));
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Save failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save restaurant')));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Restaurant Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _imageFile == null
                      ? const Center(child: Text('Tap to select restaurant image'))
                      : ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(_imageFile!, fit: BoxFit.cover)),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Restaurant name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter restaurant name' : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _ownerCtrl,
                decoration: const InputDecoration(labelText: 'Owner name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter owner name' : null,
              ),

              const SizedBox(height: 12),

              Text('Food type', style: GoogleFonts.kumbhSans()),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Veg'),
                      value: 'veg',
                      groupValue: _foodType,
                      onChanged: (v) => setState(() => _foodType = v ?? 'veg'),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Non-Veg'),
                      value: 'nonveg',
                      groupValue: _foodType,
                      onChanged: (v) => setState(() => _foodType = v ?? 'nonveg'),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Both'),
                      value: 'both',
                      groupValue: _foodType,
                      onChanged: (v) => setState(() => _foodType = v ?? 'both'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(labelText: 'Address (street, city, postal) or notes'),
                maxLines: 2,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter address or location details' : null,
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _getCurrentLocation,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Use current location'),
                  ),
                  const SizedBox(width: 12),
                  if (_latitude != null && _longitude != null)
                    Text('Lat: ${_latitude!.toStringAsFixed(5)}, Lng: ${_longitude!.toStringAsFixed(5)}')
                ],
              ),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _isSaving ? null : _saveToFirestore,
                child: _isSaving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
