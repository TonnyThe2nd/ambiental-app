import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  override func configureFlutterEngine(_ flutterEngine: FlutterEngine) {
    GeneratedPluginRegistrant.register(with: flutterEngine)
    let channel = FlutterMethodChannel(
      name: "urbaneye/system_notifications",
      binaryMessenger: flutterEngine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "show", let values = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      let content = UNMutableNotificationContent()
      content.title = values["title"] as? String ?? "Novo alerta ambiental"
      content.body = values["body"] as? String ?? "Há uma ocorrência próxima de você."
      content.sound = .default
      let identifier = String(values["id"] as? Int ?? Int(Date().timeIntervalSince1970))
      UNUserNotificationCenter.current().add(
        UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
      ) { error in
        if let error {
          result(FlutterError(code: "notification_error", message: error.localizedDescription, details: nil))
        } else {
          result(nil)
        }
      }
    }
  }
}
