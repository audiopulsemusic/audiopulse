import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/audio_provider.dart';
import 'theme/app_theme.dart';
import 'widgets/bottom_nav.dart';
import 'widgets/fullscreen_player.dart';
import 'widgets/queue_drawer.dart';
import 'views/home_view.dart';
import 'views/search_view.dart';
import 'views/artist_view.dart';
import 'views/settings_view.dart';
import 'views/queue_import_view.dart';
import 'views/share_view.dart';
import 'views/onboarding_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/apple_music_import_wizard.dart';
import 'models/app_view.dart';
import 'services/security/security_check_service.dart';
import 'services/audio_handler_registry.dart';
import 'services/audio_player_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Conformité RGPD / Play Store (TECH-03) : interdit tout téléchargement
  // dynamique de polices vers fonts.gstatic.com au runtime.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Diagnostics d'intégrité non bloquants
  SecurityCheckService.runStartupDiagnostics();

  // Optimisation du cache mémoire d'images Flutter pour éviter les pics de RAM sur mobile
  PaintingBinding.instance.imageCache.maximumSizeBytes = 60 * 1024 * 1024; // 60 Mo max
  PaintingBinding.instance.imageCache.maximumSize = 100; // 100 images max

  // Orientation adaptative (compatible grands écrans / pliables Android 16)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // JustAudioBackground / AudioService is only supported on Android and iOS.
  // On macOS/Desktop it corrupts the AudioPlayer state even when the exception is caught.
  final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  final playerService = AudioPlayerService();

  if (isMobile) {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (e) {
      debugPrint('AudioSession init failed: $e');
    }

    try {
      await initAudioService(playerService.player);
    } catch (e) {
      debugPrint('AudioService init failed: $e');
    }
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => AudioProvider(playerService),
      child: const AudioPulseApp(),
    ),
  );
}

class AudioPulseApp extends StatelessWidget {
  const AudioPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Pulse',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainLayout(),
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> with WidgetsBindingObserver {
  bool _showOnboarding = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool('has_seen_onboarding') ?? false;
    if (mounted) {
      setState(() {
        _showOnboarding = !hasSeen;
        _isLoading = false;
      });
      if (hasSeen) {
        _requestNotificationPermissionPostFrame();
      }
    }
  }

  /// Demande la permission `POST_NOTIFICATIONS` (Android 13+) uniquement après
  /// l'attachement de l'arbre UI et l'onboarding pour ne jamais figer le splash screen.
  void _requestNotificationPermissionPostFrame() {
    if (kIsWeb || !Platform.isAndroid) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await Permission.notification.request();
      } catch (e) {
        debugPrint('Notification permission request failed: $e');
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      // Nettoyage ou synchronisation de sécurité lors de la mise en arrière-plan
    }
  }

  int _viewToIndex(AppView view) {
    switch (view) {
      case AppView.search:
        return 1;
      case AppView.artist:
        return 2;
      case AppView.settings:
        return 3;
      case AppView.queueImport:
        return 4;
      case AppView.share:
        return 5;
      case AppView.offline:
      case AppView.home:
      case AppView.album:
      case AppView.playlist:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.white)));
    }
    
    if (_showOnboarding) {
      return OnboardingView(
        onComplete: (bool triggerImport) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('has_seen_onboarding', true);
          if (!mounted) return;
          setState(() => _showOnboarding = false);
          _requestNotificationPermissionPostFrame();

          if (triggerImport) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                AppleMusicImportWizard.show(context);
              }
            });
          }
        },
      );
    }

    final activeView = context.select<AudioProvider, AppView>((a) => a.activeAppView);
    final canPopRoot = context.select<AudioProvider, bool>((a) => a.canPopRoot);
    final activeIndex = _viewToIndex(activeView);

    return PopScope(
      canPop: canPopRoot,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        context.read<AudioProvider>().handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              width: double.infinity,
              height: double.infinity,
              constraints: const BoxConstraints(maxWidth: 640),
              color: Colors.black,
              child: Stack(
                children: [
                  // Main Scrollable Area with IndexedStack (Preserves Scroll & Prevents Rebuilds)
                  Positioned.fill(
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: IndexedStack(
                          index: activeIndex,
                          children: const [
                            HomeView(),
                            SearchView(),
                            ArtistView(),
                            SettingsView(),
                            QueueImportView(),
                            ShareView(),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Unified Floating Glass Dock (MiniPlayer + Bottom Navigation Bar)
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: BottomNavBar(),
                  ),

                  // Modal & Drawer Overlays
                  const FullScreenPlayer(),
                  const QueueDrawer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
