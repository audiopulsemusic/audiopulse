import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';
import 'app_network_image.dart';

class _BottomNavProgressLine extends StatelessWidget {
  final Color ambientColor;
  const _BottomNavProgressLine({required this.ambientColor});

  @override
  Widget build(BuildContext context) {
    final progress = context.select<AudioProvider, double>((a) {
      final dur = a.duration.inSeconds > 0 ? a.duration.inSeconds : 1;
      final cur = a.currentPosition.inSeconds;
      return (cur / dur).clamp(0.0, 1.0);
    });

    return Container(
      height: 2.5,
      width: double.infinity,
      color: const Color(0x1AFFFFFF),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: progress,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primaryPink,
                ambientColor,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: ambientColor.withValues(alpha: 0.8),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BottomNavBar extends StatelessWidget {
  const BottomNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    final track = context.select<AudioProvider, Track?>((a) => a.currentTrack);
    final hasTrack = track != null;
    final isPlaying = context.select<AudioProvider, bool>((a) => a.isPlaying);
    final activeView = context.select<AudioProvider, String>((a) => a.activeView);
    final ambientColor = hasTrack ? AppTheme.parseHexColor(track.ambientColor) : AppTheme.primaryPink;

    final navItems = [
      {'id': 'home', 'label': 'Bibliothèque', 'icon': LucideIcons.library},
      {'id': 'search', 'label': 'Recherche', 'icon': LucideIcons.search},
      {'id': 'queueImport', 'label': 'Import', 'icon': LucideIcons.radio},
      {'id': 'share', 'label': 'Partager', 'icon': LucideIcons.qr_code},
      {'id': 'settings', 'label': 'Paramètres', 'icon': LucideIcons.settings},
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xF5000000),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: hasTrack ? ambientColor.withValues(alpha: 0.35) : const Color(0x2BFFFFFF),
          width: 1.2,
        ),
        boxShadow: [
          const BoxShadow(
            color: Colors.black,
            blurRadius: 30,
            offset: Offset(0, 10),
          ),
          if (hasTrack)
            BoxShadow(
              color: ambientColor.withValues(alpha: 0.2),
              blurRadius: 22,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Integrated Mini-Player Section (if track is active)
            if (hasTrack) ...[
              // Top Progress Line (Isolé pour 60 FPS sans rebuild de la barre de navigation)
              _BottomNavProgressLine(ambientColor: ambientColor),

              // Mini Player Controls Row
              InkWell(
                onTap: () => context.read<AudioProvider>().setIsFullPlayerOpen(true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      // Mini Artwork
                      AppNetworkImage(
                        imageUrl: track.coverUrl,
                        width: 40,
                        height: 40,
                        borderRadius: 10,
                      ),
                      const SizedBox(width: 10),

                      // Track Info
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
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: ambientColor,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Previous
                      IconButton(
                        onPressed: () => context.read<AudioProvider>().playPrevious(),
                        tooltip: 'Morceau précédent',
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        icon: const Icon(LucideIcons.skip_back, size: 18, color: Colors.white),
                      ),

                      // Hero Play/Pause
                      GestureDetector(
                        onTap: () => context.read<AudioProvider>().togglePlayPause(),
                        child: Container(
                          width: 36,
                          height: 36,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ambientColor,
                            boxShadow: [
                              BoxShadow(
                                color: ambientColor.withValues(alpha: 0.6),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              isPlaying ? LucideIcons.pause : LucideIcons.play,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      // Next
                      IconButton(
                        onPressed: () => context.read<AudioProvider>().playNext(),
                        tooltip: 'Morceau suivant',
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        icon: const Icon(LucideIcons.skip_forward, size: 18, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),

              const Divider(color: Color(0x1FFFFFFF), height: 1),
            ],

            // 2. Navigation Tabs Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: navItems.map((item) {
                  final isSelected = activeView == item['id'];
                  return Expanded(
                    child: InkWell(
                      onTap: () => context.read<AudioProvider>().setActiveView(item['id'] as String),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0x22EC4899) : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              item['icon'] as IconData,
                              size: 19,
                              color: isSelected ? AppTheme.primaryPink : AppTheme.textSecondary,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item['label'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected ? Colors.white : AppTheme.textMuted,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
