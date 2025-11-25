import 'package:cloud_firestore/cloud_firestore.dart';

/// Handles Razorpay webhook events for subscription management
/// Webhook URL: https://razorpaywebhook-ynqe2ldztq-uc.a.run.app
class WebhookSubscriptionHandler {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Process webhook event from Razorpay
  /// This should be called by your server/webhook endpoint
  /// The server receives webhook and updates Firestore
  static Future<void> handleWebhookEvent(Map<String, dynamic> eventData) async {
    try {
      final event = eventData['event'] as String?;
      final payload = eventData['payload'] as Map<String, dynamic>?;

      if (payload == null) {
        print('❌ Webhook payload is null');
        return;
      }

      print('📥 Processing webhook event: $event');

      switch (event) {
        case 'subscription.activated':
          await _handleSubscriptionActivated(payload);
          break;
        case 'subscription.charged':
          await _handleSubscriptionCharged(payload);
          break;
        case 'payment.captured':
          await _handlePaymentCaptured(payload);
          break;
        case 'subscription.cancelled':
          await _handleSubscriptionCancelled(payload);
          break;
        case 'subscription.paused':
          await _handleSubscriptionPaused(payload);
          break;
        case 'subscription.resumed':
          await _handleSubscriptionResumed(payload);
          break;
        default:
          print('⚠️ Unhandled webhook event: $event');
      }
    } catch (e) {
      print('❌ Error handling webhook event: $e');
    }
  }

  /// Handle subscription activation (first payment)
  static Future<void> _handleSubscriptionActivated(
      Map<String, dynamic> payload) async {
    try {
      final subscription = payload['subscription'] as Map<String, dynamic>?;
      final entity = subscription?['entity'] as Map<String, dynamic>?;
      final notes = entity?['notes'] as Map<String, dynamic>?;

      if (notes == null) {
        print('❌ No notes in subscription entity');
        return;
      }

      final restaurantId = notes['restaurantId'] as String?;
      if (restaurantId == null || restaurantId.isEmpty) {
        print('❌ Restaurant ID not found in subscription notes');
        return;
      }

      final subscriptionId = entity?['id'] as String? ?? '';
      final planId = entity?['plan_id'] as String? ?? '';
      final customerId = entity?['customer_id'] as String? ?? '';
      final status = entity?['status'] as String? ?? '';

      final now = Timestamp.now();
      final currentEnd = entity?['current_end'] as int?;
      final nextBillingDate = currentEnd != null
          ? Timestamp.fromMillisecondsSinceEpoch(currentEnd * 1000)
          : Timestamp.fromMillisecondsSinceEpoch(
              now.millisecondsSinceEpoch + (30 * 24 * 60 * 60 * 1000));

      // Update subscription in Firestore
      await _firestore
          .collection('Restaurent_shop')
          .doc(restaurantId)
          .update({
        'subscription': {
          'isActive': status == 'active',
          'subscriptionId': subscriptionId,
          'planId': planId,
          'customerId': customerId,
          'amount': 99,
          'currency': 'INR',
          'interval': 'monthly',
          'nextBillingDate': nextBillingDate,
          'autoPay': true,
          'activatedAt': now,
          'status': status,
          'webhookEvent': 'subscription.activated',
        },
        'pendingSubscription': FieldValue.delete(),
      });

      // Log payment
      final payment = subscription?['payment'] as Map<String, dynamic>?;
      if (payment != null) {
        final paymentEntity = payment['entity'] as Map<String, dynamic>?;
        final paymentId = paymentEntity?['id'] as String? ?? '';

        await _firestore
            .collection('Restaurent_shop')
            .doc(restaurantId)
            .collection('payments')
            .add({
          'paymentId': paymentId,
          'subscriptionId': subscriptionId,
          'amount': 99,
          'type': 'initial',
          'timestamp': now,
          'status': 'success',
          'webhookEvent': 'subscription.activated',
        });
      }

      print('✅ Subscription activated for restaurant: $restaurantId');
    } catch (e) {
      print('❌ Error handling subscription activation: $e');
    }
  }

  /// Handle subscription charged (recurring payment)
  static Future<void> _handleSubscriptionCharged(
      Map<String, dynamic> payload) async {
    try {
      final subscription = payload['subscription'] as Map<String, dynamic>?;
      final entity = subscription?['entity'] as Map<String, dynamic>?;
      final notes = entity?['notes'] as Map<String, dynamic>?;

      if (notes == null) {
        print('❌ No notes in subscription entity');
        return;
      }

      final restaurantId = notes['restaurantId'] as String?;
      if (restaurantId == null || restaurantId.isEmpty) {
        print('❌ Restaurant ID not found in subscription notes');
        return;
      }

      final subscriptionId = entity?['id'] as String? ?? '';
      final currentEnd = entity?['current_end'] as int?;
      final status = entity?['status'] as String? ?? '';

      final now = Timestamp.now();
      final nextBillingDate = currentEnd != null
          ? Timestamp.fromMillisecondsSinceEpoch(currentEnd * 1000)
          : Timestamp.fromMillisecondsSinceEpoch(
              now.millisecondsSinceEpoch + (30 * 24 * 60 * 60 * 1000));

      // Update subscription with new billing date
      await _firestore
          .collection('Restaurent_shop')
          .doc(restaurantId)
          .update({
        'subscription.nextBillingDate': nextBillingDate,
        'subscription.lastRenewalAt': now,
        'subscription.isActive': status == 'active',
        'subscription.status': status,
        'subscription.webhookEvent': 'subscription.charged',
      });

      // Log renewal payment
      final payment = subscription?['payment'] as Map<String, dynamic>?;
      if (payment != null) {
        final paymentEntity = payment['entity'] as Map<String, dynamic>?;
        final paymentId = paymentEntity?['id'] as String? ?? '';

        await _firestore
            .collection('Restaurent_shop')
            .doc(restaurantId)
            .update({
          'subscription.lastPaymentId': paymentId,
        });

        await _firestore
            .collection('Restaurent_shop')
            .doc(restaurantId)
            .collection('payments')
            .add({
          'paymentId': paymentId,
          'subscriptionId': subscriptionId,
          'amount': 99,
          'type': 'renewal',
          'timestamp': now,
          'status': 'success',
          'webhookEvent': 'subscription.charged',
        });
      }

      print('✅ Subscription charged (renewed) for restaurant: $restaurantId');
    } catch (e) {
      print('❌ Error handling subscription charged: $e');
    }
  }

  /// Handle payment captured
  static Future<void> _handlePaymentCaptured(
      Map<String, dynamic> payload) async {
    try {
      final payment = payload['payment'] as Map<String, dynamic>?;
      final entity = payment?['entity'] as Map<String, dynamic>?;
      final notes = entity?['notes'] as Map<String, dynamic>?;

      if (notes == null) return;

      final restaurantId = notes['restaurantId'] as String?;
      if (restaurantId == null || restaurantId.isEmpty) return;

      final paymentId = entity?['id'] as String? ?? '';
      final amount = (entity?['amount'] as int? ?? 0) / 100; // Convert paise to rupees

      // Log payment
      await _firestore
          .collection('Restaurent_shop')
          .doc(restaurantId)
          .collection('payments')
          .add({
        'paymentId': paymentId,
        'amount': amount,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'captured',
        'webhookEvent': 'payment.captured',
      });

      print('✅ Payment captured for restaurant: $restaurantId');
    } catch (e) {
      print('❌ Error handling payment captured: $e');
    }
  }

  /// Handle subscription cancelled
  static Future<void> _handleSubscriptionCancelled(
      Map<String, dynamic> payload) async {
    try {
      final subscription = payload['subscription'] as Map<String, dynamic>?;
      final entity = subscription?['entity'] as Map<String, dynamic>?;
      final notes = entity?['notes'] as Map<String, dynamic>?;

      if (notes == null) return;

      final restaurantId = notes['restaurantId'] as String?;
      if (restaurantId == null || restaurantId.isEmpty) return;

      await _firestore
          .collection('Restaurent_shop')
          .doc(restaurantId)
          .update({
        'subscription.isActive': false,
        'subscription.status': 'cancelled',
        'subscription.cancelledAt': FieldValue.serverTimestamp(),
        'subscription.webhookEvent': 'subscription.cancelled',
      });

      print('✅ Subscription cancelled for restaurant: $restaurantId');
    } catch (e) {
      print('❌ Error handling subscription cancelled: $e');
    }
  }

  /// Handle subscription paused
  static Future<void> _handleSubscriptionPaused(
      Map<String, dynamic> payload) async {
    try {
      final subscription = payload['subscription'] as Map<String, dynamic>?;
      final entity = subscription?['entity'] as Map<String, dynamic>?;
      final notes = entity?['notes'] as Map<String, dynamic>?;

      if (notes == null) return;

      final restaurantId = notes['restaurantId'] as String?;
      if (restaurantId == null || restaurantId.isEmpty) return;

      await _firestore
          .collection('Restaurent_shop')
          .doc(restaurantId)
          .update({
        'subscription.isActive': false,
        'subscription.status': 'paused',
        'subscription.pausedAt': FieldValue.serverTimestamp(),
        'subscription.webhookEvent': 'subscription.paused',
      });

      print('✅ Subscription paused for restaurant: $restaurantId');
    } catch (e) {
      print('❌ Error handling subscription paused: $e');
    }
  }

  /// Handle subscription resumed
  static Future<void> _handleSubscriptionResumed(
      Map<String, dynamic> payload) async {
    try {
      final subscription = payload['subscription'] as Map<String, dynamic>?;
      final entity = subscription?['entity'] as Map<String, dynamic>?;
      final notes = entity?['notes'] as Map<String, dynamic>?;

      if (notes == null) return;

      final restaurantId = notes['restaurantId'] as String?;
      if (restaurantId == null || restaurantId.isEmpty) return;

      await _firestore
          .collection('Restaurent_shop')
          .doc(restaurantId)
          .update({
        'subscription.isActive': true,
        'subscription.status': 'active',
        'subscription.resumedAt': FieldValue.serverTimestamp(),
        'subscription.webhookEvent': 'subscription.resumed',
      });

      print('✅ Subscription resumed for restaurant: $restaurantId');
    } catch (e) {
      print('❌ Error handling subscription resumed: $e');
    }
  }
}

