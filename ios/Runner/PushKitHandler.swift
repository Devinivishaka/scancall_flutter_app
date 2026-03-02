import Foundation
import PushKit
import Flutter
import CallKit

class PushKitHandler: NSObject, PKPushRegistryDelegate {

    static let instance = PushKitHandler()

    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    var lastVoipToken: String?

    func setupEventChannel(_ messenger: FlutterBinaryMessenger) {
        eventChannel = FlutterEventChannel(name: "pushkit_events", binaryMessenger: messenger)
        eventChannel?.setStreamHandler(self)
    }

    func registerVoIP() {
        let registry = PKPushRegistry(queue: DispatchQueue.main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
    }

    // -----------------------
    //  VoIP TOKEN
    // -----------------------
    func pushRegistry(_ registry: PKPushRegistry,
                      didUpdate pushCredentials: PKPushCredentials,
                      for type: PKPushType) {

        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        print("🍎 VoIP Token: \(token)")

        lastVoipToken = token

        eventSink?([
            "event": "voipToken",
            "token": token
        ])
    }

    // -----------------------
    //  INCOMING VoIP PUSH
    // -----------------------
    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType,
                      completion: @escaping () -> Void) {

        print("📞 Incoming VoIP Push:", payload.dictionaryPayload)

        // Convert payload into usable dictionary
        let data = payload.dictionaryPayload

        // Show CallKit UI IMMEDIATELY (required for TestFlight / production)
        CallProvider.shared.reportIncomingCall(
            uuid: UUID(),
            handle: data["callerName"] as? String ?? "Unknown",
            hasVideo: (data["isVideo"] as? String) == "1"
        )

        // ALWAYS call completion
        defer { completion() }

        // Clean the payload for Flutter (AnyHashable → String)
        var cleanPayload: [String: Any] = [:]
        for (key, value) in data {
            cleanPayload[String(describing: key)] = value
        }

        // Send event to Flutter
        eventSink?([
            "event": "incoming_voip",
            "payload": cleanPayload
        ])
    }
}

// MARK: - Event Channel
extension PushKitHandler: FlutterStreamHandler {

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events

        if let token = lastVoipToken {
            events([
                "event": "voipToken",
                "token": token
            ])
        }

        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
