import 'package:flutter/material.dart';

class DriverHome extends StatefulWidget {
  final String driverAuthId;
  const DriverHome(this.driverAuthId, {super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text("Driver Home"),
      ),
      body: Center(
        child: Text(
          "DriverAuthID: ${widget.driverAuthId}",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
