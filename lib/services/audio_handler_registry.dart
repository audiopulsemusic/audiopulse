import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_handler.dart';

AudioPulseHandler? audioHandler;

Future<void> initAudioService(AudioPlayer player) async {
  AudioService.asyncError.listen((Object error) {
    if (kDebugMode) {
      debugPrint('[AudioService] asyncError: $error');
    }
  });

  audioHandler = await AudioService.init(
    builder: () => AudioPulseHandler(player),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.audiopulse.channel.audio',
      androidNotificationChannelName: 'AudioPulse Hi-Fi Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidShowNotificationBadge: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
      preloadArtwork: true,
      androidBrowsableRootExtras: <String, dynamic>{
        AudioPulseHandler.contentStyleSupportedKey: true,
        AudioPulseHandler.contentStyleBrowsableHintKey:
            AudioPulseHandler.contentStyleListItem,
        AudioPulseHandler.contentStylePlayableHintKey:
            AudioPulseHandler.contentStyleListItem,
        AudioPulseHandler.searchSupportedKey: true,
      },
    ),
  );
}
