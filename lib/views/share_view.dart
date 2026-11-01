import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_view.dart';
import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';

enum SharePlatform { ios, android }

class ShareView extends StatefulWidget {
  const ShareView({super.key});

  @override
  State<ShareView> createState() => _ShareViewState();
}

class _ShareViewState extends State<ShareView> {
  static const MethodChannel _brightnessChannel = MethodChannel('com.audiopulse/media_scraper');

  SharePlatform _selectedPlatform = SharePlatform.ios;

  // Liens officiels de téléchargement direct GitHub Releases
  String _iosUrl = 'https://github.com/audiopulsemusic/audiopulse/releases/latest/download/AudioPulse.ipa';
  String _androidUrl = 'https://github.com/audiopulsemusic/audiopulse/releases/latest/download/app-arm64-v8a-release.apk';

  bool _wasActive = false;

  bool get _isMobilePlatform => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _loadCustomUrls();
  }

  Future<void> _loadCustomUrls() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIos = prefs.getString('share_url_ios');
      final savedAndroid = prefs.getString('share_url_android');
      if (mounted) {
        setState(() {
          if (savedIos != null && savedIos.isNotEmpty) _iosUrl = savedIos;
          if (savedAndroid != null && savedAndroid.isNotEmpty) _androidUrl = savedAndroid;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveCustomUrl(SharePlatform platform, String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (platform == SharePlatform.ios) {
        await prefs.setString('share_url_ios', url);
        setState(() => _iosUrl = url);
      } else {
        await prefs.setString('share_url_android', url);
        setState(() => _androidUrl = url);
      }
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isActive = context.watch<AudioProvider>().activeAppView == AppView.share;
    if (isActive != _wasActive) {
      _wasActive = isActive;
      if (isActive) {
        _boostBrightness();
      } else {
        _restoreBrightness();
      }
    }
  }

  Future<void> _boostBrightness() async {
    // Désactivé sur macOS / Desktop / Web (uniquement iOS & Android)
    if (!_isMobilePlatform) return;
    try {
      await _brightnessChannel.invokeMethod('setMaxBrightness');
    } catch (_) {}
  }

  Future<void> _restoreBrightness() async {
    // Désactivé sur macOS / Desktop / Web (uniquement iOS & Android)
    if (!_isMobilePlatform) return;
    try {
      await _brightnessChannel.invokeMethod('resetBrightness');
    } catch (_) {}
  }

  @override
  void dispose() {
    _restoreBrightness();
    super.dispose();
  }

  String get _currentUrl => _selectedPlatform == SharePlatform.ios ? _iosUrl : _androidUrl;

  Future<void> _copyCurrentUrl() async {
    await Clipboard.setData(ClipboardData(text: _currentUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Lien ${_selectedPlatform == SharePlatform.ios ? "iOS" : "Android"} copié dans le presse-papier !'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showEditUrlDialog() async {
    final controller = TextEditingController(text: _currentUrl);
    final platformName = _selectedPlatform == SharePlatform.ios ? 'iOS' : 'Android';

    final newUrl = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        backgroundColor: const Color(0xFF141721),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0x33FFFFFF)),
        ),
        title: Text(
          'Modifier le lien $platformName',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Entrez l\'URL de téléchargement ou d\'installation (ex: GitHub Releases, IzzyOnDroid, F-Droid, AltStore) :',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0A0D14),
                hintText: 'https://...',
                hintStyle: const TextStyle(color: Colors.white30),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x33FFFFFF)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x33FFFFFF)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primaryPink),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryPink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (newUrl != null && newUrl.isNotEmpty) {
      await _saveCustomUrl(_selectedPlatform, newUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = _selectedPlatform == SharePlatform.ios;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 110),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner Section (Identique aux autres vues de l'app)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 14, bottom: 20),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0x33A855F7),
                    Color(0x1FEC4899),
                    Color(0x150A0D14),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0x33A855F7)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x11A855F7),
                    blurRadius: 20,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0x33A855F7),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0x4DA855F7)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.qr_code, size: 11, color: Color(0xFFC084FC)),
                            SizedBox(width: 5),
                            Text(
                              'PARTAGE INSTANTANÉ',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFC084FC),
                                letterSpacing: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isMobilePlatform)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0x22FBBF24),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0x4DFBBF24)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.sun, size: 11, color: Color(0xFFFBBF24)),
                              SizedBox(width: 4),
                              Text(
                                'LUMINOSITÉ MAX',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFBBF24),
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Partager Audio Pulse',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Faites scanner ce QR code pour installer l\'application instantanément sur iPhone ou Android.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),

            // Sélecteur de plateforme (iOS / Android)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF141721),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x1FFFFFFF)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedPlatform = SharePlatform.ios),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isIos ? AppTheme.primaryPink : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: isIos
                              ? [
                                  BoxShadow(
                                    color: AppTheme.primaryPink.withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.apple,
                              size: 16,
                              color: isIos ? Colors.white : Colors.white60,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'iOS (iPhone)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isIos ? Colors.white : Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedPlatform = SharePlatform.android),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !isIos ? AppTheme.primaryPink : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: !isIos
                              ? [
                                  BoxShadow(
                                    color: AppTheme.primaryPink.withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.smartphone,
                              size: 16,
                              color: !isIos ? Colors.white : Colors.white60,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Android',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: !isIos ? Colors.white : Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Carte principale du QR Code
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF141721),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0x1FFFFFFF)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Badge Plateforme
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isIos ? LucideIcons.apple : LucideIcons.smartphone,
                        size: 18,
                        color: AppTheme.primaryPink,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isIos ? 'Téléchargement pour iOS' : 'Téléchargement pour Android',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // QR Code Box (Fond blanc pur pour un contraste optimal au scan)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.15),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: _currentUrl,
                      version: QrVersions.auto,
                      size: 210,
                      backgroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Conteneur d'affichage du lien
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0D14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x22FFFFFF)),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.link, size: 14, color: AppTheme.textMuted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _currentUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Actions : Copier et Modifier
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _copyCurrentUrl,
                          icon: const Icon(LucideIcons.copy, size: 14),
                          label: const Text('Copier le lien', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0x33FFFFFF)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _showEditUrlDialog,
                        icon: const Icon(LucideIcons.pencil, size: 14),
                        label: const Text('Modifier', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryPink,
                          side: const BorderSide(color: Color(0x4DEC4899)),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Guide rapide d'utilisation
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0x0FFFFFFF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x14FFFFFF)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.info, size: 15, color: AppTheme.primaryPink),
                      SizedBox(width: 8),
                      Text(
                        'Comment scanner ?',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    '1. Ouvrez l\'appareil photo de votre smartphone.\n'
                    '2. Pointez l\'objectif vers le QR code ci-dessus.\n'
                    '3. Touchez la bannière jaune qui apparaît pour lancer le téléchargement.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
