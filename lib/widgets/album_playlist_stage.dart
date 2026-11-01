import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';
import 'app_network_image.dart';
import 'track_tile.dart';

/// Composant unifié pour l'affichage complet de la scène / modale d'un album ou d'une playlist.
/// Utilisé de manière identique dans le lecteur plein écran (FullscreenPlayer) et lors du clic sur un album (SearchView / ArtistView).
class AlbumPlaylistStage extends StatelessWidget {
  final String title;
  final String artist;
  final String coverUrl;
  final String genre;
  final Color ambientColor;
  final VoidCallback? onClose;
  final String closeLabel;
  final ValueChanged<Track>? onTrackTap;

  const AlbumPlaylistStage({
    super.key,
    required this.title,
    required this.artist,
    required this.coverUrl,
    this.genre = 'Album',
    this.ambientColor = AppTheme.primaryPink,
    this.onClose,
    this.closeLabel = 'Glisser vers le bas pour revenir au lecteur',
    this.onTrackTap,
  });

  /// Ouvre la scène d'album sous forme de bottom sheet plein écran avec exactement le même code et design.
  static Future<void> showAsBottomSheet(
    BuildContext context, {
    required Track matchTrack,
    String? title,
    String? artist,
    String? coverUrl,
    String genre = 'Album',
    Color? ambientColor,
    ValueChanged<Track>? onTrackTap,
  }) {
    final audio = context.read<AudioProvider>();
    audio.loadAlbumTracks(matchTrack);

    final effectiveColor = ambientColor ?? AppTheme.parseHexColor(matchTrack.ambientColor);
    final effectiveTitle = (title != null && title.isNotEmpty)
        ? title
        : (matchTrack.album.isNotEmpty ? matchTrack.album : matchTrack.title);
    final effectiveArtist = (artist != null && artist.isNotEmpty) ? artist : matchTrack.artist;
    final effectiveCover = (coverUrl != null && coverUrl.isNotEmpty) ? coverUrl : matchTrack.coverUrl;

    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0E17),
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        return FractionallySizedBox(
          heightFactor: 0.88,
          child: AlbumPlaylistStage(
            title: effectiveTitle,
            artist: effectiveArtist,
            coverUrl: effectiveCover,
            genre: genre,
            ambientColor: effectiveColor,
            closeLabel: 'Glisser vers le bas pour revenir au lecteur',
            onClose: () => Navigator.of(modalContext).pop(),
            onTrackTap: onTrackTap,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioProvider>();

    return SafeArea(
      child: Column(
        children: [
          // 1. Indicateur de fermeture / repliage supérieur
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 8),
            child: InkWell(
              onTap: onClose,
              child: Column(
                children: [
                  Icon(
                    LucideIcons.chevron_down,
                    size: 16,
                    color: ambientColor.withValues(alpha: 0.8),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    closeLabel,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textMuted,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. En-tête : Jaquette 64x64 + Tag ALBUM/PLAYLIST + Titre + Artiste
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0x990E121B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x22FFFFFF)),
              ),
              child: Row(
                children: [
                  AppNetworkImage(
                    imageUrl: coverUrl,
                    width: 64,
                    height: 64,
                    borderRadius: 14,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: ambientColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: ambientColor.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            (genre == 'Playlist' ||
                                    genre == 'Playlist Track' ||
                                    genre == 'Playlist Officielle')
                                ? 'PLAYLIST'
                                : 'ALBUM',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Liste des morceaux de l'album
          Expanded(
            child: Builder(
              builder: (context) {
                if (audio.isLoadingAlbumTracks) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: ambientColor),
                        const SizedBox(height: 12),
                        const Text(
                          'Chargement de l\'album complet...',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }

                if (audio.currentAlbumTracks.isEmpty) {
                  return const Center(
                    child: Text(
                      'Aucune autre piste trouvée pour cet album.',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    ),
                  );
                }

                return ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                  itemCount: audio.currentAlbumTracks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final albumTrack = audio.currentAlbumTracks[index];
                    return TrackTile(
                      track: albumTrack,
                      playlistContext: audio.currentAlbumTracks,
                      showQualityBadge: false,
                      showDownloadButton: true,
                      onTap: onTrackTap != null ? () => onTrackTap!(albumTrack) : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

