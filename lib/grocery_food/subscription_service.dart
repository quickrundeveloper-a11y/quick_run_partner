import 'package:cloud_firestore/cloud_firestore.dart';

class SubscriptionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Check if restaurant has active subscription
  Future<bool> hasActiveSubscription(String restaurantId) async {
    try {
      final doc = await _firestore
          .collection('Restaurent_shop')
          .doc(restaurantId)
          .get();

      if (!doc.exists) return false;

      final data = doc.data();
      final subscription = data?['subscription'] as Map<String, dynamic>?;

      if (subscription == null) return false;

      final isActive = subscription['isActive'] as bool? ?? false;
      final expiryDate = subscription['expiryDate'] as Timestamp?;

      if (!isActive) return false;

      // Check if subscription has expired
      if (expiryDate != null) {
        final now = Timestamp.now();
        if (now.compareTo(expiryDate) > 0) {
          // Subscription expired, update status
          await _firestore
              .collection('Restaurent_shop')
              .doc(restaurantId)
              .update({
            'subscription.isActive': false,
          });
          return false;
        }
      }

      return true;
    } catch (e) {
      print('❌ Error checking subscription: $e');
      return false;
    }
  }

  // Get order count for restaurant
  Future<int> getOrderCount(String restaurantId) async {
    try {
      final doc = await _firestore
          .collection('Restaurent_shop')
          .doc(restaurantId)
          .get();

      if (!doc.exists) return 0;

      final data = doc.data();
      return data?['orderCount'] as int? ?? 0;
    } catch (e) {
      print('❌ Error getting order count: $e');
      return 0;
    }
  }

  // Check if first order (free)
  Future<bool> isFirstOrder(String restaurantId) async {
    final count = await getOrderCount(restaurantId);
    return count == 0;
  }

  // Increment order count
  Future<void> incrementOrderCount(String restaurantId) async {
    try {
      await _firestore
          .collection('Restaurent_shop')
          .doc(restaurantId)
          .update({
        'orderCount': FieldValue.increment(1),
      });
    } catch (e) {
      print('❌ Error incrementing order count: $e');
    }
  }

  // Activate subscription after payment
  Future<void> activateSubscription(
    String restaurantId,
    String paymentId,
    String orderId,
  ) async {
    try {
      final now = Timestamp.now();
      final expiryDate = Timestamp.fromMillisecondsSinceEpoch(
        now.millisecondsSinceEpoch + (30 * 24 * 60 * 60 * 1000), // 30 days
      );

      await _firestore
          .collection('Restaurent_shop')
          .doc(restaurantId)
          .update({
        'subscription': {
          'isActive': true,
          'expiryDate': expiryDate,
          'paymentId': paymentId,
          'orderId': orderId,
          'activatedAt': now,
          'autoPay': true,
          'amount': 99,
        },
      });

      print('✅ Subscription activated for restaurant: $restaurantId');
    } catch (e) {
      print('❌ Error activating subscription: $e');
      rethrow;
    }
  }

  // Stream subscription status
  Stream<Map<String, dynamic>> subscriptionStream(String restaurantId) {
    return _firestore
        .collection('Restaurent_shop')
        .doc(restaurantId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) {
        return {
          'isActive': false,
          'orderCount': 0,
          'isFirstOrder': true,
        };
      }

      final data = doc.data()!;
      final subscription = data['subscription'] as Map<String, dynamic>?;
      final orderCount = data['orderCount'] as int? ?? 0;

      bool isActive = false;
      if (subscription != null) {
        isActive = subscription['isActive'] as bool? ?? false;
        final status = subscription['status'] as String?;
        
        // Check status from webhook
        if (status != null && status != 'active') {
          isActive = false;
        }
        
        // Also check nextBillingDate for webhook-based subscriptions
        final nextBillingDate = subscription['nextBillingDate'] as Timestamp?;
        if (nextBillingDate != null) {
          final now = Timestamp.now();
          // If billing date passed and no recent renewal, subscription might be inactive
          // But webhook should handle this, so we trust the status
        }
      }

      return {
        'isActive': isActive,
        'orderCount': orderCount,
        'isFirstOrder': orderCount == 0,
      };
    });
  }
}

