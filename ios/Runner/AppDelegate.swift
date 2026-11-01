import Flutter
import UIKit
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var savedBrightness: CGFloat? = nil

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let appleMusicChannel = FlutterMethodChannel(name: "com.audiopulse/apple_music",
                                                binaryMessenger: controller.binaryMessenger)
      
      appleMusicChannel.setMethodCallHandler({
        [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
        if call.method == "getLocalReleases" {
          self?.fetchLocalMusic(result: result)
        } else {
          result(FlutterMethodNotImplemented)
        }
      })

      let scraperChannel = FlutterMethodChannel(name: "com.audiopulse/media_scraper",
                                                binaryMessenger: controller.binaryMessenger)
      scraperChannel.setMethodCallHandler({
        [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
        if call.method == "setMaxBrightness" {
          DispatchQueue.main.async {
            if self?.savedBrightness == nil {
              self?.savedBrightness = UIScreen.main.brightness
            }
            UIScreen.main.brightness = 1.0
            result(true)
          }
        } else if call.method == "resetBrightness" {
          DispatchQueue.main.async {
            if let prev = self?.savedBrightness {
              UIScreen.main.brightness = prev
              self?.savedBrightness = nil
            }
            result(true)
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      })
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func fetchLocalMusic(result: @escaping FlutterResult) {
    if #available(iOS 9.3, *) {
      MPMediaLibrary.requestAuthorization { status in
        if status == .authorized {
          let query = MPMediaQuery.songs()
          var releases = Set<String>()
          
          if let items = query.items {
            for item in items {
              let title = item.title ?? ""
              let artist = item.albumArtist ?? item.artist ?? "Unknown Artist"
              let album = item.albumTitle ?? "Single"
              let duration = Int(item.playbackDuration)
              
              if !title.isEmpty && !artist.isEmpty && duration > 0 {
                releases.insert("\(title)|||\(artist)|||\(album)|||\(duration)")
              }
            }
          }
          result(Array(releases))
        } else {
          result(FlutterError(code: "PERMISSION_DENIED",
                            message: "Accès à Apple Music refusé",
                            details: nil))
        }
      }
    } else {
      result(FlutterError(code: "UNSUPPORTED_IOS_VERSION",
                        message: "iOS 9.3 ou supérieur requis",
                        details: nil))
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
