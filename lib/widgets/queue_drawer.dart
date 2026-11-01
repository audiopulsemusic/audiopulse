import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';
import '../models/track.dart';
import 'track_tile.dart';

class QueueDrawer extends StatelessWidget {
  const QueueDrawer({super.key});

  String _formatTotalDuration(List<Track> queue) {
    final totalSeconds = queue.fold<int>(0, (sum, t) => sum + t.duration);
    if (totalSeconds <= 0) return '0 min';
    final mins = totalSeconds ~/ 60;
    final hrs = mins ~/ 60;
    final remMins = mins % 60;
    if (hrs > 0) {
      return '$hrs h $remMins min';
    }
    return '$mins min';
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = context.select<AudioProvider, bool>((a) => a.isQueueOpen);
    final queue = context.select<AudioProvider, List<Track>>((a) => a.queue);
    final currentTrack = context.select<AudioProvider, Track?>((a) => a.currentTrack);
    final currentIndex = context.select<AudioProvider, int>((a) => a.queueIndex);
    final isPlaying = context.select<AudioProvider, bool>((a) => a.isPlaying);

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final drawerWidth = isMobile ? screenWidth : math.min(screenWidth * 0.85, 460.0);

    return IgnorePointer(
      ignoring: !isOpen,
      child: Stack(
        children: [
          // Animated Backdrop overlay barrier
          Positioned.fill(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              opacity: isOpen ? 1.0 : 0.0,
              child: GestureDetector(
                onTap: () => context.read<AudioProvider>().setIsQueueOpen(false),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          ),

          // Animated Sliding Queue Panel
          Align(
            alignment: Alignment.centerRight,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeOutCubic,
              offset: isOpen ? Offset.zero : (isMobile ? const Offset(0, 1.0) : const Offset(1.0, 0)),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOut,
                opacity: isOpen ? 1.0 : 0.0,
                child: Container(
                  width: drawerWidth,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xF5080B10),
                    border: const Border(
                      left: BorderSide(color: Color(0x33FFFFFF), width: 1),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.85),
                        blurRadius: 36,
                        offset: const Offset(-12, 0),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top Navigation & Header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Drag Indicator for mobile
                              if (isMobile)
                                Center(
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    width: 36,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: Colors.white24,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [AppTheme.primaryPink, AppTheme.accentPurple],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(10),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppTheme.primaryPink.withValues(alpha: 0.35),
                                              blurRadius: 10,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(LucideIcons.list_music, color: Colors.white, size: 18),
                                      ),
                                      const SizedBox(width: 10),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'File d\'attente',
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white,
                                              letterSpacing: -0.3,
                                            ),
                                          ),
                                          Text(
                                            '${queue.length} ${queue.length > 1 ? "titres" : "titre"} • ${_formatTotalDuration(queue)}',
                                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),

                                  Row(
                                    children: [
                                      if (queue.isNotEmpty) ...[
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () {
                                            final shuffled = List<Track>.from(queue)..shuffle();
                                            context.read<AudioProvider>().playTrack(shuffled.first, shuffled);
                                          },
                                          tooltip: 'Mélanger la file',
                                          icon: const Icon(LucideIcons.shuffle, size: 17, color: AppTheme.textSecondary),
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => context.read<AudioProvider>().clearQueue(),
                                          tooltip: 'Vider la file',
                                          icon: const Icon(LucideIcons.trash_2, size: 17, color: Colors.redAccent),
                                        ),
                                      ],
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => context.read<AudioProvider>().setIsQueueOpen(false),
                                        tooltip: 'Fermer',
                                        icon: const Icon(LucideIcons.x, size: 20, color: Colors.white70),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const Divider(color: Color(0x1FFFFFFF), height: 1),

                        // Content Area
                        Expanded(
                          child: queue.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(18),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.04),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(LucideIcons.list_music, size: 36, color: AppTheme.textMuted),
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Votre file d\'attente est vide',
                                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Lancez un morceau ou un album pour ajouter des titres.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                      ),
                                    ],
                                  ),
                                )
                              : Theme(
                                  data: Theme.of(context).copyWith(
                                    canvasColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                  ),
                                  child: ReorderableListView.builder(
                                    physics: const BouncingScrollPhysics(),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    itemCount: queue.length,
                                    onReorder: (oldIndex, newIndex) {
                                      context.read<AudioProvider>().reorderQueue(oldIndex, newIndex);
                                    },
                                    proxyDecorator: (child, index, animation) {
                                      return AnimatedBuilder(
                                        animation: animation,
                                        builder: (context, child) {
                                          final animValue = Curves.easeInOut.transform(animation.value);
                                          final scale = lerpDouble(1.0, 1.04, animValue)!;
                                          final elevation = lerpDouble(0, 16, animValue)!;
                                          return Transform.scale(
                                            scale: scale,
                                            child: Material(
                                              elevation: elevation,
                                              color: Colors.transparent,
                                              shadowColor: Colors.black.withValues(alpha: 0.5),
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: child,
                                      );
                                    },
                                    header: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Section Header: Instructions
                                        Row(
                                          children: [
                                            const Icon(LucideIcons.grip_vertical, size: 14, color: AppTheme.textMuted),
                                            const SizedBox(width: 6),
                                            const Text(
                                              'Glissez un morceau pour modifier l\'ordre de lecture',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.textMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                      ],
                                    ),
                                    itemBuilder: (context, index) {
                                      final track = queue[index];
                                      final isCurrent = index == currentIndex || track.id == currentTrack?.id;

                                      return Container(
                                        key: ValueKey('queue_${track.id}_$index'),
                                        margin: const EdgeInsets.only(bottom: 8),
                                        child: TrackTile(
                                          track: track,
                                          playlistContext: queue,
                                          showQualityBadge: false,
                                          showDownloadButton: false,
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Mini Equalizer for current track
                                              if (isCurrent) ...[
                                                _MiniEqualizerBar(
                                                  isPlaying: isPlaying,
                                                  color: AppTheme.primaryPink,
                                                ),
                                                const SizedBox(width: 8),
                                              ],

                                              // Quick Move Up
                                              if (index > 0)
                                                IconButton(
                                                  visualDensity: VisualDensity.compact,
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                  onPressed: () => context.read<AudioProvider>().moveQueueItemUp(index),
                                                  tooltip: 'Monter',
                                                  icon: const Icon(LucideIcons.chevron_up, size: 16, color: AppTheme.textMuted),
                                                ),

                                              // Quick Move Down
                                              if (index < queue.length - 1)
                                                IconButton(
                                                  visualDensity: VisualDensity.compact,
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                  onPressed: () => context.read<AudioProvider>().moveQueueItemDown(index),
                                                  tooltip: 'Descendre',
                                                  icon: const Icon(LucideIcons.chevron_down, size: 16, color: AppTheme.textMuted),
                                                ),

                                              // Remove from Queue
                                              IconButton(
                                                visualDensity: VisualDensity.compact,
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                onPressed: () => context.read<AudioProvider>().removeFromQueue(index),
                                                tooltip: 'Retirer de la file',
                                                icon: const Icon(LucideIcons.x, size: 16, color: Colors.white38),
                                              ),

                                              const SizedBox(width: 4),

                                              // Drag Handle
                                              ReorderableDragStartListener(
                                                index: index,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                                  child: Icon(
                                                    LucideIcons.grip_vertical,
                                                    size: 18,
                                                    color: isCurrent ? AppTheme.primaryPink : Colors.white38,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),

                        // Bottom Bar
                        if (queue.isNotEmpty) ...[
                          const Divider(color: Color(0x1FFFFFFF), height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${queue.length} titres • ${_formatTotalDuration(queue)}',
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                ),
                                ElevatedButton(
                                  onPressed: () => context.read<AudioProvider>().setIsQueueOpen(false),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0x26FFFFFF),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: const Text('Fermer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniEqualizerBar extends StatefulWidget {
  final bool isPlaying;
  final Color color;

  const _MiniEqualizerBar({required this.isPlaying, required this.color});

  @override
  State<_MiniEqualizerBar> createState() => _MiniEqualizerBarState();
}

class _MiniEqualizerBarState extends State<_MiniEqualizerBar> with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.isPlaying) {
      _anim.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_MiniEqualizerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_anim.isAnimating) {
      _anim.repeat(reverse: true);
    } else if (!widget.isPlaying && _anim.isAnimating) {
      _anim.stop();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final v = _anim.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              width: 2.5,
              height: 4 + 7 * (0.3 + 0.7 * math.sin(v * math.pi)),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(width: 2),
            Container(
              width: 2.5,
              height: 3 + 9 * (0.2 + 0.8 * math.sin((v + 0.3) * math.pi).abs()),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(width: 2),
            Container(
              width: 2.5,
              height: 4 + 8 * (0.3 + 0.7 * math.cos(v * math.pi).abs()),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        );
      },
    );
  }
}
