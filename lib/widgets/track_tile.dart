import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';
import 'app_network_image.dart';
import 'track_actions_modal.dart';

/// Reusable unified track item component used across all views of AudioPulse
class TrackTile extends StatelessWidget {
  final Track track;
  final List<Track>? playlistContext;
  final VoidCallback? onTap;
  final bool showQualityBadge;
  final bool showDownloadButton;
  final Widget? trailing;

  const TrackTile({
    super.key,
    required this.track,
    this.playlistContext,
    this.onTap,
    this.showQualityBadge = false,
    this.showDownloadButton = true,
    this.trailing,
  });

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0:00';
    final mins = seconds ~/ 60;
    final remSecs = seconds % 60;
    return '$mins:${remSecs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final currentTrack = context.select<AudioProvider, Track?>((a) => a.currentTrack?.id == track.id ? a.currentTrack : null);
    final localTrack = context.select<AudioProvider, Track?>((a) => a.allTracks.where((t) => t.id == track.id).firstOrNull);
    final effectiveTrack = (currentTrack != null && currentTrack.bitrate > 0)
        ? currentTrack
        : (localTrack != null && localTrack.bitrate > 0)
            ? localTrack
            : (currentTrack ?? localTrack ?? track);

    final isCurrent = context.select<AudioProvider, bool>((a) => a.currentTrack?.id == effectiveTrack.id);
    final isDownloaded = context.select<AudioProvider, bool>((a) {
      final local = a.allTracks.where((t) => t.id == effectiveTrack.id).firstOrNull;
      return (local?.isDownloaded ?? effectiveTrack.isDownloaded) &&
          (local?.localFilePath != null || effectiveTrack.localFilePath != null);
    });
    final downloadProg = context.select<AudioProvider, double?>((a) => a.downloadProgress[effectiveTrack.id]);
    final isLoadingThisTrack = context.select<AudioProvider, bool>((a) => a.loadingTrackId == effectiveTrack.id);
    final ambientColor = AppTheme.parseHexColor(effectiveTrack.ambientColor);

    Offset? tapPosition;

    return InkWell(
      onTap: onTap ?? () {
        if (TrackActionsModal.wasRecentlyDismissed) return;
        final audio = context.read<AudioProvider>();
        audio.playTrack(effectiveTrack, playlistContext);
      },
      onTapDown: (details) {
        tapPosition = details.globalPosition;
      },
      onLongPress: () {
        TrackActionsModal.show(context, effectiveTrack, tapPosition: tapPosition);
      },
      onSecondaryTapDown: (details) {
        tapPosition = details.globalPosition;
      },
      onSecondaryTap: () {
        TrackActionsModal.show(context, effectiveTrack, tapPosition: tapPosition);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isCurrent ? const Color(0x26EC4899) : const Color(0x800E121B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCurrent
                ? AppTheme.primaryPink.withValues(alpha: 0.6)
                : const Color(0x1AFFFFFF),
          ),
        ),
        child: Row(
          children: [
            // Cover Artwork (Clean)
            AppNetworkImage(
              imageUrl: effectiveTrack.coverUrl,
              width: 44,
              height: 44,
              borderRadius: 10,
            ),
            const SizedBox(width: 12),

            // Track Title & Artist Name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    effectiveTrack.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isCurrent ? AppTheme.primaryPink : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      // Badge 1x1 : Source (Music vs YouTube)
                      Container(
                        margin: const EdgeInsets.only(right: 5),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: effectiveTrack.source == 'music'
                              ? const Color(0x3306B6D4) // Cyan tint for YouTube Music
                              : const Color(0x33EF4444), // Red tint for YouTube
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: effectiveTrack.source == 'music'
                                ? const Color(0x4D06B6D4)
                                : const Color(0x4DEF4444),
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          effectiveTrack.source == 'music' ? 'M' : 'YT',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: effectiveTrack.source == 'music'
                                ? const Color(0xFF22D3EE)
                                : const Color(0xFFF87171),
                            height: 1.0,
                          ),
                        ),
                      ),
                      // Badge 1x1 : Explicit (E)
                      if (effectiveTrack.isExplicit) ...[
                        Container(
                          margin: const EdgeInsets.only(right: 5),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'E',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Colors.white70,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ],
                      // Badge Bitrate Réel (Pastille Bitrate uniquement si mesuré, ex: 134 kbps, 160 kbps)
                      if (effectiveTrack.bitrate > 0) ...[
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0x268B5CF6),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: const Color(0x4D8B5CF6),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            '${effectiveTrack.bitrate} kbps',
                            style: const TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFA78BFA),
                              height: 1.0,
                            ),
                          ),
                        ),
                      ],
                      Expanded(
                        child: Text(
                          effectiveTrack.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: isCurrent ? ambientColor : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      if (showQualityBadge)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0x1F10B981),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0x4D10B981)),
                          ),
                          child: const Text(
                            '320k eq',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppTheme.accentEmerald,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Trailing Actions (Loading Indicator / Download Button + Duration)
            if (trailing != null)
              trailing!
            else ...[
              if (isLoadingThisTrack)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primaryPink,
                    ),
                  ),
                )
              else if (showDownloadButton)
                if (downloadProg != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        value: downloadProg > 0 ? downloadProg : null,
                        strokeWidth: 2.5,
                        color: AppTheme.accentEmerald,
                      ),
                    ),
                  )
                else
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      final audio = context.read<AudioProvider>();
                      if (!audio.allTracks.any((t) => t.id == effectiveTrack.id)) {
                        await audio.playTrack(effectiveTrack);
                      }
                      await audio.toggleDownload(effectiveTrack.id);
                    },
                    tooltip: 'Télécharger en local',
                    icon: Icon(
                      isDownloaded ? LucideIcons.circle_check : LucideIcons.download,
                      size: 17,
                      color: isDownloaded ? AppTheme.accentEmerald : AppTheme.textMuted,
                    ),
                  ),
              Text(
                _formatDuration(effectiveTrack.duration),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 4),
              // Bouton Options contextuelles 3-points (Clic gauche PC & tactile)
              Builder(
                builder: (btnContext) {
                  return IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    tooltip: 'Options du morceau',
                    icon: const Icon(
                      LucideIcons.ellipsis_vertical,
                      size: 15,
                      color: AppTheme.textMuted,
                    ),
                    onPressed: () {
                      final renderBox = btnContext.findRenderObject() as RenderBox?;
                      final offset = renderBox?.localToGlobal(Offset.zero);
                      final position = offset != null
                          ? Offset(offset.dx, offset.dy + renderBox!.size.height)
                          : null;
                      TrackActionsModal.show(context, effectiveTrack, tapPosition: position);
                    },
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
