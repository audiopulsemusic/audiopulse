import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiopulse_flutter/main.dart';
import 'package:audiopulse_flutter/models/app_view.dart';
import 'package:audiopulse_flutter/providers/audio_provider.dart';
import 'package:audiopulse_flutter/views/onboarding_view.dart';

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
          return {'id': 'test_player_widget'};
        }
        if (methodCall.method == 'load') {
          return {'duration': 218000000};
        }
        return <String, dynamic>{};
      },
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'has_seen_onboarding': true,
    });
  });

  testWidgets('AudioPulseApp smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final provider = AudioProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AudioProvider>.value(
        value: provider,
        child: const AudioPulseApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AudioPulseApp), findsOneWidget);
    expect(find.text('Bibliothèque'), findsWidgets);
  });

  testWidgets(
    'UX-01: PopScope / handleBackNavigation ferme QueueDrawer, FullScreenPlayer puis revient à Home',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final provider = AudioProvider();
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<AudioProvider>.value(
          value: provider,
          child: const AudioPulseApp(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Sur l'accueil sans overlay : canPopRoot est true
      expect(provider.canPopRoot, isTrue);

      // 2. Navigation vers ArtistView -> Retour ramène vers SearchView
      provider.setActiveView(AppView.artist);
      await tester.pump();
      expect(provider.activeAppView, AppView.artist);
      expect(provider.canPopRoot, isFalse);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(provider.activeAppView, AppView.search);
      expect(provider.canPopRoot, isFalse);

      // 3. Ouverture du FullScreenPlayer et du QueueDrawer -> Retour ferme d'abord QueueDrawer puis FullScreenPlayer
      provider.setIsFullPlayerOpen(true);
      provider.setIsQueueOpen(true);
      await tester.pump();
      expect(provider.isQueueOpen, isTrue);
      expect(provider.isFullPlayerOpen, isTrue);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(provider.isQueueOpen, isFalse);
      expect(provider.isFullPlayerOpen, isTrue);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(provider.isFullPlayerOpen, isFalse);
      expect(provider.activeAppView, AppView.search);

      // 4. Retour depuis SearchView ramène sur HomeView
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(provider.activeAppView, AppView.home);
      expect(provider.canPopRoot, isTrue);
    },
  );

  testWidgets(
    'UX-03 & TECH-03: Mode paysage compact sans RenderFlex overflow + Politique de confidentialité',
    (WidgetTester tester) async {
      // Écran paysage très compact (ex: téléphone en paysage ou écran scindé Android 16)
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final provider = AudioProvider();
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<AudioProvider>.value(
          value: provider,
          child: const AudioPulseApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Vérifie QueueImportView en mode paysage compact (aucun overflow)
      provider.setActiveView(AppView.queueImport);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Vérifie SettingsView et la présence de la Politique de confidentialité (TECH-03)
      provider.setActiveView(AppView.settings);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Politique de confidentialité'), findsOneWidget);
      expect(find.text('Licences Open-Source'), findsOneWidget);

      // Vérifie OnboardingView en mode paysage compact (aucun overflow)
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingView(onComplete: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
