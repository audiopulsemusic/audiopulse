import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiopulse_flutter/models/track.dart';
import 'package:audiopulse_flutter/providers/audio_provider.dart';
import 'package:audiopulse_flutter/widgets/track_actions_modal.dart';
import 'package:audiopulse_flutter/widgets/track_tile.dart';

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
          return {'id': 'test_player_actions'};
        }
        if (methodCall.method == 'load') {
          return {'duration': 218000000};
        }
        return <String, dynamic>{};
      },
    );
  });

  final testTrack = Track(
    id: 'test_action_track_1',
    title: 'Pulse Symphony',
    artist: 'AudioPulse Artist',
    album: 'Greatest Hits',
    coverUrl: 'https://example.com/cover.jpg',
    duration: 215,
    bitrate: 160,
    source: 'music',
  );

  testWidgets('TrackTile long press displays contextual modal with required actions and excludes playlist/favorites',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final provider = AudioProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<AudioProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: TrackTile(
                track: testTrack,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify track tile is displayed
    expect(find.text('Pulse Symphony'), findsOneWidget);
    expect(find.text('AudioPulse Artist'), findsOneWidget);

    // Long press on TrackTile
    await tester.longPress(find.byType(TrackTile));
    await tester.pumpAndSettle();

    // Verify allowed actions are displayed
    expect(find.text('Lire juste après'), findsOneWidget);
    expect(find.text('Ajouter à la file d\'attente'), findsOneWidget);
    expect(find.text('Détails & Qualité audio'), findsOneWidget);
    expect(find.text('Voir l\'artiste'), findsOneWidget);
    expect(find.text('Voir l\'album'), findsOneWidget);

    // Verify explicitly excluded actions are NOT displayed
    expect(find.text('Ajouter à une playlist'), findsNothing);
    expect(find.text('Favoris'), findsNothing);
    expect(find.text('Ajouter aux favoris'), findsNothing);

    // Tap "Détails & Qualité audio" to open info dialog
    await tester.tap(find.text('Détails & Qualité audio'));
    await tester.pumpAndSettle();

    // Verify the technical info dialog appears
    expect(find.text('160 kbps (Mesuré)'), findsOneWidget);
    expect(find.text('YouTube Music (Officiel)'), findsOneWidget);

    // Close dialog
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();

    provider.dispose();
  });

  testWidgets('TrackTile secondary click (right click) displays context menu',
      (WidgetTester tester) async {
    final provider = AudioProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<AudioProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: TrackTile(
                track: testTrack,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Right click (secondary click)
    await tester.tap(find.byType(TrackTile), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    // Check menu options
    expect(find.text('Lire juste après'), findsOneWidget);
    expect(find.text('Ajouter à la file d\'attente'), findsOneWidget);

    final initialTrackId = provider.currentTrack?.id;

    // Tap "Lire juste après"
    await tester.tap(find.text('Lire juste après'));
    await tester.pumpAndSettle();

    // Verify it was added to queue but NOT played as current track
    expect(provider.queue.any((t) => t.id == testTrack.id), isTrue);
    expect(provider.currentTrack?.id, initialTrackId);

    provider.dispose();
  });

  testWidgets('Mobile Bottom Sheet displays badges and actions when shown without tapPosition',
      (WidgetTester tester) async {
    final provider = AudioProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<AudioProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => TrackActionsModal.show(context, testTrack),
                  child: const Text('Open Modal'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Modal'));
    await tester.pumpAndSettle();

    // Bottom sheet content
    expect(find.text('Pulse Symphony'), findsOneWidget);
    expect(find.text('M'), findsOneWidget); // Source badge YouTube Music
    expect(find.text('160 kbps'), findsOneWidget); // Bitrate badge
    expect(find.text('Insérer juste après la lecture en cours'), findsOneWidget);
    expect(find.text('Placer à la fin de la file de lecture'), findsOneWidget);
    expect(find.text('Ajouter à une playlist'), findsNothing);
    expect(find.text('Favoris'), findsNothing);

    provider.dispose();
  });

  testWidgets('TrackTile 3-dots button (left click) opens contextual menu and does not trigger playback',
      (WidgetTester tester) async {
    final provider = AudioProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<AudioProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: TrackTile(
                track: testTrack,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Find the 3-dots options icon button
    final optionsBtn = find.byTooltip('Options du morceau');
    expect(optionsBtn, findsOneWidget);

    // Left click on 3-dots button
    await tester.tap(optionsBtn);
    await tester.pumpAndSettle();

    // Check menu options are visible
    expect(find.text('Lire juste après'), findsOneWidget);
    expect(find.text('Ajouter à la file d\'attente'), findsOneWidget);

    final initialTrackId = provider.currentTrack?.id;

    // Tap "Lire juste après"
    await tester.tap(find.text('Lire juste après'));
    await tester.pumpAndSettle();

    // Verify track is queued but NOT playing as current track
    expect(provider.queue.any((t) => t.id == testTrack.id), isTrue);
    expect(provider.currentTrack?.id, initialTrackId);

    provider.dispose();
  });
}

