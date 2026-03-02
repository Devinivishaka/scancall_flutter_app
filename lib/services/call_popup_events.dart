import 'dart:async';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

class CallPopupEvents {
  static StreamSubscription? _sub;

  static void listen(
      Function(String action, Map<String, dynamic> data) handler,
      ) {
    _sub = FlutterCallkitIncoming.onEvent.listen((dynamic event) {
      print('📞 CallPopupEvents received: $event');

      try {
        if (event == null) return;

        String action = 'UNKNOWN';
        Map<String, dynamic> body = {};

        // The event from FlutterCallkitIncoming.onEvent is typically a Map
        if (event is Map) {
          // Extract event name from common property names
          action = event['name']?.toString() ??
              event['event']?.toString() ??
              event['type']?.toString() ??
              'UNKNOWN';

          // Create body from the event map
          body = Map<String, dynamic>.from(event);

          // Remove action-related fields to keep body clean
          body.remove('name');
          body.remove('event');
          body.remove('type');

        } else {
          // If not a Map, convert to string and try to parse
          final eventStr = event.toString();

          // Try to identify common call actions
          if (eventStr.contains('ACTION_CALL_ACCEPT')) {
            action = 'ACTION_CALL_ACCEPT';
          } else if (eventStr.contains('ACTION_CALL_DECLINE')) {
            action = 'ACTION_CALL_DECLINE';
          } else if (eventStr.contains('ACTION_CALL_ENDED')) {
            action = 'ACTION_CALL_ENDED';
          } else {
            action = eventStr;
          }

          body = {'raw_event': eventStr};
        }

        print('📞 Parsed - Action: $action, Body: $body');

        // Handle specific actions
        if (action == 'ACTION_CALL_ACCEPT' ||
            action == 'ACTION_CALL_DECLINE' ||
            action == 'ACTION_CALL_ENDED') {
          handler(action, body);
        }

      } catch (e) {
        print('❌ Error in CallPopupEvents: $e');
      }
    });
  }

  static void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
