import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import 'bd_password.dart';

class BdLogin extends StatefulWidget {
  const BdLogin({super.key});

  @override
  State<BdLogin> createState() => _BdLoginState();
}

class _BdLoginState extends State<BdLogin> {
  List<Map<String, dynamic>> bdList = [];

  @override
  void initState() {
    super.initState();
    fetchBDs();
  }

  void fetchBDs() async {
    final snapshot = await FirebaseFirestore.instance.collection('bd_profiles').get();
    final data = snapshot.docs
        .map((doc) => {
              "id": doc.id,
              "name": doc["name"],
              "profileURL": doc["profileURL"],
            })
        .toList();
    setState(() {
      bdList = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title:  Text(
          "Business Executives",
          style: GoogleFonts.lexend(color: Colors.black),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),

      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: bdList.length,
        itemBuilder: (context, index) {
          final bd = bdList[index];

          return GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BdPassword(bd["id"]),
                ),
              );
            },
            child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                )
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: NetworkImage(bd["profileURL"]),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bd["name"],
                        style: GoogleFonts.lexend(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "ID: ${bd["id"]}",
                        style: GoogleFonts.lexend(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            ),
          );
        },
      ),
    );
  }
}
