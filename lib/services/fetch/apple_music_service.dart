import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppleMusicService {
  static const MethodChannel _channel = MethodChannel('com.audiopulse/apple_music');

  /// Récupère la liste des MORCEAUX réels depuis la bibliothèque locale
  Future<List<String>> getLocalReleases() async {
    print("🍎 [AppleMusicService] Tentative d'extraction des Morceaux...");
    
    if (!kIsWeb && Platform.isIOS) {
      try {
        final List<dynamic>? result = await _channel.invokeMethod('getLocalReleases');
        if (result != null) {
          final releases = result.cast<String>().where((e) => e.isNotEmpty && e.contains('|||')).toList();
          print("🍎 [AppleMusicService] Succès Mobile : ${releases.length} morceaux trouvés !");
          return releases;
        }
      } on PlatformException catch (e) {
        print("🍎 [AppleMusicService] Erreur Mobile : ${e.message}");
      } catch (e) {
        print("🍎 [AppleMusicService] Exception Mobile : $e");
      }
      return [];
    }
    
    if (Platform.isMacOS) {
      try {
        // Script JavaScript for Automation (JXA) ultra-rapide.
        final script = '''
          const music = Application("Music");
          const names = music.tracks.name();
          const albums = music.tracks.album();
          const albumArtists = music.tracks.albumArtist();
          const trackArtists = music.tracks.artist();
          const durations = music.tracks.duration();
          const unique = new Set();
          
          for (let i = 0; i < names.length; i++) {
              const name = names[i];
              if (!name) continue;
              
              let art = albumArtists[i];
              if (!art || art === "") art = trackArtists[i];
              
              let alb = albums[i] || "Single";
              let dur = durations[i] || 0;
              
              if (name && art && dur > 0) {
                  unique.add(name + "|||" + art + "|||" + alb + "|||" + Math.round(dur));
              }
          }
          Array.from(unique).join("\\n");
        ''';

        final processResult = await Process.run('osascript', ['-l', 'JavaScript', '-e', script]);

        if (processResult.exitCode == 0) {
          final String output = processResult.stdout.toString();
          
          final uniqueReleases = output
              .split('\n')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty && e.contains('|||'))
              .toList();
              
          print("🍎 [AppleMusicService] Succès macOS : ${uniqueReleases.length} morceaux trouvés !");
          return uniqueReleases;
        } else {
          print("🍎 [AppleMusicService] Erreur JXA : ${processResult.stderr}");
        }
      } catch (e) {
        print("🍎 [AppleMusicService] Exception JXA : $e");
      }
    }

    return [];
  }
}

