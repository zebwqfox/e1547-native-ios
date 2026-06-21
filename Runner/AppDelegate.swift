import UIKit
import SwiftUI

@UIApplicationMain
@objc class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let window = UIWindow(frame: UIScreen.main.bounds)
    window.rootViewController = UIHostingController(rootView: NativeRootView())
    window.makeKeyAndVisible()
    self.window = window
    return true
  }
}
