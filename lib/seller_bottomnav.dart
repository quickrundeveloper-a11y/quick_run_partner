import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'grocery_food/seller_earning.dart';
import 'grocery_food/seller_home.dart';
import 'grocery_food/seller_profile.dart';
import 'grocery_food/seller_stock.dart';

class SellerBottomnav extends StatefulWidget {
  final String driverAuthId;
  const SellerBottomnav(this.driverAuthId, {super.key});

  @override
  State<SellerBottomnav> createState() => _SellerBottomnavState();
}

class _SellerBottomnavState extends State<SellerBottomnav> {
  int _currentIndex = 0;
  late final List<Widget> _pages = [
    SellerHome(widget.driverAuthId),
    SellerEarning(widget.driverAuthId),
    SellerStock(widget.driverAuthId),
    SellerProfile(widget.driverAuthId),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Colors.black,
              width: 1,
            ),
          ),
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.white,
          selectedLabelStyle: GoogleFonts.lexend(),
          unselectedLabelStyle: GoogleFonts.lexend(),
          selectedItemColor: Colors.black,
          unselectedItemColor: Colors.grey,
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items:  [
            BottomNavigationBarItem(
              backgroundColor: Colors.white,
              icon: Icon(PhosphorIcons.house()),
              label: "Home",
            ),
            BottomNavigationBarItem(
              icon: Icon(PhosphorIcons.money()),
              label: "Earning",
            ),
            BottomNavigationBarItem(
              icon: Icon(PhosphorIcons.bag()),
              label: "Stock",
            ),
            BottomNavigationBarItem(
              icon: Icon(PhosphorIcons.user()),
              label: "Profile",
            ),
          ],
        ),
      ),
    );
  }
}
