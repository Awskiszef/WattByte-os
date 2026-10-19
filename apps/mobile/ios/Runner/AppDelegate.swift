import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Background refresh (BGAppRefreshTask) runs the same Dart pipeline as the
    // foreground app. The identifier must match kRefreshTask in Dart and the
    // BGTaskSchedulerPermittedIdentifiers entry in Info.plist.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // iOS decides when it really runs; 15 minutes is only the earliest begin date, never a promise.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "pl.wattbyte.refresh", earliestBeginInSeconds: NSNumber(value: 15 * 60))

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // UIScene life cycle (required since iOS 27): plugins are registered on the implicit engine.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
