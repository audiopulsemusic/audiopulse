import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../theme/app_theme.dart';
import '../services/fetch/media_scraper_service.dart';
import '../models/track.dart';
import '../widgets/track_tile.dart';
import '../widgets/apple_music_import_wizard.dart';
import '../services/library_sync_service.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';

class QueueImportView extends StatefulWidget {
  const QueueImportView({super.key});

  @override
  State<QueueImportView> createState() => _QueueImportViewState();
}

class _QueueImportViewState extends State<QueueImportView> {
  bool _isScanning = false;

  final List<String> _results = [];

  Future<void> _openRestrictedSettings() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Cliquez sur les 3 points (⋮) en haut à droite puis « Autoriser les paramètres restreints ».",
        ),
        duration: Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await MediaScraperService.openAppSettings();
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _results.clear();
    });

    final List<String> newTracks = [];

    try {
      await for (final trackStr
          in MediaScraperService.scanActivePlayersStream()) {
        if (!mounted) break;

        setState(() {
          _results.add(trackStr);
        });
        newTracks.add(trackStr);

        // Optionnel: On peut envoyer les morceaux par batch au fur et à mesure
        // Mais pour plus de sécurité on les envoie tous à la fin, ou petit à petit.
        if (newTracks.length >= 10) {
          await LibrarySyncService.instance.syncReleases(
            List.from(newTracks),
            onProgress: (_, _, _) {},
          );
          if (mounted) {
            context.read<AudioProvider>().libraryController.refresh();
          }
          newTracks.clear();
        }
      }

      // On sauvegarde les derniers restants
      if (newTracks.isNotEmpty) {
        await LibrarySyncService.instance.syncReleases(
          newTracks,
          onProgress: (_, _, _) {},
        );
        if (mounted) {
          context.read<AudioProvider>().libraryController.refresh();
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Banner Section
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 14, bottom: 24),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0x33EC4899),
                        Color(0x1F8B5CF6),
                        Color(0x150A0D14),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0x33EC4899)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x11EC4899),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x33EC4899),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0x4DEC4899)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.wand,
                                  size: 11,
                                  color: AppTheme.primaryPink,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'IMPORT MAGIQUE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryPink,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!kIsWeb && (Platform.isMacOS || Platform.isIOS))
                            ElevatedButton.icon(
                              onPressed: () => AppleMusicImportWizard.show(context),
                              icon: const Icon(LucideIcons.download, size: 14),
                              label: const Text("Importer Musique"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryPink.withValues(alpha: 0.18),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: const BorderSide(color: Color(0x4DEC4899)),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Import',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "1. ",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryPink,
                              fontSize: 13,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              "Chargez une playlist dans la file d'attente de votre lecteur (Spotify, Musique...).",
                              style: TextStyle(
                                color: Colors.white70,
                                height: 1.4,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "2. ",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryPink,
                              fontSize: 13,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              "Cliquez sur Importer. L'aspirateur capturera toute la file d'attente !",
                              style: TextStyle(
                                color: Colors.white70,
                                height: 1.4,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Action Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141721),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0x1FFFFFFF)),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        LucideIcons.radio,
                        size: 48,
                        color: _isScanning
                            ? AppTheme.primaryPink
                            : AppTheme.textMuted,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Radar Multimédia",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isScanning
                            ? "Recherche de lecteurs actifs..."
                            : "Prêt à scanner les applications externes.",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isScanning ? null : _startScan,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryPink,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: _isScanning
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                "Importer",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                      if (!kIsWeb && Platform.isAndroid) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _openRestrictedSettings,
                          icon: const Icon(
                            LucideIcons.shield_alert,
                            size: 16,
                            color: Colors.white70,
                          ),
                          label: const Text(
                            "Désactiver/activer les paramètres restreints",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 44),
                            side: const BorderSide(color: Color(0x33FFFFFF)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          "Ouvre les infos de l'app. Cliquez sur les 3 points (⋮) en haut à droite.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_results.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.only(top: 16, bottom: 140),
              sliver: SliverList.separated(
                itemCount: _results.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final parts = _results[index].split('|||');
                  final title = parts.isNotEmpty ? parts[0] : 'Inconnu';
                  final rawArtist = parts.length > 1
                      ? parts[1]
                      : 'Artiste inconnu';
                  final album = parts.length > 2 ? parts[2] : 'Single';
                  final duration = parts.length > 3
                      ? (int.tryParse(parts[3]) ?? 0)
                      : 0;

                  String artistName = rawArtist;
                  if (artistName.contains(' & ')) {
                    artistName = artistName.split(' & ')[0].trim();
                  }
                  if (artistName.contains(', ')) {
                    artistName = artistName.split(', ')[0].trim();
                  }

                  final artistId =
                      "local_art_${artistName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}";
                  final albumId =
                      "local_alb_${album.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}_$artistId";
                  final trackId =
                      "local_trk_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}_$albumId";

                  // On cherche le vrai morceau dans la base (car il a déjà été importé)
                  final realTrack = context
                      .read<AudioProvider>()
                      .libraryController
                      .trackById(trackId);

                  final trackToDisplay =
                      realTrack ??
                      Track(
                        id: trackId,
                        title: title,
                        artist: artistName,
                        artistId: artistId,
                        album: album,
                        albumId: albumId,
                        duration: duration,
                        coverUrl: '',
                        audioUrl: '',
                        genre: 'Imported',
                        ambientColor: '#1A1A1A',
                      );

                  return TrackTile(
                    track: trackToDisplay,
                    // L'utilisateur peut cliquer dessus pour l'écouter comme dans le reste de l'appli !
                    onTap: null,
                    trailing: realTrack != null
                        ? const Icon(
                            LucideIcons.check,
                            size: 20,
                            color: AppTheme.primaryPink,
                          )
                        : const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                  );
                },
              ),
            )
          else
            const SliverToBoxAdapter(
              child: SizedBox(height: 140),
            ),
        ],
      ),
    );
  }
}
