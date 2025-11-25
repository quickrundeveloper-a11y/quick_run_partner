import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddRetailer extends StatefulWidget {
  final String bdId;
  const AddRetailer(this.bdId, {super.key});

  @override
  State<AddRetailer> createState() => _AddRetailerState();
}

class _AddRetailerState extends State<AddRetailer> {
  final name = TextEditingController();
  final owner = TextEditingController();
  final address = TextEditingController();
  final foodType = TextEditingController();
  final number = TextEditingController();

  double? lat;
  double? lng;

  bool sendingOtp = false;
  String? verificationId;

  Future<void> sendOtp() async {
    setState(() => sendingOtp = true);

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: "+91${number.text.trim()}",
      verificationCompleted: (cred) {},
      verificationFailed: (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? "Error")),
        );
        setState(() => sendingOtp = false);
      },
      codeSent: (vId, _) {
        verificationId = vId;
        setState(() => sendingOtp = false);
        askOtp();
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  void askOtp() {
    final otp = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Enter OTP"),
        content: TextField(
          controller: otp,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final cred = PhoneAuthProvider.credential(
                verificationId: verificationId!,
                smsCode: otp.text.trim(),
              );

              final user = await FirebaseAuth.instance.signInWithCredential(cred);

              Navigator.pop(context);
              saveRetailer(user.user!.uid);
            },
            child: const Text("Verify"),
          ),
        ],
      ),
    );
  }

  Future<void> saveRetailer(String docId) async {
    final restaurantData = {
      "name": name.text.trim(),
      "owner_name": owner.text.trim(),
      "address": address.text.trim(),
      "food_type": foodType.text.trim(),
      "image_url": null,
      "location": {"lat": lat, "lng": lng},
      "created_at": Timestamp.now(),
    };

    await FirebaseFirestore.instance
        .collection("Restaurent_shop")
        .doc(docId)
        .set(restaurantData);

    await FirebaseFirestore.instance
        .collection("bd_profiles")
        .doc(widget.bdId)
        .collection("registered_retailers")
        .add({
      "retailer_doc_id": docId,
      "created_at": Timestamp.now(),
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Retailer Registered Successfully"),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Add New Retailer"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.storefront, size: 24),
                      SizedBox(width: 8),
                      Text(
                        "Register New Retailer",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Retailer Information",
                  style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                _buildTextField(
                  controller: name,
                  labelText: "Shop Name",
                  icon: Icons.store,
                ),
                const SizedBox(height: 8),
                Divider(thickness: 1, color: Colors.black12),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: owner,
                  labelText: "Owner Name",
                  icon: Icons.person,
                ),
                const SizedBox(height: 8),
                Divider(thickness: 1, color: Colors.black12),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: address,
                  labelText: "Address",
                  icon: Icons.location_on,
                ),
                const SizedBox(height: 8),
                Divider(thickness: 1, color: Colors.black12),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: foodType,
                  labelText: "Food Type (e.g., Indian, Italian)",
                  icon: Icons.fastfood,
                ),
                const SizedBox(height: 8),
                Divider(thickness: 1, color: Colors.black12),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: number,
                  labelText: "Phone Number",
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 8),
                Divider(thickness: 1, color: Colors.black12),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: Icon(lat == null ? Icons.add_location_alt : Icons.check_circle,
                      color: lat == null ? Theme.of(context).primaryColor : Colors.green),
                  onPressed: () {
                    // Placeholder for location picker logic
                    lat = 28.62;
                    lng = 77.37;
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Location Selected!"),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  label: Text(lat == null ? "Pick Shop Location" : "Location Selected"),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(
                      color: lat == null ? Theme.of(context).primaryColor : Colors.green,
                      width: 2,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                if (lat != null && lng != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "LAT: ${lat!.toStringAsFixed(6)}   LNG: ${lng!.toStringAsFixed(6)}",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.green,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: sendingOtp ? null : sendOtp,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                  ),
                  child: sendingOtp
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : const Text("Register & Send OTP", style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 20),
                Text(
                  "You are registering under BD ID: ",
                  textAlign: TextAlign.center,
                ),
                Text(
                  "${widget.bdId}",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: labelText,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: Theme.of(context).primaryColor,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      ),
    );
  }
}
