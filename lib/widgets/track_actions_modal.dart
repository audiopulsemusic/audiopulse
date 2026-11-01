import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';

import '../models/artist.dart';
import '../models/track.dart';
import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';
import 'album_playlist_stage.dart';
import 'app_network_image.dart';

/// Modal contextuel pour les morceaux de musique (appui long tactile / clic droit bureau)
class TrackActionsModal {
  TrackActionsModal._();

  /// Horodatage de fermeture du dernier modal / menu pour éviter les clics fantômes (ghost taps)
  static DateTime lastDismissedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Indique si un menu ou bottom sheet contextuel vient d'être fermé (protection anti-clic intempestif)
  static bool get wasRecentlyDismissed =>
      DateTime.now().difference(lastDismissedAt).inMilliseconds < 450;

  /// Affiche le menu contextuel selon la plateforme et la position du clic
  static Future<void> show(
    BuildContext context,
    Track track, {
    Offset? tapPosition,
  }) async {
    final isDesktop = !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

    if (isDesktop && tapPosition != null) {
      await _showDesktopMenu(context, track, tapPosition);
    } else {
      await _showMobileBottomSheet(context, track);
    }
  }

  /// Menu contextuel flottant pour Desktop (au curseur de la souris)
  static Future<void> _showDesktopMenu(
    BuildContext context,
    Track track,
    Offset position,
  ) async {
    final audio = context.read<AudioProvider>();
    final isDownloaded = audio.allTracks.any((t) => t.id == track.id && t.isDownloaded) || track.isDownloaded;
    final hasAlbum = track.album.isNotEmpty &&
        track.album != 'Single' &&
        track.album != 'Single Web' &&
        track.album != 'Streaming Web' &&
        track.album != 'Master Hi-Fi • 320k eq';

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final rect = overlay != null
        ? RelativeRect.fromRect(
            Rect.fromLTWH(position.dx, position.dy, 1, 1),
            Offset.zero & overlay.size,
          )
        : RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1);

    final action = await showMenu<String>(
      context: context,
      position: rect,
      color: const Color(0xFF131826),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0x26FFFFFF), width: 0.8),
      ),
      items: [
        // En-tête avec Jaquette, Titre, Artiste
        PopupMenuItem<String>(
          enabled: false,
          child: Row(
            children: [
              AppNetworkImage(
                imageUrl: track.coverUrl,
                width: 38,
                height: 38,
                borderRadius: 8,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),

        // 1. Lire juste après
        _buildPopupItem(
          value: 'play_next',
          icon: LucideIcons.list_plus,
          label: 'Lire juste après',
          iconColor: AppTheme.primaryPink,
        ),

        // 2. Ajouter à la file d'attente
        _buildPopupItem(
          value: 'add_to_queue',
          icon: LucideIcons.list_music,
          label: 'Ajouter à la file d\'attente',
          iconColor: const Color(0xFF22D3EE),
        ),

        // 3. Télécharger ou Supprimer du stockage local
        _buildPopupItem(
          value: 'toggle_download',
          icon: isDownloaded ? LucideIcons.trash_2 : LucideIcons.download,
          label: isDownloaded ? 'Supprimer du stockage local' : 'Télécharger (Studio)',
          iconColor: isDownloaded ? const Color(0xFFF87171) : AppTheme.accentEmerald,
        ),

        // 4. Accéder à l'artiste
        _buildPopupItem(
          value: 'go_artist',
          icon: LucideIcons.user,
          label: 'Voir l\'artiste',
          iconColor: Colors.white70,
        ),

        // 5. Accéder à l'album (si disponible)
        if (hasAlbum)
          _buildPopupItem(
            value: 'go_album',
            icon: LucideIcons.disc,
            label: 'Voir l\'album',
            iconColor: Colors.white70,
          ),

        // 6. Infos & Qualité audio
        _buildPopupItem(
          value: 'info',
          icon: LucideIcons.info,
          label: 'Détails & Qualité audio',
          iconColor: const Color(0xFFA78BFA),
        ),
      ],
    );

    lastDismissedAt = DateTime.now();

    if (action != null && context.mounted) {
      _handleAction(context, action, track, isDownloaded);
    }
  }

  static PopupMenuItem<String> _buildPopupItem({
    required String value,
    required IconData icon,
    required String label,
    required Color iconColor,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom Sheet moderne pour Mobile / Écran tactile
  static Future<void> _showMobileBottomSheet(BuildContext context, Track track) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        final audio = modalContext.watch<AudioProvider>();
        final isDownloaded = audio.allTracks.any((t) => t.id == track.id && t.isDownloaded) || track.isDownloaded;
        final hasAlbum = track.album.isNotEmpty &&
            track.album != 'Single' &&
            track.album != 'Single Web' &&
            track.album != 'Streaming Web' &&
            track.album != 'Master Hi-Fi • 320k eq';

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Poignée de glissement
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // En-tête : Jaquette, Titre, Artiste, Badges
                Row(
                  children: [
                    AppNetworkImage(
                      imageUrl: track.coverUrl,
                      width: 52,
                      height: 52,
                      borderRadius: 12,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              // Badge M ou YT
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: track.source == 'music'
                                      ? const Color(0x3306B6D4)
                                      : const Color(0x33EF4444),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                    color: track.source == 'music'
                                        ? const Color(0x4D06B6D4)
                                        : const Color(0x4DEF4444),
                                    width: 0.5,
                                  ),
                                ),
                                child: Text(
                                  track.source == 'music' ? 'M' : 'YT',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: track.source == 'music'
                                        ? const Color(0xFF22D3EE)
                                        : const Color(0xFFF87171),
                                  ),
                                ),
                              ),
                              // Badge Débit si mesuré
                              if (track.bitrate > 0)
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0x268B5CF6),
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: const Color(0x4D8B5CF6), width: 0.5),
                                  ),
                                  child: Text(
                                    '${track.bitrate} kbps',
                                    style: const TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFA78BFA),
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0x1AFFFFFF), height: 1),
                const SizedBox(height: 8),

                // Liste des actions
                // 1. Lire juste après
                _buildActionTile(
                  context: modalContext,
                  icon: LucideIcons.list_plus,
                  label: 'Lire juste après',
                  subtitle: 'Insérer juste après la lecture en cours',
                  iconColor: AppTheme.primaryPink,
                  onTap: () {
                    Navigator.of(modalContext).pop();
                    _handleAction(context, 'play_next', track, isDownloaded);
                  },
                ),

                // 2. Ajouter à la file d'attente
                _buildActionTile(
                  context: modalContext,
                  icon: LucideIcons.list_music,
                  label: 'Ajouter à la file d\'attente',
                  subtitle: 'Placer à la fin de la file de lecture',
                  iconColor: const Color(0xFF22D3EE),
                  onTap: () {
                    Navigator.of(modalContext).pop();
                    _handleAction(context, 'add_to_queue', track, isDownloaded);
                  },
                ),

                // 3. Télécharger ou Supprimer
                _buildActionTile(
                  context: modalContext,
                  icon: isDownloaded ? LucideIcons.trash_2 : LucideIcons.download,
                  label: isDownloaded ? 'Supprimer du stockage local' : 'Télécharger (Studio)',
                  subtitle: isDownloaded
                      ? 'Supprimer les données hors-ligne de cet appareil'
                      : 'Audio haute fidélité pour une écoute sans connexion',
                  iconColor: isDownloaded ? const Color(0xFFF87171) : AppTheme.accentEmerald,
                  onTap: () {
                    Navigator.of(modalContext).pop();
                    _handleAction(context, 'toggle_download', track, isDownloaded);
                  },
                ),

                // 4. Accéder à l'artiste
                _buildActionTile(
                  context: modalContext,
                  icon: LucideIcons.user,
                  label: 'Voir l\'artiste',
                  subtitle: track.artist,
                  iconColor: Colors.white70,
                  onTap: () {
                    Navigator.of(modalContext).pop();
                    _handleAction(context, 'go_artist', track, isDownloaded);
                  },
                ),

                // 5. Accéder à l'album
                if (hasAlbum)
                  _buildActionTile(
                    context: modalContext,
                    icon: LucideIcons.disc,
                    label: 'Voir l\'album',
                    subtitle: track.album,
                    iconColor: Colors.white70,
                    onTap: () {
                      Navigator.of(modalContext).pop();
                      _handleAction(context, 'go_album', track, isDownloaded);
                    },
                  ),

                // 6. Infos & Qualité audio
                _buildActionTile(
                  context: modalContext,
                  icon: LucideIcons.info,
                  label: 'Détails & Qualité audio',
                  subtitle: 'Débit, format et conteneur du flux',
                  iconColor: const Color(0xFFA78BFA),
                  onTap: () {
                    Navigator.of(modalContext).pop();
                    _handleAction(context, 'info', track, isDownloaded);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
    lastDismissedAt = DateTime.now();
  }

  static Widget _buildActionTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String subtitle,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(LucideIcons.chevron_right, size: 16, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  /// Exécute l'action sélectionnée
  static void _handleAction(
    BuildContext context,
    String action,
    Track track,
    bool isDownloaded,
  ) {
    final audio = context.read<AudioProvider>();

    switch (action) {
      case 'play_next':
        audio.playNextTrack(track);
        _showToast(context, 'Sera lu juste après : "${track.title}"');
        break;

      case 'add_to_queue':
        audio.addToQueue(track);
        _showToast(context, 'Ajouté à la file d\'attente : "${track.title}"');
        break;

      case 'toggle_download':
        audio.toggleDownload(track.id, track);
        _showToast(
          context,
          isDownloaded
              ? 'Suppression de "${track.title}" en cours...'
              : 'Téléchargement studio de "${track.title}" lancé...',
        );
        break;

      case 'go_artist':
        final artistObj = Artist(
          id: track.artistId.isNotEmpty ? track.artistId : track.artist,
          name: track.artist,
          avatarUrl: track.artistAvatarUrl,
          bannerUrl: '',
          bio: 'Artiste Officiel',
          tracks: const [],
          albums: const [],
        );
        audio.selectArtistAndNavigate(artistObj);
        break;

      case 'go_album':
        AlbumPlaylistStage.showAsBottomSheet(
          context,
          matchTrack: track,
          title: track.album,
          artist: track.artist,
        );
        break;

      case 'info':
        _showTrackInfoDialog(context, track);
        break;
    }
  }

  /// Boîte de dialogue présentant les détails techniques et la qualité audio du morceau
  static void _showTrackInfoDialog(BuildContext context, Track track) {
    final mins = track.duration ~/ 60;
    final secs = track.duration % 60;
    final durationStr = '$mins:${secs.toString().padLeft(2, '0')}';
    final isApple = !kIsWeb && (Platform.isMacOS || Platform.isIOS);

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF131826),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0x26FFFFFF)),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0x268B5CF6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(LucideIcons.info, color: Color(0xFFA78BFA), size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'Détails & Qualité audio',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Titre', track.title),
              _buildInfoRow('Artiste', track.artist),
              if (track.album.isNotEmpty) _buildInfoRow('Album', track.album),
              _buildInfoRow('Durée', durationStr),
              _buildInfoRow(
                'Débit réel',
                track.bitrate > 0 ? '${track.bitrate} kbps (Mesuré)' : 'Non mesuré (en attente de lecture)',
                valueColor: track.bitrate > 0 ? const Color(0xFFA78BFA) : AppTheme.textMuted,
              ),
              _buildInfoRow(
                'Format audio',
                isApple ? 'AAC Audio (Compatible AVPlayer Apple)' : 'Opus Audio (Compatible Android)',
              ),
              _buildInfoRow(
                'Conteneur',
                isApple ? '.m4a (MPEG-4 Audio)' : '.opus (WebM Audio)',
              ),
              _buildInfoRow(
                'Source',
                track.source == 'music' ? 'YouTube Music (Officiel)' : 'YouTube Vidéo Audio',
                valueColor: track.source == 'music' ? const Color(0xFF22D3EE) : const Color(0xFFF87171),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fermer', style: TextStyle(color: AppTheme.primaryPink, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  static Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11.5,
                color: valueColor ?? Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void _showToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12, color: Colors.white)),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

