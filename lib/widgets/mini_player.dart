import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';
import 'app_network_image.dart';

class _MiniPlayerProgressBar extends StatelessWidget {
  final Color ambientColor;
  const _MiniPlayerProgressBar({required this.ambientColor});

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
                AppTheme.accentPurple,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryPink.withValues(alpha: 0.8),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final track = context.select<AudioProvider, Track?>((a) => a.currentTrack);
    if (track == null) return const SizedBox.shrink();

    final isPlaying = context.select<AudioProvider, bool>((a) => a.isPlaying);
    final isLoadingStream = context.select<AudioProvider, bool>((a) => a.isLoadingStream);
    final streamStatusMessage = context.select<AudioProvider, String>((a) => a.streamStatusMessage);
    final ambientColor = AppTheme.parseHexColor(track.ambientColor);

    return GestureDetector(
      onTap: () => context.read<AudioProvider>().setIsFullPlayerOpen(true),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xF20E121B),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x33FFFFFF), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: ambientColor.withValues(alpha: 0.25),
              blurRadius: 15,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Ultra-Slim Progress Line (Isolé pour 60 FPS constants sans rebuild du corps)
              _MiniPlayerProgressBar(ambientColor: ambientColor),

              // Player Content Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    // Album Cover with Neon Ambient Border
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: ambientColor.withValues(alpha: 0.4),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: AppNetworkImage(
                            imageUrl: track.coverUrl,
                            width: 44,
                            height: 44,
                            borderRadius: 10,
                          ),
                        ),
                        if (isPlaying)
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0x55000000),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              LucideIcons.audio_lines,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(width: 12),

                    // Track Title & Artist
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
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: ambientColor,
                                  ),
                                ),
                              ),
                              if (track.isExplicit) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0x33EF4444),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: const Text(
                                    'E',
                                    style: TextStyle(
                                      fontSize: 7,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (isLoadingStream || (streamStatusMessage.isNotEmpty && !isPlaying))
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                children: [
                                  if (isLoadingStream) ...[
                                    const SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: AppTheme.accentEmerald,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                  ],
                                  Flexible(
                                    child: Text(
                                      streamStatusMessage,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: isLoadingStream ? AppTheme.accentEmerald : const Color(0xFFF59E0B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Transport Actions
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () => context.read<AudioProvider>().playPrevious(),
                          tooltip: 'Précédent',
                          icon: const Icon(
                            LucideIcons.skip_back,
                            size: 18,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => context.read<AudioProvider>().togglePlayPause(),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  AppTheme.primaryPink,
                                  ambientColor,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryPink.withValues(alpha: 0.5),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                isPlaying ? LucideIcons.pause : LucideIcons.play,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () => context.read<AudioProvider>().playNext(),
                          tooltip: 'Suivant',
                          icon: const Icon(
                            LucideIcons.skip_forward,
                            size: 18,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
