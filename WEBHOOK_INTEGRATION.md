# Razorpay Webhook Integration Guide

## Overview
This app uses Razorpay Payment Links for subscriptions with automatic recurring payments. The webhook at `https://razorpaywebhook-ynqe2ldztq-uc.a.run.app` handles subscription events.

## Subscription Link
- **Link**: https://rzp.io/rzp/ijIJfIa
- This link automatically creates a subscription that charges ₹99/month

## Webhook Setup

### 1. Configure Razorpay Dashboard
1. Go to [Razorpay Dashboard](https://dashboard.razorpay.com)
2. Navigate to **Settings** → **Webhooks**
3. Add webhook URL: `https://razorpaywebhook-ynqe2ldztq-uc.a.run.app`
4. Enable these events:
   - `subscription.activated` - When subscription is first activated
   - `subscription.charged` - When monthly payment is automatically charged
   - `payment.captured` - When payment is captured
   - `subscription.cancelled` - When subscription is cancelled
   - `subscription.paused` - When subscription is paused
   - `subscription.resumed` - When subscription is resumed

### 2. Server-Side Webhook Handler

Your webhook server at `https://razorpaywebhook-ynqe2ldztq-uc.a.run.app` should:

1. **Verify webhook signature** (important for security)
2. **Extract restaurant ID** from payment link notes
3. **Update Firestore** using the `WebhookSubscriptionHandler` logic

#### Example Server Code (Node.js/Express):

```javascript
const express = require('express');
const crypto = require('crypto');
const admin = require('firebase-admin');

const app = express();
app.use(express.json());

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const WEBHOOK_SECRET = 'your_razorpay_webhook_secret'; // From Razorpay Dashboard

// Verify webhook signature
function verifyWebhookSignature(body, signature) {
  const expectedSignature = crypto
    .createHmac('sha256', WEBHOOK_SECRET)
    .update(JSON.stringify(body))
    .digest('hex');
  
  return crypto.timingSafeEqual(
    Buffer.from(signature),
    Buffer.from(expectedSignature)
  );
}

app.post('/razorpay-webhook', async (req, res) => {
  const signature = req.headers['x-razorpay-signature'];
  const body = req.body;

  // Verify signature
  if (!verifyWebhookSignature(body, signature)) {
    return res.status(401).send('Invalid signature');
  }

  const event = body.event;
  const payload = body.payload;

  try {
    // Extract restaurant ID from notes
    let restaurantId = null;
    
    if (payload.subscription?.entity?.notes?.restaurantId) {
      restaurantId = payload.subscription.entity.notes.restaurantId;
    } else if (payload.payment?.entity?.notes?.restaurantId) {
      restaurantId = payload.payment.entity.notes.restaurantId;
    }

    if (!restaurantId) {
      console.log('No restaurant ID found in webhook payload');
      return res.status(400).send('Restaurant ID not found');
    }

    // Update Firestore based on event
    const db = admin.firestore();
    const restaurantRef = db.collection('Restaurent_shop').doc(restaurantId);

    switch (event) {
      case 'subscription.activated':
        const subscription = payload.subscription.entity;
        await restaurantRef.update({
          subscription: {
            isActive: subscription.status === 'active',
            subscriptionId: subscription.id,
            planId: subscription.plan_id,
            customerId: subscription.customer_id,
            amount: 99,
            currency: 'INR',
            interval: 'monthly',
            nextBillingDate: admin.firestore.Timestamp.fromMillis(
              subscription.current_end * 1000
            ),
            autoPay: true,
            activatedAt: admin.firestore.FieldValue.serverTimestamp(),
            status: subscription.status,
            webhookEvent: 'subscription.activated',
          },
          pendingSubscription: admin.firestore.FieldValue.delete(),
        });

        // Log payment
        if (payload.subscription.payment?.entity) {
          const payment = payload.subscription.payment.entity;
          await restaurantRef.collection('payments').add({
            paymentId: payment.id,
            subscriptionId: subscription.id,
            amount: 99,
            type: 'initial',
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            status: 'success',
            webhookEvent: 'subscription.activated',
          });
        }
        break;

      case 'subscription.charged':
        const chargedSub = payload.subscription.entity;
        await restaurantRef.update({
          'subscription.nextBillingDate': admin.firestore.Timestamp.fromMillis(
            chargedSub.current_end * 1000
          ),
          'subscription.lastRenewalAt': admin.firestore.FieldValue.serverTimestamp(),
          'subscription.isActive': chargedSub.status === 'active',
          'subscription.status': chargedSub.status,
          'subscription.webhookEvent': 'subscription.charged',
        });

        // Log renewal payment
        if (payload.subscription.payment?.entity) {
          const payment = payload.subscription.payment.entity;
          await restaurantRef.update({
            'subscription.lastPaymentId': payment.id,
          });
          await restaurantRef.collection('payments').add({
            paymentId: payment.id,
            subscriptionId: chargedSub.id,
            amount: 99,
            type: 'renewal',
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            status: 'success',
            webhookEvent: 'subscription.charged',
          });
        }
        break;

      case 'subscription.cancelled':
        await restaurantRef.update({
          'subscription.isActive': false,
          'subscription.status': 'cancelled',
          'subscription.cancelledAt': admin.firestore.FieldValue.serverTimestamp(),
          'subscription.webhookEvent': 'subscription.cancelled',
        });
        break;

      // Handle other events...
    }

    res.status(200).send('OK');
  } catch (error) {
    console.error('Webhook error:', error);
    res.status(500).send('Error processing webhook');
  }
});

app.listen(process.env.PORT || 8080);
```

### 3. Add Restaurant ID to Payment Link Notes

**Important**: When creating the payment link in Razorpay Dashboard, make sure to add notes:
- Go to Payment Links → Edit your subscription link
- Add custom fields/notes:
  - `restaurantId`: Will be set dynamically by the app
  - Or configure the link to accept `restaurantId` as a parameter

Alternatively, update the payment link to accept restaurant ID as a query parameter and pass it when opening the link.

## How It Works

1. **User clicks Subscribe**:
   - App stores `pendingSubscription` in Firestore with restaurant ID
   - Opens Razorpay subscription link: `https://rzp.io/rzp/ijIJfIa`

2. **User completes payment**:
   - Razorpay processes payment and creates subscription
   - Razorpay sends webhook to your server

3. **Webhook processes event**:
   - Server verifies signature
   - Extracts restaurant ID from notes or Firestore `pendingSubscription`
   - Updates Firestore subscription status

4. **Automatic renewals**:
   - Razorpay automatically charges ₹99 every month
   - Sends `subscription.charged` webhook
   - Server updates `nextBillingDate` and logs payment

## Firestore Structure

```
Restaurent_shop/{restaurantId}
  subscription: {
    isActive: true,
    subscriptionId: "sub_xxxxx",
    planId: "plan_xxxxx",
    customerId: "cust_xxxxx",
    amount: 99,
    currency: "INR",
    interval: "monthly",
    nextBillingDate: Timestamp,
    autoPay: true,
    status: "active",
    activatedAt: Timestamp,
    lastRenewalAt: Timestamp,
    lastPaymentId: "pay_xxxxx",
    webhookEvent: "subscription.charged"
  }
  pendingSubscription: {
    restaurantId: "...",
    driverAuthId: "...",
    phone: "...",
    initiatedAt: Timestamp
  }
  payments/{paymentId}
    paymentId: "pay_xxxxx",
    subscriptionId: "sub_xxxxx",
    amount: 99,
    type: "initial" | "renewal",
    timestamp: Timestamp,
    status: "success",
    webhookEvent: "..."
```

## Testing

1. Use Razorpay Test Mode
2. Test webhook events using Razorpay Dashboard → Webhooks → Test Webhook
3. Verify Firestore updates in real-time
4. Check subscription status in app

## Security Notes

- ✅ Always verify webhook signature
- ✅ Never trust client-side data
- ✅ Use Firebase Admin SDK on server
- ✅ Validate all webhook payloads
- ✅ Log all webhook events for debugging

