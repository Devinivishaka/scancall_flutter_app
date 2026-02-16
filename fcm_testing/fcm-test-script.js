const admin = require('firebase-admin');
const path = require('path');
require('dotenv').config();

// Configuration - Update these values
const CONFIG = {
  // Path to your Firebase service account key JSON file
  serviceAccountPath: './service-account-key.json',

  // FCM Token from your Flutter app (get this from app logs)
  fcmToken: process.env.FCM_TOKEN || 'YOUR_FCM_TOKEN_HERE',

  // Default call settings
  defaultCallId: `call_${Date.now()}`,
  defaultCallerName: 'Test Caller',
  defaultCallerAvatar: 'https://via.placeholder.com/150/0000FF/808080?Text=Caller'
};

// Initialize Firebase Admin SDK
function initializeFirebase() {
  try {
    const serviceAccountPath = path.resolve(CONFIG.serviceAccountPath);
    const serviceAccount = require(serviceAccountPath);

    if (admin.apps.length === 0) {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
      });
      console.log('✅ Firebase Admin SDK initialized successfully');
    }
  } catch (error) {
    console.error('❌ Firebase initialization failed:', error.message);
    console.log('\n📋 Setup Steps:');
    console.log('1. Download your Firebase service account key from Firebase Console');
    console.log('2. Save it as "service-account-key.json" in this folder');
    console.log('3. Update FCM_TOKEN in .env file or script');
    process.exit(1);
  }
}

/**
 * Send an incoming call FCM message
 * @param {string} fcmToken - The FCM token from your Flutter app
 * @param {string} callId - Unique identifier for the call (will be used as room name)
 * @param {string} callerName - Name of the caller to display
 * @param {string} callerAvatar - Optional avatar URL
 */
async function sendIncomingCall(fcmToken, callId, callerName, callerAvatar = null) {
  console.log('\n📞 Sending incoming call notification...');
  console.log(`   Call ID: ${callId}`);
  console.log(`   Caller: ${callerName}`);
  console.log(`   FCM Token: ${fcmToken.substring(0, 20)}...`);

  const message = {
    token: fcmToken,
    data: {
      type: 'incoming_call',
      callId: callId,
      callerName: callerName,
      ...(callerAvatar && { callerAvatar })
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'incoming_call_channel'
      }
    },
    apns: {
      headers: {
        'apns-priority': '10'
      },
      payload: {
        aps: {
          contentAvailable: true,
          category: 'CALL_CATEGORY'
        }
      }
    }
  };

  try {
    const response = await admin.messaging().send(message);
    console.log('✅ Incoming call sent successfully!');
    console.log(`   Message ID: ${response}`);
    return response;
  } catch (error) {
    console.error('❌ Error sending incoming call:', error.message);
    if (error.code === 'messaging/registration-token-not-registered') {
      console.log('💡 This usually means the FCM token is invalid or expired');
      console.log('   Get a fresh token from your Flutter app logs');
    }
    throw error;
  }
}

/**
 * Send a call cancel FCM message
 * @param {string} fcmToken - The FCM token from your Flutter app
 * @param {string} callId - The call ID to cancel
 */
async function sendCallCancel(fcmToken, callId) {
  console.log('\n🚫 Sending call cancel notification...');
  console.log(`   Call ID: ${callId}`);

  const message = {
    token: fcmToken,
    data: {
      type: 'call_cancel',
      callId: callId
    },
    android: {
      priority: 'high'
    },
    apns: {
      headers: {
        'apns-priority': '10'
      }
    }
  };

  try {
    const response = await admin.messaging().send(message);
    console.log('✅ Call cancel sent successfully!');
    console.log(`   Message ID: ${response}`);
    return response;
  } catch (error) {
    console.error('❌ Error sending call cancel:', error.message);
    throw error;
  }
}

/**
 * Interactive testing menu
 */
async function interactiveTest() {
  console.log('\n🧪 ScanCall FCM Interactive Testing');
  console.log('==================================');

  if (CONFIG.fcmToken === 'YOUR_FCM_TOKEN_HERE') {
    console.log('⚠️  FCM Token not configured!');
    console.log('   1. Run your Flutter app');
    console.log('   2. Look for: 🔑 FCM Registration Token: [token]');
    console.log('   3. Copy the token and update CONFIG.fcmToken or .env file');
    return;
  }

  const callId = CONFIG.defaultCallId;

  try {
    // Send incoming call
    await sendIncomingCall(
      CONFIG.fcmToken,
      callId,
      CONFIG.defaultCallerName,
      CONFIG.defaultCallerAvatar
    );

    console.log('\n⏰ Call will auto-cancel in 30 seconds...');
    console.log('   (Check your app for the incoming call UI)');

    // Auto-cancel after 30 seconds
    setTimeout(async () => {
      try {
        await sendCallCancel(CONFIG.fcmToken, callId);
        console.log('\n✨ Test completed successfully!');
        process.exit(0);
      } catch (error) {
        console.error('Error during auto-cancel:', error.message);
        process.exit(1);
      }
    }, 30000);

  } catch (error) {
    console.error('Test failed:', error.message);
    process.exit(1);
  }
}

/**
 * Command line argument handling
 */
async function handleCommands() {
  const args = process.argv.slice(2);
  const command = args[0];

  if (!command) {
    await interactiveTest();
    return;
  }

  const callId = args[1] || CONFIG.defaultCallId;
  const callerName = args[2] || CONFIG.defaultCallerName;

  switch (command.toLowerCase()) {
    case 'call':
      await sendIncomingCall(CONFIG.fcmToken, callId, callerName, CONFIG.defaultCallerAvatar);
      console.log(`\n💡 To cancel this call, run: npm run test-cancel ${callId}`);
      break;

    case 'cancel':
      await sendCallCancel(CONFIG.fcmToken, callId);
      break;

    default:
      console.log('❌ Unknown command. Usage:');
      console.log('   npm test                    - Interactive testing');
      console.log('   npm run test-call [id] [name] - Send incoming call');
      console.log('   npm run test-cancel [id]   - Cancel call');
      break;
  }
}

// Main execution
async function main() {
  console.log('🚀 ScanCall FCM Testing Tool');
  console.log('============================');

  initializeFirebase();
  await handleCommands();
}

// Export functions for external use
module.exports = {
  sendIncomingCall,
  sendCallCancel,
  initializeFirebase
};

// Run if called directly
if (require.main === module) {
  main().catch(error => {
    console.error('❌ Script failed:', error.message);
    process.exit(1);
  });
}
