import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:quick_run_driver/porter_driver/porter_home.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({Key? key}) : super(key: key);

  @override
  _DriverDashboardState createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  bool _isOnline = false;
  Timer? _timer;
  int _offlineSeconds = 0;

  @override
  void initState() {
    super.initState();
    // Initially the driver is offline, so the timer should start.
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _offlineSeconds++;
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
  }

  String _formatDuration(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF1F0F5), // Set the background to dark blue
      appBar: AppBar(
        backgroundColor: Color(0xFFF1F0F5),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _isOnline = !_isOnline;
                  if (_isOnline) {
                    // When going online, stop the timer.
                    _stopTimer();
                  } else {
                    // When going offline, start the timer.
                    _startTimer();
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 145,
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: _isOnline ? Color(0xFF00BA69) : Color(0xFF83C7FF),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: Text(
                        _isOnline ? 'ONLINE' : 'OFFLINE',
                        style: GoogleFonts.lexend(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    AnimatedAlign(
                      duration: Duration(milliseconds: 300),
                      alignment: _isOnline ? Alignment.centerRight : Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.all(.0),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: _isOnline ? Color(0xFF008C4F) : Color(0xFF0088FF),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                Text(
                  "OFFLINE TIME ",
                  style: GoogleFonts.lexend(
                    color: Colors.black87,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _formatDuration(_offlineSeconds),
                  style: GoogleFonts.lexend(
                    color: Colors.amber.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(


              children: [
                 Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Color(0xFFFFFFFF),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Today's Earning",
                                    style: GoogleFonts.lexend(
                                      fontSize: 20,
                                      color: Color(0xFF7E7E7E),
                                      fontWeight: FontWeight.w600,
                                    )),
                                Text("34 km",
                                    style: GoogleFonts.lexend(
                                      color: Colors.grey[600],
                                      fontSize: 13,
                                    )),
                              ],
                            ),
                            SizedBox(height: 15),

                            Container(height: 1,width: double.infinity,color: Color(0xFFF2F2F2),),
                            SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 18.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("Total Earning",
                                            style: GoogleFonts.lexend(
                                              color: Colors.black,
                                              fontSize: 12,
                                            )),
                                        SizedBox(height: 4),
                                        Text("₹ 4,000",
                                            style: GoogleFonts.lexend(
                                              color: Color(0xFF6E6E6E),
                                              fontSize: 27,
                                              fontWeight: FontWeight.bold,
                                            )),
                                      ],
                                    ),
                                  ),
                                ),
                                SizedBox(width: 60,),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text("Total Orders",
                                          style: GoogleFonts.lexend(
                                            color: Colors.black,
                                            fontSize: 12,
                                          )),
                                      SizedBox(height: 4),
                                      Text("80",
                                          style: GoogleFonts.lexend(
                                            color: Color(0xFF6E6E6E),
                                            fontSize: 27,
                                            fontWeight: FontWeight.bold,
                                          )),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),

                            Container(height: 1,width: double.infinity,color: Color(0xFFF2F2F2),),

                            SizedBox(height: 4),
                            // Center(
                            //   child: TextButton.icon(
                            //     onPressed: () {},
                            //     label: Text(
                            //       "See Details",
                            //       style: GoogleFonts.lexend(
                            //         color: Colors.black87,
                            //         fontWeight: FontWeight.w500,
                            //       ),
                            //     ),
                            //     icon: Icon(Icons.arrow_forward, size: 16, color: Colors.black87),
                            //
                            //   ),
                            // ),
                          ],
                        ),
                      ),
                      SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            "🎉 You’re doing well. Keep it up !",
                            style: GoogleFonts.lexend(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                    ],
                  ),
              ],
            ),
          ),
          const Expanded(child: PorterHome()), // Embed the existing PorterHome widget
        ],
      ),
    );
  }
}