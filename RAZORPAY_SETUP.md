# Razorpay Automatic Recurring Payments Setup

## Overview
This app implements automatic monthly subscription billing of ₹99 using Razorpay. The subscription will automatically deduct money from the user's account every month without asking.

## Current Implementation

### What's Working:
1. ✅ First payment creates a subscription record
2. ✅ Subscription details stored in Firestore
3. ✅ Auto-pay flag enabled
4. ✅ Next billing date tracked
5. ✅ Automatic renewal check service runs every 6 hours

### What Needs Server-Side Setup:

For **true automatic recurring payments**, you need to set up Razorpay Subscriptions with webhooks:

## Step 1: Create Subscription Plan in Razorpay Dashboard

1. Login to [Razorpay Dashboard](https://dashboard.razorpay.com)
2. Go to **Settings** → **Products** → **Subscriptions**
3. Click **Create Plan**
4. Fill in:
   - **Plan Name**: Monthly Subscription ₹99
   - **Amount**: ₹99
   - **Billing Period**: Monthly
   - **Plan ID**: `plan_monthly_99` (or update code to use your plan ID)

## Step 2: Set Up Webhooks

1. In Razorpay Dashboard, go to **Settings** → **Webhooks**
2. Add webhook URL: `https://your-server.com/razorpay-webhook`
3. Select events:
   - `subscription.charged`
   - `payment.captured`
   - `subscription.activated`
   - `subscription.cancelled`

## Step 3: Server-Side Webhook Handler

Your server needs to handle webhook events:

```javascript
// Example Node.js webhook handler
app.post('/razorpay-webhook', async (req, res) => {
  const { event, payload } = req.body;
  
  if (event === 'subscription.charged') {
    const { subscription_id, payment_id, entity } = payload.subscription.entity;
    
    // Update Firestore subscription
    await updateSubscriptionAfterRenewal({
      restaurantId: entity.notes.restaurantId,
      paymentId: payment_id,
    });
  }
  
  res.status(200).send('OK');
});
```

## Step 4: Update Code to Use Plan ID

Once you create the plan, update `razorpay_subscription_service.dart`:

```dart
static Future<Map<String, dynamic>?> createSubscriptionPlan() async {
  return {
    'plan_id': 'plan_XXXXXXXXXXXXX', // Your actual plan ID from Razorpay
    // ... rest of the code
  };
}
```

## How It Works

1. **First Payment**: User pays ₹99 → Subscription created → Auto-pay enabled
2. **Automatic Renewal**: Every month, Razorpay automatically:
   - Charges ₹99 from user's saved payment method
   - Sends webhook to your server
   - Server updates Firestore with new billing date
3. **No User Action Required**: Money is deducted automatically

## Firestore Structure

```
Restaurent_shop/{restaurantId}
  subscription: {
    isActive: true,
    subscriptionId: "sub_xxxxx",
    paymentId: "pay_xxxxx",
    planId: "plan_monthly_99",
    amount: 99,
    autoPay: true,
    nextBillingDate: Timestamp,
    status: "active"
  }
```

## Testing

1. Use Razorpay Test Mode first
2. Test with test cards: https://razorpay.com/docs/payments/test-cards/
3. Verify webhook events in Razorpay Dashboard → Webhooks → Events

## Important Notes

⚠️ **Security**: Never put Razorpay Secret Key in client code. All subscription creation should ideally be done on your server.

⚠️ **Webhooks are Required**: For true automatic recurring payments, Razorpay webhooks are essential. The current implementation extends subscriptions, but actual payment charging requires webhook setup.

## Current Workaround

The current code automatically extends subscriptions when the billing date passes. For production, you should:
1. Set up Razorpay webhooks
2. Move subscription creation to your server
3. Handle webhook events to update Firestore

This ensures money is actually charged automatically by Razorpay, not just subscription extended in the database.

