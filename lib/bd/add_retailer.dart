import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';

class AddRetailer extends StatefulWidget {
  final String bdId;
  const AddRetailer(this.bdId, {super.key});

  @override
  State<AddRetailer> createState() => _AddRetailerState();
}

class _AddRetailerState extends State<AddRetailer> {
  // Key for form validation
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final nameController = TextEditingController();
  final ownerController = TextEditingController();
  final addressController = TextEditingController();
  final numberController = TextEditingController();

  // State Variables
  String? selectedFoodType;
  double? lat;
  double? lng;
  bool isLoading = false;

  @override
  void dispose() {
    nameController.dispose();
    ownerController.dispose();
    addressController.dispose();
    numberController.dispose();
    super.dispose();
  }

  // --- Logic Section ---



  Future<void> saveRetailer() async {
    if (!_formKey.currentState!.validate()) return;

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please pick a location"), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final String uid = numberController.text.trim();
      final restaurantData = {
        "name": nameController.text.trim(),
        "owner_name": ownerController.text.trim(),
        "address": addressController.text.trim(),
        "food_type": selectedFoodType?.toLowerCase(),
        "phone": numberController.text.trim(),
        "image_url": null,
        "location": {"lat": lat, "lng": lng},
        "created_at": FieldValue.serverTimestamp(),
        "bd_ref_id": widget.bdId, // Good to keep reference who added them
      };

      // 1. Save to main collection
      await FirebaseFirestore.instance
          .collection("Restaurent_shop")
          .doc(uid)
          .set(restaurantData);

      // 2. Link to BD Profile
      await FirebaseFirestore.instance
          .collection("bd_profiles")
          .doc(widget.bdId)
          .collection("registered_retailers")
          .add({
        "retailer_doc_id": uid,
        "created_at": FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Retailer Registered Successfully!"), backgroundColor: Colors.green),
        );
        Navigator.pop(context); // Go back after success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // --- UI Section ---

  @override
  Widget build(BuildContext context) {
    // Define theme colors
    final primaryColor = Color(0xFF0000000);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        title:  Text("Onboard Retailer",style: GoogleFonts.lexend(),),
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),

              // --- Basic Details ---
              Text("Basic Information", style: _sectionHeaderStyle(context)),
              const SizedBox(height: 16),
              _buildInput(
                controller: nameController,
                label: "Shop Name",
                icon: Icons.storefront_outlined,
                validator: (v) => v!.isEmpty ? "Shop Name is required" : null,
              ),
              const SizedBox(height: 16),
              _buildInput(
                controller: ownerController,
                label: "Owner Name",
                icon: Icons.person_outline,
                validator: (v) => v!.isEmpty ? "Owner Name is required" : null,
              ),

              const SizedBox(height: 24),

              // --- Location & Type ---
              Text("Details & Location", style: _sectionHeaderStyle(context)),
              const SizedBox(height: 16),
              _buildFoodTypeDropdown(),
              const SizedBox(height: 16),
              _buildInput(
                controller: addressController,
                label: "Full Address",
                icon: Icons.location_on_outlined,
                maxLines: 2,
                validator: (v) => v!.isEmpty ? "Address is required" : null,
              ),
              const SizedBox(height: 16),
              _buildLocationPicker(primaryColor),

              const SizedBox(height: 24),

              // --- Verification ---
              Text("Contact Verification", style: _sectionHeaderStyle(context)),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildInput(
                      controller: numberController,
                      label: "Mobile Number",
                      icon: Icons.phone_android,
                      inputType: TextInputType.phone,
                      maxLength: 10,
                      prefixText: "+91 ",
                      enabled: true,
                      validator: (v) => v!.length < 10 ? "Invalid Number" : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),

              const SizedBox(height: 32),

              // --- Action Button ---
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: isLoading ? null : saveRetailer,
                  icon: const Icon(Icons.save),
                  label: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Save Retailer Profile",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // --- Widget Builders ---

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Add the retailer's details and save.",
              style: TextStyle(color: Colors.blue.shade900, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType inputType = TextInputType.text,
    int maxLines = 1,
    int? maxLength,
    String? prefixText,
    bool enabled = true,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      style: GoogleFonts.lexend(),
      controller: controller,
      keyboardType: inputType,
      maxLines: maxLines,
      maxLength: maxLength,
      enabled: enabled,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 22),
        prefixText: prefixText,
        counterText: "", // Hide counter for max length
        filled: true,
        fillColor: enabled ? Colors.white : Colors.grey[200],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.black, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black, width: 1),
        ),
      ),
    );
  }

  Widget _buildFoodTypeDropdown() {
    return DropdownButtonFormField<String>(
      dropdownColor: Colors.white,
      value: selectedFoodType,
      style: GoogleFonts.lexend(),
      items: ["Veg", "Non-Veg", "Both"].map((e) {
        return DropdownMenuItem(
          value: e,
          child: Text(
            e,
            style: GoogleFonts.lexend(color: Colors.black),
          ),
        );
      }).toList(),
      onChanged: (val) => setState(() => selectedFoodType = val),
      validator: (val) => val == null ? "Select Food Type" : null,
      decoration: InputDecoration(
        labelText: "Food Type",
        prefixIcon: const Icon(Icons.restaurant_menu),
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.black, width: 1),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black, width: 1),
        ),
      ),
    );
  }

  Widget _buildLocationPicker(Color primaryColor) {
    bool hasLocation = lat != null && lng != null;
    return InkWell(
      onTap: () async {
        try {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );

          setState(() {
            lat = position.latitude;
            lng = position.longitude;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Location Fetched Successfully!")),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Unable to fetch location: $e")),
          );
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: hasLocation ? Colors.green.withOpacity(0.05) : Colors.white,
          border: Border.all(
            color: Colors.black,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              hasLocation ? Icons.check_circle : Icons.add_location_alt,
              color: hasLocation ? Colors.green : Colors.grey[600],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasLocation ? "Location Selected" : "Tap to Pick Shop Location",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: hasLocation ? Colors.green[800] : Colors.grey[800],
                    ),
                  ),
                  if (hasLocation)
                    Text(
                      "Lat: $lat, Lng: $lng",
                      style: TextStyle(fontSize: 12, color: Colors.green[700]),
                    )
                ],
              ),
            ),
            if (!hasLocation)
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  TextStyle _sectionHeaderStyle(BuildContext context) {
    return GoogleFonts.lexend(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: Colors.grey[600],
      letterSpacing: 0.5,
    );
  }
}