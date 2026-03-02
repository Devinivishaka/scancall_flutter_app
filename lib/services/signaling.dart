import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class SignalingService {
  WebSocketChannel? ws;

  Function(dynamic)? onSignal;

  String myId = "flutter";
  String remoteId = "web";

  Future<void> connect(void Function(dynamic) onMessage) async {
    onSignal = onMessage;

    // Production server
    ws = WebSocketChannel.connect(
      Uri.parse(
        "wss://scan-call-backend-app-hnfdddcfgbh0bfb7.canadacentral-01.azurewebsites.net",
      ),
    );

    // Local development (uncomment if needed)
    // ws = WebSocketChannel.connect(Uri.parse("ws://192.168.1.139:8080"));

    ws!.sink.add(jsonEncode({"type": "register", "from": myId}));

    ws!.stream.listen((event) {
      final msg = jsonDecode(event);
      onSignal?.call(msg);
    });
  }

  void send(String type, Map data) {
    ws?.sink.add(
      jsonEncode({"type": type, "from": myId, "to": remoteId, ...data}),
    );
  }

  void dispose() {
    ws?.sink.close();
    ws = null;
  }
}
