import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_network_image.dart';

class ExploreView extends StatelessWidget {
  const ExploreView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    final channels = [
      {
        'title': 'Synthwave & Cyberpunk',
        'colors': [const Color(0xFF9333EA), const Color(0xFFDB2777), const Color(0xFFEF4444)],
        'bg': 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?auto=format&fit=crop&w=500&q=80',
      },
      {
        'title': 'Neo-R&B & Soul',
        'colors': [const Color(0xFFEC4899), const Color(0xFF7E22CE), const Color(0xFF3730A3)],
        'bg': 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?auto=format&fit=crop&w=500&q=80',
      },
      {
        'title': 'Lo-Fi Chill & Beats',
        'colors': [const Color(0xFF2563EB), const Color(0xFF14B8A6), const Color(0xFF059669)],
        'bg': 'https://images.unsplash.com/photo-1509198397868-475647b2a1e5?auto=format&fit=crop&w=500&q=80',
      },
      {
        'title': 'Spatial 3D Audio',
        'colors': [const Color(0xFF4F46E5), const Color(0xFF9333EA), const Color(0xFFEC4899)],
        'bg': 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&w=500&q=80',
      },
      {
        'title': 'Progressive House',
        'colors': [const Color(0xFFF59E0B), const Color(0xFFEA580C), const Color(0xFFDC2626)],
        'bg': 'https://images.unsplash.com/photo-1451187580459-43490279c0fa?auto=format&fit=crop&w=500&q=80',
      },
      {
        'title': 'Indie Folk & Acoustic',
        'colors': [const Color(0xFF059669), const Color(0xFF0F766E), const Color(0xFF155E75)],
        'bg': 'https://images.unsplash.com/photo-1448375240586-882707db888b?auto=format&fit=crop&w=500&q=80',
      },
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Banner
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x33EC4899),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x4DEC4899)),
                ),
                child: const Icon(LucideIcons.compass, color: AppTheme.primaryPink, size: 24),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Explorer les Genres & Canaux Hi-Fi',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    'Découvrez les univers musicaux et flux masterisés en audio spatial',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Channel Cards
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: channels.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isDesktop ? 3 : 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.5,
            ),
            itemBuilder: (context, idx) {
              final ch = channels[idx];
              return InkWell(
                onTap: () {
                  final audio = context.read<AudioProvider>();
                  if (audio.allTracks.isNotEmpty) {
                    audio.playTrack(audio.allTracks[idx % audio.allTracks.length], audio.allTracks);
                  }
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      colors: ch['colors'] as List<Color>,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 15,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: 120,
                        child: Opacity(
                          opacity: 0.35,
                          child: AppNetworkImage(
                            imageUrl: ch['bg'] as String,
                            borderRadius: 0,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0x66000000),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'CANAL ${idx + 1}',
                                style: const TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            Text(
                              ch['title'] as String,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
