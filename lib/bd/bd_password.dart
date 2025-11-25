import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'bd_home.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BdPassword extends StatefulWidget {
  final String bdId;
  const BdPassword(this.bdId, {super.key});

  @override
  State<BdPassword> createState() => _BdPasswordState();
}

class _BdPasswordState extends State<BdPassword> {
  final TextEditingController _passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Set Password",
          style: TextStyle(color: Colors.black),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
      ),

      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Text(
              "Create Password",
              style: GoogleFonts.lexend(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),


            const SizedBox(height: 30),

            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: "Password",
                filled: true,
                fillColor: Color(0xFFF4F4F4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final enteredPass = _passwordController.text.trim();

                  if (enteredPass.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Enter password"),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  final doc = await FirebaseFirestore.instance
                      .collection("bd_profiles")
                      .doc(widget.bdId)
                      .get();

                  if (!doc.exists || doc.data()!["password"] != enteredPass) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Incorrect Password"),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString("bdId", widget.bdId);
                  await prefs.setString("bdPassword", enteredPass);
                  await prefs.setString("userType", "BD_executive");
                  print("BD DEBUG → Logged in BD = ${widget.bdId}");

                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BdHome(widget.bdId),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "Confirm Password",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
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
