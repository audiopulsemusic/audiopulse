import Cocoa
import FlutterMacOS
import iTunesLibrary

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Configuration du MethodChannel pour communiquer avec Flutter
    let channel = FlutterMethodChannel(name: "com.audiopulse/apple_music", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "getArtists" {
            self.fetchAppleMusicArtists(result: result)
        } else {
            result(FlutterMethodNotImplemented)
        }
    }

    super.awakeFromNib()
  }

  // Fonction native pour lire la bibliothèque Apple Music / iTunes
  func fetchAppleMusicArtists(result: @escaping FlutterResult) {
      do {
          let library = try ITLibrary(apiVersion: "1.0")
          let items = library.allMediaItems
          
          var artistSet = Set<String>()
          
          for item in items {
              if item.mediaKind == .kindSong, let artistName = item.artist?.name, !artistName.isEmpty {
                  artistSet.insert(artistName)
              }
          }
          
          // Renvoie la liste des artistes uniques à Flutter
          result(Array(artistSet))
      } catch {
          result(FlutterError(code: "LIBRARY_ERROR", message: error.localizedDescription, details: nil))
      }
  }
}
