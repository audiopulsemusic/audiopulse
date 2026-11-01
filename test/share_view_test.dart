import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:audiopulse_flutter/models/app_view.dart';
import 'package:audiopulse_flutter/providers/audio_provider.dart';
import 'package:audiopulse_flutter/services/audio_player_service.dart';
import 'package:audiopulse_flutter/views/share_view.dart';

void main() {
  testWidgets('ShareView renders banner, platform switcher, and QR code', (tester) async {
    final playerService = AudioPlayerService();
    final audioProvider = AudioProvider(playerService);
    audioProvider.setActiveView(AppView.share);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AudioProvider>.value(
          value: audioProvider,
          child: const ShareView(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Check header
    expect(find.text('Partager Audio Pulse'), findsOneWidget);
    expect(find.text('PARTAGE INSTANTANÉ'), findsOneWidget);
    // Brightness badge is disabled on macOS desktop
    expect(find.text('LUMINOSITÉ MAX'), findsNothing);

    // Check platform buttons
    expect(find.text('iOS (iPhone)'), findsOneWidget);
    expect(find.text('Android'), findsOneWidget);

    // Initial state is iOS
    expect(find.text('Téléchargement pour iOS'), findsOneWidget);

    // Tap Android button
    await tester.tap(find.text('Android'));
    await tester.pumpAndSettle();

    expect(find.text('Téléchargement pour Android'), findsOneWidget);

    // Check actions
    expect(find.text('Copier le lien'), findsOneWidget);
    expect(find.text('Modifier'), findsOneWidget);
  });
}
