import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiopulse_flutter/models/track.dart';
import 'package:audiopulse_flutter/providers/audio_provider.dart';
import 'package:audiopulse_flutter/widgets/fullscreen_player.dart';

class TestAudioProvider extends AudioProvider {
  bool fakePlaying = false;
  Track? fakeTrack;
  Duration? lastSeekPosition;

  @override
  bool get isPlaying => fakePlaying;

  @override
  Track? get currentTrack => fakeTrack ?? super.currentTrack;

  @override
  Future<void> togglePlayPause() async {
    fakePlaying = !fakePlaying;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) async {
    lastSeekPosition = position;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'init') {
          return {'id': 'test_player_fullscreen'};
        }
        if (methodCall.method == 'load') {
          return {'duration': 218000000};
        }
        return <String, dynamic>{};
      },
    );
  });

  final testTrack = Track(
    id: 'test_fullscreen_track_1',
    title: 'Pulse Symphony',
    artist: 'AudioPulse Artist',
    album: 'Greatest Hits',
    coverUrl: '',
    duration: 200,
    bitrate: 160,
    source: 'music',
  );

  testWidgets('FullScreenPlayer album circle tap toggles play/pause and outer ring seeks',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final provider = TestAudioProvider();
    provider.fakeTrack = testTrack;
    provider.setIsFullPlayerOpen(true);

    await tester.pumpWidget(
      ChangeNotifierProvider<AudioProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: FullScreenPlayer(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    // Verify player is open and displays track
    expect(find.byType(FullScreenPlayer), findsOneWidget);

    final initialPlayState = provider.isPlaying;

    // Find the main artwork stack (center of album circle)
    final centerFinder = find.byType(ClipOval);
    expect(centerFinder, findsOneWidget);

    // Tap directly on the center of the album circle
    await tester.tap(centerFinder);
    await tester.pump(const Duration(milliseconds: 50));

    // Play/pause should have been toggled
    expect(provider.isPlaying, !initialPlayState);
    expect(provider.lastSeekPosition, isNull);

    // Tap again to toggle back
    await tester.tap(centerFinder);
    await tester.pump(const Duration(milliseconds: 50));
    expect(provider.isPlaying, initialPlayState);
    expect(provider.lastSeekPosition, isNull);

    // Now tap on the outer scrubber ring (top edge above center)
    final centerOffset = tester.getCenter(centerFinder);
    final artworkRadius = tester.getSize(centerFinder).width / 2;
    // Tap at top of outer ring (outside artworkRadius)
    final ringOffset = Offset(centerOffset.dx, centerOffset.dy - artworkRadius - 8);
    await tester.tapAt(ringOffset);
    await tester.pump(const Duration(milliseconds: 50));

    // Scrubber tap should have triggered seek
    expect(provider.lastSeekPosition, isNotNull);

    provider.dispose();
  });

  testWidgets('FullScreenPlayer pan drag on scrubber ring seeks on release without lagging',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final provider = TestAudioProvider();
    provider.fakeTrack = testTrack;
    provider.setIsFullPlayerOpen(true);

    await tester.pumpWidget(
      ChangeNotifierProvider<AudioProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: FullScreenPlayer(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final centerFinder = find.byType(ClipOval);
    final centerOffset = tester.getCenter(centerFinder);
    final artworkRadius = tester.getSize(centerFinder).width / 2;

    // Start gesture on outer ring (scrubber)
    final ringStart = Offset(centerOffset.dx, centerOffset.dy - artworkRadius - 8);
    final gesture = await tester.startGesture(ringStart);
    await tester.pump();

    // No seek on pan down
    expect(provider.lastSeekPosition, isNull);

    // Drag along the circular arc
    await gesture.moveTo(Offset(centerOffset.dx + artworkRadius + 8, centerOffset.dy));
    await tester.pump();

    // While dragging, no immediate audio.seek() to prevent playback stutter
    expect(provider.lastSeekPosition, isNull);

    // Release drag
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));

    // Seek is committed exactly once upon release
    expect(provider.lastSeekPosition, isNotNull);

    provider.dispose();
  });
}
