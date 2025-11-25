import 'package:flutter/material.dart';
import 'package:quick_run_driver/porter_driver/driver_dashboard.dart';
import 'package:quick_run_driver/porter_driver/porter_home.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'grocery_food/groccery_account_create.dart';

import 'grocery_food/gorcery_food_upload.dart';
import 'grocery_food/groccery_food_home.dart';
import 'grocery_food/order_accept_grocerry.dart';

class ChooseService extends StatefulWidget {
  const ChooseService({super.key});

  @override
  State<ChooseService> createState() => _ChooseServiceState();
}

class _ChooseServiceState extends State<ChooseService> {
  Future<void> _checkRestaurantAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in first')),
      );
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('Restaurent_shop')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) =>  OrderAcceptGrocerry()),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const GrocceryAccountCreate()),
        );
      }
    } catch (e) {
      debugPrint('Firestore check failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top : 20.0),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const DriverDashboard()),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    "Porter Driver",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            GestureDetector(
                onTap: _checkRestaurantAccount,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    "Grocery and Food",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const GorceryFoodUpload()),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "Add Product",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
