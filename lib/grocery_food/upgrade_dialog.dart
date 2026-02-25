import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'subscription_service.dart';

class UpgradeDialog extends StatefulWidget {
  final String restaurantId;
  final String driverAuthId;

  const UpgradeDialog({
    super.key,
    required this.restaurantId,
    required this.driverAuthId,
  });

  @override
  State<UpgradeDialog> createState() => _UpgradeDialogState();
}

class _UpgradeDialogState extends State<UpgradeDialog> {
  final SubscriptionService _subscriptionService = SubscriptionService();
  bool _isProcessing = false;
  
  // Razorpay Subscription Payment Link
  static const String subscriptionLink = 'https://rzp.io/rzp/ijIJfIa';

  Future<void> _openSubscriptionLink() async {
    try {
      setState(() => _isProcessing = true);

      // Store restaurant ID in Firestore before opening link for webhook reference
      await FirebaseFirestore.instance
          .collection('Restaurent_shop')
          .doc(widget.restaurantId)
          .update({
        'pendingSubscription': {
          'restaurantId': widget.restaurantId,
          'driverAuthId': widget.driverAuthId,
          'phone': widget.driverAuthId.replaceAll('+91', ''),
          'initiatedAt': FieldValue.serverTimestamp(),
        },
      });

      // Add restaurant ID as query parameter to help webhook identify the restaurant
      final linkWithParams = '$subscriptionLink?restaurantId=${widget.restaurantId}';
      final uri = Uri.parse(linkWithParams);
      
      // Try to launch the URL directly (canLaunchUrl sometimes returns false on Android)
      bool launched = false;
      
      // Try external application first (opens in browser)
      try {
        launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } catch (e) {
        print('⚠️ External launch failed, trying platform default: $e');
      }
      
      // If external failed, try platform default
      if (!launched) {
        try {
          launched = await launchUrl(
            uri,
            mode: LaunchMode.platformDefault,
          );
        } catch (e) {
          print('⚠️ Platform default launch failed: $e');
        }
      }
      
      if (launched) {
        if (mounted) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Opening payment page... Complete payment to activate subscription. ₹99 will be auto-debited monthly.',
                style: GoogleFonts.lexend(),
              ),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 6),
            ),
          );
        }
      } else {
        throw Exception('Could not launch subscription link. Please check your browser settings.');
      }
    } catch (e) {
      print('❌ Error opening subscription link: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error opening payment link. Please try again.',
              style: GoogleFonts.lexend(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
        ),
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Color(0xFF00BA69).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.workspace_premium,
                size: 40,
                color: Color(0xFF00BA69),
              ),
            ),
            SizedBox(height: 20),
            
            // Title
            Text(
              'Upgrade Your Plan',
              style: GoogleFonts.lexend(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 12),
            
            // Description
            Text(
              'Get unlimited orders with automatic monthly billing',
              textAlign: TextAlign.center,
              style: GoogleFonts.lexend(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Color(0xFF555555),
              ),
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Color(0xFF00BA69).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.autorenew, size: 16, color: Color(0xFF00BA69)),
                  SizedBox(width: 6),
                  Text(
                    'Auto-debit enabled',
                    style: GoogleFonts.lexend(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF00BA69),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            
            // Price Card
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Color(0xFFF1F0F5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Monthly Subscription',
                        style: GoogleFonts.lexend(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        '₹99',
                        style: GoogleFonts.lexend(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF00BA69),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Divider(),
                  SizedBox(height: 12),
                  _buildFeature('Unlimited orders', Icons.check_circle, Colors.green),
                  SizedBox(height: 8),
                  _buildFeature('Auto-pay enabled', Icons.check_circle, Colors.green),
                  SizedBox(height: 8),
                  _buildFeature('Priority support', Icons.check_circle, Colors.green),
                ],
              ),
            ),
            SizedBox(height: 24),
            
            // Payment Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _openSubscriptionLink,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF00BA69),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _isProcessing
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Subscribe for ₹99/month',
                            style: GoogleFonts.lexend(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.autorenew, size: 18, color: Colors.white),
                        ],
                      ),
              ),
            ),
            SizedBox(height: 12),
            
            // Cancel Button
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Maybe Later',
                style: GoogleFonts.lexend(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF555555),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeature(String text, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        SizedBox(width: 12),
        Text(
          text,
          style: GoogleFonts.lexend(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Color(0xFF555555),
          ),
        ),
      ],
    );
  }
}

