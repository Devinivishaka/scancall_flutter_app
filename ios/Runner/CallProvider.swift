import Foundation
import CallKit

class CallProvider: NSObject, CXProviderDelegate {

    static let shared = CallProvider()

    private let provider: CXProvider

    override init() {
        let config = CXProviderConfiguration(localizedName: "ScanCall")
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [CXHandle.HandleType.generic]

        provider = CXProvider(configuration: config)

        super.init()
        provider.setDelegate(self, queue: nil)
    }

    func reportIncomingCall(uuid: UUID, handle: String, hasVideo: Bool) {
        let update = CXCallUpdate()
        update.localizedCallerName = handle
        update.hasVideo = hasVideo

        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let err = error {
                print("❌ Error reporting call: \(err)")
            } else {
                print("📞 CallKit incoming call shown")
            }
        }
    }

    func providerDidReset(_ provider: CXProvider) { }
}
