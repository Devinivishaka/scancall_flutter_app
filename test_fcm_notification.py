#!/usr/bin/env python3
"""
Test script to send FCM notifications for incoming calls.

Usage:
    python test_fcm_notification.py <FCM_TOKEN>

Requirements:
    pip install requests
"""

import sys
import requests
import json

# Your Firebase Server Key from Firebase Console > Project Settings > Cloud Messaging
# Go to: https://console.firebase.google.com/project/scancall-f8c81/settings/cloudmessaging
# WARNING: Keep this key secret! Do not commit it to version control.
SERVER_KEY = "YOUR_FIREBASE_SERVER_KEY_HERE"

def send_fcm_notification(fcm_token, caller_name="John Doe", call_id=None):
    """
    Send a test FCM notification for an incoming call.

    Args:
        fcm_token: The FCM registration token from the device
        caller_name: Name of the caller to display
        call_id: Unique call ID (will be auto-generated if not provided)
    """
    if call_id is None:
        import time
        call_id = str(int(time.time() * 1000))

    # FCM endpoint
    url = "https://fcm.googleapis.com/fcm/send"

    # Headers
    headers = {
        "Authorization": f"Bearer {SERVER_KEY}",
        "Content-Type": "application/json",
    }

    # Payload - IMPORTANT: Only send 'data' payload, NOT 'notification'
    # The 'notification' payload shows a heads-up notification instead of triggering our handler
    payload = {
        "to": fcm_token,
        "priority": "high",
        "data": {
            "type": "incoming_call",
            "callId": call_id,
            "callerName": caller_name,
            "callerId": "+1234567890",
            "isVideo": "false",
            "avatar": "",
        }
    }

    print("═══════════════════════════════════════════════════════════")
    print("🚀 Sending FCM Notification")
    print("═══════════════════════════════════════════════════════════")
    print(f"   To Token: {fcm_token[:20]}...{fcm_token[-20:]}")
    print(f"   Caller Name: {caller_name}")
    print(f"   Call ID: {call_id}")
    print("═══════════════════════════════════════════════════════════")

    # Send the request
    response = requests.post(url, headers=headers, data=json.dumps(payload))

    # Check response
    if response.status_code == 200:
        result = response.json()
        print("✅ Notification sent successfully!")
        print(f"   Response: {json.dumps(result, indent=2)}")
        print("═══════════════════════════════════════════════════════════")
        if result.get('success') == 1:
            print("✅ FCM confirmed delivery")
        elif result.get('failure') == 1:
            print("❌ FCM reported failure:")
            print(f"   {result.get('results', [{}])[0].get('error', 'Unknown error')}")
    else:
        print(f"❌ Failed to send notification")
        print(f"   Status Code: {response.status_code}")
        print(f"   Response: {response.text}")
        print("═══════════════════════════════════════════════════════════")

def main():
    if len(sys.argv) < 2:
        print("❌ Usage: python test_fcm_notification.py <FCM_TOKEN> [CALLER_NAME]")
        print("\nGet the FCM token from your app's console output when it starts.")
        print("Look for the line: '✅ FCM TOKEN RETRIEVED'")
        sys.exit(1)

    if SERVER_KEY == "YOUR_FIREBASE_SERVER_KEY_HERE":
        print("❌ ERROR: You need to set your Firebase Server Key!")
        print("\n📋 To get your Server Key:")
        print("1. Go to Firebase Console: https://console.firebase.google.com/")
        print("2. Select your project: scancall-f8c81")
        print("3. Go to Project Settings > Cloud Messaging")
        print("4. Copy the 'Server key' (under Cloud Messaging API (Legacy))")
        print("5. Paste it in this script where it says 'YOUR_FIREBASE_SERVER_KEY_HERE'")
        print("\n⚠️  WARNING: Keep this key secret! Do not commit it to version control.")
        sys.exit(1)

    fcm_token = sys.argv[1]
    caller_name = sys.argv[2] if len(sys.argv) > 2 else "Test Caller"

    send_fcm_notification(fcm_token, caller_name)

if __name__ == "__main__":
    main()
