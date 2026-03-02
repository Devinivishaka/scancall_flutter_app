import UIKit
import Flutter
import PushKit

@main
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
  ) -> Bool {

    GeneratedPluginRegistrant.register(with: self)

    // Register for VoIP push
    PushKitHandler.instance.registerVoIP()

    // Setup EventChannel
    let controller = window?.rootViewController as! FlutterViewController
    PushKitHandler.instance.setupEventChannel(controller.binaryMessenger)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
