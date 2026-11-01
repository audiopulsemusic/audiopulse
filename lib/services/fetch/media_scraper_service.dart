import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

class MediaScraperService {
  static const MethodChannel _channel = MethodChannel('com.audiopulse/media_scraper');

  /// Lance le scan des lecteurs multimédias actifs.
  /// Retourne une liste de chaînes au format : "Titre|||Artiste|||Album|||Durée"
  static Stream<String> scanActivePlayersStream() async* {
    debugPrint("📡 [MediaScraper] Début du scan temps réel...");
    
    if (kIsWeb) {
      debugPrint("📡 [MediaScraper] Non supporté sur le web.");
      return;
    }

    if (Platform.isMacOS) {
      yield* _scanMacOSStream();
    } else if (Platform.isAndroid) {
      yield* _scanAndroidStream();
    }
  }

  static Stream<String> _scanMacOSStream() async* {
    debugPrint("📡 [MediaScraper] Exécution du script JXA sur macOS en stream...");
    final script = '''
      function run() {
        let results = new Set();
        
        function scrape(app, appName) {
            console.log("LOG::Début de l'aspiration sur " + appName);
            while (true) {
                try {
                    const track = app.currentTrack();
                    if (!track) {
                        console.log("LOG::Pas de musique en cours.");
                        break;
                    }
                    
                    const tName = track.name() || "Inconnu";
                    const tArt = track.artist() || "Inconnu";
                    const tAlb = track.album() || "Single";
                    
                    let dur = track.duration() || 0;
                    if (appName === "Spotify") {
                        dur = Math.round(dur / 1000);
                    } else {
                        dur = Math.round(dur);
                    }
                    
                    const trackStr = tName + "|||" + tArt + "|||" + tAlb + "|||" + dur;
                    if (results.has(trackStr)) {
                        console.log("LOG::Fin de la file d'attente détectée.");
                        break;
                    }
                    results.add(trackStr);
                    console.log("TRACK::" + trackStr);
                    
                    app.nextTrack();
                    
                    let waited = 0;
                    let changed = false;
                    while (waited < 20) {
                        delay(0.1);
                        try {
                            const nextTrack = app.currentTrack();
                            if (nextTrack && (nextTrack.name() !== tName || nextTrack.artist() !== tArt)) {
                                changed = true;
                                break;
                            }
                        } catch(e) { break; }
                        waited++;
                    }
                    if (!changed) {
                        console.log("LOG::Fin de la file d'attente atteinte.");
                        break;
                    }
                } catch(e) {
                    console.log("LOG::Erreur : " + e);
                    break;
                }
            }
            console.log("LOG::Fin de l'aspiration sur " + appName);
        }
        
        // Check Apple Music
        try {
          const music = Application("Music");
          if (music.running()) {
            scrape(music, "Music");
          }
        } catch(e) {}
        
        // Check Spotify
        try {
          const spotify = Application("Spotify");
          if (spotify.running()) {
            scrape(spotify, "Spotify");
          }
        } catch(e) {}
      }
    ''';

    try {
      final process = await Process.start('osascript', ['-l', 'JavaScript', '-e', script]);
      
      await for (final chunk in process.stderr.transform(utf8.decoder)) {
        final logs = chunk.split('\n');
        for (var log in logs) {
          final trimmed = log.trim();
          if (trimmed.startsWith('TRACK::')) {
            final trackInfo = trimmed.replaceFirst('TRACK::', '').trim();
            debugPrint("📡 [MediaScraper] Yielding: $trackInfo");
            yield trackInfo;
          } else if (trimmed.startsWith('LOG::')) {
            debugPrint("🤖 [JXA Log] ${trimmed.replaceFirst('LOG::', '').trim()}");
          }
        }
      }
    } catch (e) {
      debugPrint("📡 [MediaScraper] Exception macOS : $e");
    }
  }

  static const EventChannel _eventChannel = EventChannel('com.audiopulse/media_scraper_events');

  static Stream<String> _scanAndroidStream() async* {
    debugPrint("📡 [MediaScraper] Appel du scan Android (Kotlin)...");
    try {
      // On déclenche le scan en arrière-plan via MethodChannel
      await _channel.invokeMethod('scanActivePlayers');
      
      // Et on écoute les résultats via EventChannel
      await for (final event in _eventChannel.receiveBroadcastStream()) {
        final log = event.toString();
        if (log.startsWith('TRACK::')) {
          final trackInfo = log.replaceFirst('TRACK::', '').trim();
          debugPrint("📡 [MediaScraper] Yielding: $trackInfo");
          yield trackInfo;
        } else if (log.startsWith('LOG::')) {
          debugPrint("🤖 [Kotlin Log] ${log.replaceFirst('LOG::', '').trim()}");
        }
      }
    } on PlatformException catch (e) {
      if (e.code == "PERMISSION_DENIED") {
        debugPrint("📡 [MediaScraper] Permission refusée, redirection vers les paramètres...");
        await _channel.invokeMethod('requestPermission');
      } else {
        debugPrint("📡 [MediaScraper] Erreur Android : $e");
      }
    } catch (e) {
      debugPrint("📡 [MediaScraper] Exception Android : $e");
    }
  }

  /// Ouvre la fiche de l'application dans les paramètres Android (pour débloquer les paramètres restreints)
  static Future<void> openAppSettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openAppSettings');
    } catch (e) {
      debugPrint("📡 [MediaScraper] Erreur openAppSettings : $e");
    }
  }

  /// Ouvre l'écran d'accès aux notifications Android
  static Future<void> openNotificationListenerSettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestPermission');
    } catch (e) {
      debugPrint("📡 [MediaScraper] Erreur openNotificationListenerSettings : $e");
    }
  }

  /// Vérifie si l'accès aux notifications est activé
  static Future<bool> isPermissionGranted() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final bool? granted = await _channel.invokeMethod<bool>('checkPermission');
      return granted ?? false;
    } catch (e) {
      debugPrint("📡 [MediaScraper] Erreur checkPermission : $e");
      return false;
    }
  }
}
