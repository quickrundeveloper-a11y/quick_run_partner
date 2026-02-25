import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../login/phone_number_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SellerProfile extends StatefulWidget {
  final String? driverAuthId;
  const SellerProfile(this.driverAuthId, {super.key});

  @override
  State<SellerProfile> createState() => _SellerProfileState();
}

class _SellerProfileState extends State<SellerProfile> {
  String ownerName = "";
  String restaurantName = "";
  String address = "";
  String foodType = "";
  String joiningDate = "";
  String phoneNumber = "";
  bool _isLoading = true;
  String instagram = "";
  String facebook = "";
  String xHandle = "";

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection("Restaurent_shop")
          .where("phone", isEqualTo: widget.driverAuthId)
          .get();

      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();

        setState(() {
          ownerName = data["owner_name"] ?? "";
          restaurantName = data["name"] ?? "";
          address = data["address"] ?? "";
          foodType = data["food_type"] ?? "";
          phoneNumber = widget.driverAuthId ?? "";
          instagram = data["instagram"] ?? "";
          facebook = data["facebook"] ?? "";
          xHandle = data["x"] ?? "";

          // Format joining date
          final timestamp = data["created_at"];
          if (timestamp != null) {
            if (timestamp is Timestamp) {
              joiningDate = DateFormat('dd MMM yyyy').format(timestamp.toDate());
            } else {
              joiningDate = timestamp.toString();
            }
          } else {
            joiningDate = "Not specified";
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      print("PROFILE FETCH ERROR: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _editSocialField(String field, String currentValue) async {
    final controller = TextEditingController(text: currentValue);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Edit $field",
              style: GoogleFonts.lexend(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Paste your $field link below",
              style: GoogleFonts.lexend(
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        content: Container(
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: "Enter $field URL",
              hintStyle: GoogleFonts.lexend(color: Colors.grey),
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Cancel",
              style: GoogleFonts.lexend(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            ),
            child: Text(
              "Save",
              style: GoogleFonts.lexend(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        if (field == "Instagram") instagram = result;
        if (field == "Facebook") facebook = result;
        if (field == "X") xHandle = result;
      });

      final snap = await FirebaseFirestore.instance
          .collection("Restaurent_shop")
          .where("phone", isEqualTo: widget.driverAuthId)
          .get();

      if (snap.docs.isNotEmpty) {
        await snap.docs.first.reference.update({
          field == "Instagram" ? "instagram" : field == "Facebook" ? "facebook" : "x": result,
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          "Seller Profile",
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -------- Profile Header --------
            _buildProfileHeader(),
            const SizedBox(height: 24),

            // -------- Restaurant Details Card --------
            _buildDetailsCard(),
            const SizedBox(height: 24),

            // -------- Social Links --------
            _buildSocialSection(),
            const SizedBox(height: 24),

            // -------- Account Section --------
            _buildAccountSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.restaurant,
              size: 36,
              color: Colors.blue[700],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  restaurantName.isEmpty ? "Restaurant Name" : restaurantName,
                  style: GoogleFonts.lexend(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  ownerName.isEmpty ? "Owner Name" : ownerName,
                  style: GoogleFonts.lexend(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 6),
                if (phoneNumber.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.phone, size: 16, color: Colors.grey[500]),
                      const SizedBox(width: 6),
                      Text(
                        phoneNumber,
                        style: GoogleFonts.lexend(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 12),
          child: Text(
            "RESTAURANT DETAILS",
            style: GoogleFonts.lexend(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _detailItem(
                  icon: Icons.person_outline,
                  label: "Owner Name",
                  value: ownerName,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: Color(0xFFF0F0F0)),
                ),
                _detailItem(
                  icon: Icons.storefront_outlined,
                  label: "Restaurant Name",
                  value: restaurantName,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: Color(0xFFF0F0F0)),
                ),
                _detailItem(
                  icon: Icons.restaurant_menu_outlined,
                  label: "Food Type",
                  value: foodType,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: Color(0xFFF0F0F0)),
                ),
                _detailItem(
                  icon: Icons.location_on_outlined,
                  label: "Address",
                  value: address,
                  maxLines: 2,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: Color(0xFFF0F0F0)),
                ),
                _detailItem(
                  icon: Icons.calendar_today_outlined,
                  label: "Joining Date",
                  value: joiningDate,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _detailItem({
    required IconData icon,
    required String label,
    required String value,
    int maxLines = 1,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.lexend(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value.isEmpty ? "Not specified" : value,
                style: GoogleFonts.lexend(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSocialSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 12),
          child: Text(
            "SOCIAL PROFILES",
            style: GoogleFonts.lexend(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              _socialTile(
                icon: Icons.camera_alt_outlined,
                title: "Instagram",
                subtitle: "Add Instagram link",
                color: Color(0xFFE1306C),
              ),
              const Divider(height: 1, indent: 70, color: Color(0xFFF0F0F0)),
              _socialTile(
                icon: Icons.facebook_outlined,
                title: "Facebook",
                subtitle: "Add Facebook link",
                color: Color(0xFF1877F2),
              ),
              const Divider(height: 1, indent: 70, color: Color(0xFFF0F0F0)),
              _socialTile(
                icon: Icons.alternate_email_outlined,
                title: "X (Twitter)",
                subtitle: "Add X handle",
                color: Colors.black87,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _socialTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: color,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: GoogleFonts.lexend(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.lexend(
          fontSize: 13,
          color: Colors.grey[600],
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          (title == "Instagram" ? instagram : title == "Facebook" ? facebook : xHandle).isNotEmpty
              ? "Change"
              : "Add",
          style: GoogleFonts.lexend(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
      ),
      onTap: () async {
        final existing = title == "Instagram" ? instagram : title == "Facebook" ? facebook : xHandle;

        if (existing.isNotEmpty) {
          // Open URL
          try {
            await launchUrl(Uri.parse(existing), mode: LaunchMode.externalApplication);
          } catch (e) {
            _editSocialField(title, existing);
          }
        } else {
          // Let user add
          _editSocialField(title, existing);
        }
      },
    );
  }

  Widget _buildAccountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 12),
          child: Text(
            "ACCOUNT",
            style: GoogleFonts.lexend(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              _accountTile(
                icon: Icons.delete_forever_outlined,
                title: "Delete Account",
                subtitle: "Permanently delete your account",
                color: Colors.red,
              ),
              const Divider(height: 1, indent: 70, color: Color(0xFFF0F0F0)),
              _accountTile(
                icon: Icons.logout_outlined,
                title: "Logout",
                subtitle: "Sign out from this device",
                color: Colors.black87,
                isLogout: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _accountTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    bool isLogout = false,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: color,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: GoogleFonts.lexend(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: color,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.lexend(
          fontSize: 13,
          color: Colors.grey[600],
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: Colors.grey[400],
      ),
      onTap: () async {
        if (isLogout) {
          final confirm = await _showConfirmationDialog(
            title: "Logout",
            message: "Are you sure you want to logout from this device?",
            confirmText: "Logout",
            isDestructive: false,
          );
          if (confirm == true) {
            // Clear SharedPreferences
            final prefs = await SharedPreferences.getInstance();
            await prefs.clear();

            // Navigate to login screen
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const PhoneNumberAuth()),
              (route) => false,
            );
          }
        } else {
          final confirm = await _showConfirmationDialog(
            title: "Delete Account",
            message: "This action cannot be undone. All your data will be permanently deleted.",
            confirmText: "Delete",
            isDestructive: true,
          );
          if (confirm == true) {
            // TODO: Implement account deletion
          }
        }
      },
    );
  }

  Future<bool?> _showConfirmationDialog({
    required String title,
    required String message,
    required String confirmText,
    required bool isDestructive,
  }) {
    return showDialog<bool>(
      barrierColor: Colors.white,
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: GoogleFonts.lexend(fontWeight: FontWeight.w700),
        ),
        content: Text(
          message,
          style: GoogleFonts.lexend(color: Colors.grey[700]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            child: Text(
              "Cancel",
              style: GoogleFonts.lexend(
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              backgroundColor: isDestructive ? Colors.red : Colors.blue,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              confirmText,
              style: GoogleFonts.lexend(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}