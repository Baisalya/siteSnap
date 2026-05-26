import UIKit
import Flutter
import CoreMotion

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private let localEnvironmentChannel = "surveycam/local_environment"
  private let altimeter = CMAltimeter()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    SwiftFlutterForegroundTaskPlugin.setPluginRegistrantCallback(registerPlugins)
    configureLocalEnvironmentChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func configureLocalEnvironmentChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let channel = FlutterMethodChannel(
      name: localEnvironmentChannel,
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "getSensorAvailability" {
        result(self?.getSensorAvailability() ?? [String: Bool]())
        return
      }

      guard call.method == "readEnvironment" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard let self = self else {
        result([String: Double]())
        return
      }

      self.readEnvironmentSensors(result)
    }
  }

  private func getSensorAvailability() -> [String: Bool] {
    return [
      "temperature": false,
      "humidity": false,
      "pressure": CMAltimeter.isRelativeAltitudeAvailable(),
      "airQuality": false,
    ]
  }

  private func readEnvironmentSensors(_ result: @escaping FlutterResult) {
    var readings: [String: Double] = [:]

    guard CMAltimeter.isRelativeAltitudeAvailable() else {
      result(readings)
      return
    }

    var finished = false

    func finish() {
      guard !finished else { return }
      finished = true
      altimeter.stopRelativeAltitudeUpdates()
      result(readings)
    }

    altimeter.startRelativeAltitudeUpdates(to: OperationQueue.main) { data, _ in
      if let pressure = data?.pressure {
        readings["pressureHpa"] = pressure.doubleValue * 10.0
      }
      finish()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
      finish()
    }
  }
}

func registerPlugins(registry: FlutterPluginRegistry) {
  GeneratedPluginRegistrant.register(with: registry)
}
