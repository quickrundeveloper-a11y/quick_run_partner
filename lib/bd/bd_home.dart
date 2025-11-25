import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'add_retailer.dart';

class BdHome extends StatefulWidget {
  final String bdId;
  const BdHome(this.bdId, {super.key});

  @override
  State<BdHome> createState() => _BdHomeState();
}

class _BdHomeState extends State<BdHome> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddRetailer(widget.bdId),
                ),
              );
            },
            child: Text(
              "Add Retailers",
              style: GoogleFonts.lexend(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Text('data'),
    );
  }
}