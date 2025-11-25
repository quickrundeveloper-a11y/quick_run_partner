const functions = require("firebase-functions/v2");
const admin = require("firebase-admin");
const crypto = require("crypto");

admin.initializeApp();

const db = admin.firestore();

function verifyRazorpaySignature(req) {
  const secret = process.env.RAZORPAY_WEBHOOK_SECRET;
  const signature = req.headers["x-razorpay-signature"];

  if (!secret || !signature) {
    console.error("❌ Missing Razorpay secret or signature header");
    return false;
  }

  const body = JSON.stringify(req.body);

  const expectedSignature = crypto
    .createHmac("sha256", secret)
    .update(body)
    .digest("hex");

  const isValid = crypto.timingSafeEqual(
    Buffer.from(signature),
    Buffer.from(expectedSignature)
  );

  if (!isValid) {
    console.error("❌ Signature mismatch");
  }

  return isValid;
}

/**
 * Helper to resolve restaurantId from Razorpay payload.
 * We try several places:
 *  1. payload.subscription.entity.notes.restaurantId
 *  2. payload.payment.entity.notes.restaurantId
 *  3. Fallback: look up most recent pendingSubscription for this driver/phone
 */
async function resolveRestaurantId(body) {
  const payload = body.payload || {};

  // 1. From subscription notes
  if (
    payload.subscription &&
    payload.subscription.entity &&
    payload.subscription.entity.notes &&
    payload.subscription.entity.notes.restaurantId
  ) {
    return payload.subscription.entity.notes.restaurantId;
  }

  // 2. From payment notes
  if (
    payload.payment &&
    payload.payment.entity &&
    payload.payment.entity.notes &&
    payload.payment.entity.notes.restaurantId
  ) {
    return payload.payment.entity.notes.restaurantId;
  }

  // 3. Fallback: try to infer from phone / driverId saved in pendingSubscription
  const phone =
    payload.payment?.entity?.contact ||
    payload.payment?.entity?.email ||
    null;

  if (phone) {
    const snap = await db
      .collection("Restaurent_shop")
      .where("pendingSubscription.phone", "==", phone)
      .orderBy("pendingSubscription.initiatedAt", "desc")
      .limit(1)
      .get();

    if (!snap.empty) {
      return snap.docs[0].id;
    }
  }

  return null;
}

async function handleSubscriptionActivated(body) {
  const subscription = body.payload.subscription.entity;
  const payment = body.payload.subscription.payment?.entity;

  const restaurantId = await resolveRestaurantId(body);
  if (!restaurantId) {
    console.error("❌ subscription.activated: restaurantId not found");
    return;
  }

  const restaurantRef = db.collection("Restaurent_shop").doc(restaurantId);

  const nextBillingDate = admin.firestore.Timestamp.fromMillis(
    subscription.current_end * 1000
  );

  const subscriptionData = {
    isActive: subscription.status === "active",
    subscriptionId: subscription.id,
    planId: subscription.plan_id,
    customerId: subscription.customer_id,
    amount: 99,
    currency: "INR",
    interval: "monthly",
    nextBillingDate,
    autoPay: true,
    activatedAt: admin.firestore.FieldValue.serverTimestamp(),
    status: subscription.status,
    webhookEvent: "subscription.activated",
  };

  const batch = db.batch();
  batch.update(restaurantRef, {
    subscription: subscriptionData,
    pendingSubscription: admin.firestore.FieldValue.delete(),
  });

  if (payment) {
    const paymentsRef = restaurantRef.collection("payments").doc();
    batch.set(paymentsRef, {
      paymentId: payment.id,
      subscriptionId: subscription.id,
      amount: 99,
      type: "initial",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      status: "success",
      webhookEvent: "subscription.activated",
    });
  }

  await batch.commit();
  console.log("✅ subscription.activated processed for", restaurantId);
}

async function handleSubscriptionCharged(body) {
  const subscription = body.payload.subscription.entity;
  const payment = body.payload.subscription.payment?.entity;

  const restaurantId = await resolveRestaurantId(body);
  if (!restaurantId) {
    console.error("❌ subscription.charged: restaurantId not found");
    return;
  }

  const restaurantRef = db.collection("Restaurent_shop").doc(restaurantId);

  const nextBillingDate = admin.firestore.Timestamp.fromMillis(
    subscription.current_end * 1000
  );

  const updates = {
    "subscription.nextBillingDate": nextBillingDate,
    "subscription.lastRenewalAt": admin.firestore.FieldValue.serverTimestamp(),
    "subscription.isActive": subscription.status === "active",
    "subscription.status": subscription.status,
    "subscription.webhookEvent": "subscription.charged",
  };

  const batch = db.batch();
  batch.update(restaurantRef, updates);

  if (payment) {
    const paymentsRef = restaurantRef.collection("payments").doc();
    batch.update(restaurantRef, {
      "subscription.lastPaymentId": payment.id,
    });
    batch.set(paymentsRef, {
      paymentId: payment.id,
      subscriptionId: subscription.id,
      amount: 99,
      type: "renewal",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      status: "success",
      webhookEvent: "subscription.charged",
    });
  }

  await batch.commit();
  console.log("✅ subscription.charged processed for", restaurantId);
}

async function handleSubscriptionCancelled(body) {
  const restaurantId = await resolveRestaurantId(body);
  if (!restaurantId) {
    console.error("❌ subscription.cancelled: restaurantId not found");
    return;
  }

  const restaurantRef = db.collection("Restaurent_shop").doc(restaurantId);
  await restaurantRef.update({
    "subscription.isActive": false,
    "subscription.status": "cancelled",
    "subscription.cancelledAt": admin.firestore.FieldValue.serverTimestamp(),
    "subscription.webhookEvent": "subscription.cancelled",
  });

  console.log("✅ subscription.cancelled processed for", restaurantId);
}

exports.razorpayWebhook = functions.https.onRequest(
  {
    region: "us-central1",
  },
  async (req, res) => {
    try {
      console.log("✅ Razorpay webhook received");

      // Razorpay sends only POST for webhooks
      if (req.method !== "POST") {
        return res.status(405).send("Method Not Allowed");
      }

      const event = req.body?.event;

      if (!event) {
        console.error("❌ Missing event in payload");
        return res.status(400).send("Invalid payload");
      }

      const isValid = verifyRazorpaySignature(req);
      if (!isValid) {
        return res.status(401).send("Invalid signature");
      }

      console.log("🔔 Event:", event);

      switch (event) {
        case "subscription.activated":
          await handleSubscriptionActivated(req.body);
          break;
        case "subscription.charged":
          await handleSubscriptionCharged(req.body);
          break;
        case "subscription.cancelled":
          await handleSubscriptionCancelled(req.body);
          break;
        default:
          console.log("ℹ️ Unhandled event type:", event);
      }

      res.status(200).send("OK");
    } catch (err) {
      console.error("❌ Webhook error", err);
      res.status(500).send("Error");
    }
  }
);

/**
 * NEW ORDER -> FCM (DATA-ONLY) delivery for SELLERS (restaurants)
 *
 * Why:
 * - SellerHome's Firestore polling/UI does not run when app is background/terminated.
 * - We must wake the device via native FCM -> QuickRunMessagingService -> FloatingService overlay.
 *
 * Delivery rules:
 * - DATA payload only (no `notification` block)
 * - high priority
 * - include `type=NEW_ORDER`, `orderId`, and `mode=seller`
 *
 * Targeting:
 * - Extract unique `restaurentId` from `items[]`
 * - Send to Restaurent_shop/{restaurentId}.fcmId (if activeShop == true)
 */
exports.notifyNewOrderSeller = functions.firestore.onDocumentCreated(
  {
    document: "Customer/{customerId}/current_order/{orderId}",
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const orderId = event.params.orderId;
    const customerId = event.params.customerId;
    const data = snap.data() || {};

    if (!orderId) {
      console.warn("[notifyNewOrderSeller] Missing orderId param");
      return;
    }

    // If order already accepted (driver/restaurant), don't spam.
    if (
      data.acceptedBy ||
      data.driverId ||
      data.status === "accepted" ||
      data.restaurentAccpetedId
    ) {
      console.log("[notifyNewOrderSeller] Order already accepted, skipping push", {
        orderId,
        customerId,
      });
      return;
    }

    const items = Array.isArray(data.items) ? data.items : [];
    const restIds = new Set();
    for (const it of items) {
      if (!it) continue;
      const rid = String(it.restaurentId || it.restaurantId || "").trim();
      if (rid) restIds.add(rid);
    }

    if (restIds.size === 0) {
      console.log("[notifyNewOrderSeller] No restaurentId found in items; skipping", {
        orderId,
        customerId,
      });
      return;
    }

    // Fetch restaurant docs by id and collect tokens.
    const refs = [...restIds].map((id) => db.collection("Restaurent_shop").doc(id));
    const snaps = await db.getAll(...refs);

    const tokens = [];
    for (const r of snaps) {
      if (!r.exists) continue;
      const rd = r.data() || {};
      if (rd.activeShop !== true) continue;
      if (rd.fcmId && typeof rd.fcmId === "string" && rd.fcmId.trim().length > 0) {
        tokens.push(rd.fcmId.trim());
      }
    }

    if (tokens.length === 0) {
      console.log("[notifyNewOrderSeller] No active restaurants with fcmId found", {
        orderId,
        customerId,
        restIds: [...restIds].slice(0, 20),
      });
      return;
    }

    // Keep payload strings only.
    const msgData = {
      type: "NEW_ORDER",
      mode: "seller",
      orderId: String(orderId),
      customerId: String(customerId),
      title: "New Order",
      body: "You have a new order",
    };

    let sent = 0;
    let failed = 0;

    for (let i = 0; i < tokens.length; i += 500) {
      const batch = tokens.slice(i, i + 500);
      const response = await admin.messaging().sendEachForMulticast({
        tokens: batch,
        data: msgData,
        android: {
          priority: "high",
        },
      });
      sent += response.successCount;
      failed += response.failureCount;

      if (response.failureCount > 0) {
        console.warn("[notifyNewOrderSeller] Some sends failed", {
          orderId,
          customerId,
          failures: response.responses
            .map((r, idx) => ({ ok: r.success, idx, err: r.error?.message }))
            .filter((x) => !x.ok)
            .slice(0, 20),
        });
      }
    }

    console.log("[notifyNewOrderSeller] Push complete", {
      orderId,
      customerId,
      restaurants: restIds.size,
      tokens: tokens.length,
      sent,
      failed,
    });
  }
);

/**
 * NEW ORDER -> FCM (DATA-ONLY) delivery
 *
 * Why this exists:
 * - Firestore listeners do NOT run when the app is background/terminated.
 * - Driver apps must be woken up by FCM data messages (high priority).
 *
 * Requirements for reliable Android delivery:
 * - Use DATA payload only (do NOT depend on `notification` block).
 * - Use high priority.
 * - Include `type=NEW_ORDER` and `orderId` (mandatory) so the app can decide
 *   to show the full-screen / heads-up local notification.
 *
 * Firestore path:
 *   Customer/{customerId}/current_order/{orderId}
 *
 * Current app behavior:
 * - Orders are broadcast and drivers filter by distance/acceptance in-app.
 * - Here we notify ALL active drivers who have an fcmId saved.
 *   (You can later optimize to nearby drivers only if you store driver locations
 *    in a queryable way.)
 */
exports.notifyNewOrder = functions.firestore.onDocumentCreated(
  {
    document: "Customer/{customerId}/current_order/{orderId}",
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const orderId = event.params.orderId;
    const customerId = event.params.customerId;
    const data = snap.data() || {};

    // Safety: ensure order exists before sending.
    if (!orderId) {
      console.warn("[notifyNewOrder] Missing orderId param");
      return;
    }

    // If order already accepted, don't spam everyone.
    if (data.acceptedBy || data.driverId || data.status === "accepted") {
      console.log("[notifyNewOrder] Order already accepted, skipping push", {
        orderId,
        customerId,
      });
      return;
    }

    // Fetch active drivers who have FCM tokens saved.
    // NOTE: if you store tokens elsewhere, update this query accordingly.
    const driversSnap = await db
      .collection("QuickRunDrivers")
      .where("activeDriver", "==", true)
      .get();

    const tokens = [];
    for (const doc of driversSnap.docs) {
      const d = doc.data() || {};
      if (d.fcmId && typeof d.fcmId === "string" && d.fcmId.trim().length > 0) {
        tokens.push(d.fcmId.trim());
      }
    }

    if (tokens.length === 0) {
      console.log("[notifyNewOrder] No active drivers with fcmId found", {
        orderId,
        customerId,
      });
      return;
    }

    // Firebase Admin requires strings in data payload.
    const msgData = {
      type: "NEW_ORDER",
      orderId: String(orderId),
      customerId: String(customerId),
      title: "New Order",
      body: "You have a new order",
    };

    // Send in batches of 500 (FCM limit).
    let sent = 0;
    let failed = 0;

    for (let i = 0; i < tokens.length; i += 500) {
      const batch = tokens.slice(i, i + 500);
      const response = await admin.messaging().sendEachForMulticast({
        tokens: batch,
        data: msgData, // DATA-ONLY
        android: {
          priority: "high",
        },
      });
      sent += response.successCount;
      failed += response.failureCount;

      if (response.failureCount > 0) {
        console.warn("[notifyNewOrder] Some sends failed", {
          orderId,
          customerId,
          failures: response.responses
            .map((r, idx) => ({ ok: r.success, idx, err: r.error?.message }))
            .filter((x) => !x.ok)
            .slice(0, 20),
        });
      }
    }

    console.log("[notifyNewOrder] Push complete", {
      orderId,
      customerId,
      tokens: tokens.length,
      sent,
      failed,
    });
  }
);