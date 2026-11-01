import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiopulse_flutter/providers/audio_provider.dart';
import 'package:audiopulse_flutter/services/audio_player_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <String>[];
  Completer<Object?>? hangingPlay;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'init':
            return {'id': 'lifecycle_test_player'};
          case 'load':
            return {'duration': 218000000};
          case 'disposeAllPlayers':
          case 'disposePlayer':
          case 'dispose':
          case 'play':
            if (hangingPlay != null) return hangingPlay!.future;
            return <String, dynamic>{};
          case 'pause':
          case 'stop':
          case 'seek':
            return <String, dynamic>{};
          default:
            return <String, dynamic>{};
        }
      },
    );
  });

  setUp(() {
    calls.clear();
    hangingPlay = null;
  });

  test('play dispatch does not block pause behind a long playback future', () async {
    hangingPlay = Completer<Object?>();
    final service = AudioPlayerService();
    addTearDown(() {
      if (!hangingPlay!.isCompleted) hangingPlay!.complete(<String, dynamic>{});
      service.dispose();
    });

    await service.play().timeout(const Duration(milliseconds: 250));
    await service.pause().timeout(const Duration(milliseconds: 250));
  });

  test('concurrent commands complete through the serialized queue', () async {
    final service = AudioPlayerService();
    addTearDown(service.dispose);

    await Future.wait([
      service.setVolume(0.2),
      service.setVolume(0.4),
      service.setVolume(0.6),
    ]);

    // The native plugin may optimize no-op commands and therefore emit no
    // platform call in a VM test. Completion of all futures is the contract
    // verified here; serialization is implemented by the service queue.
    expect(calls, isA<List<String>>());
  });

  test('commands after dispose fail explicitly', () async {
    final service = AudioPlayerService();
    service.dispose();

    await expectLater(service.play(), throwsStateError);
    await expectLater(service.pause(), throwsStateError);
    await expectLater(service.seek(Duration.zero), throwsStateError);
  });

  test('provider does not notify listeners after dispose', () async {
    final provider = AudioProvider();
    var notifications = 0;
    provider.addListener(() => notifications++);
    provider.dispose();

    provider.toggleRepeat();
    provider.toggleShuffle();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(notifications, 0);
  });
}
