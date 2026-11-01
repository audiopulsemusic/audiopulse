import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final autoPlayNext = context.select<AudioProvider, bool>((a) => a.autoPlayNext);
    final autoDownload = context.select<AudioProvider, bool>((a) => a.autoDownload);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 16, bottom: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0x33EC4899),
                  Color(0x1FF43F5E),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0x33EC4899),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0x4DEC4899)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.sliders_horizontal, size: 11, color: Color(0xFFF472B6)),
                          SizedBox(width: 5),
                          Text(
                            'CONFIGURATION & SYSTÈME',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFF472B6),
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Text(
                      'v1.0.0',
                      style: TextStyle(fontSize: 10, color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Paramètres & Stockage',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Personnalisez la lecture, le téléchargement automatique et le cache.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Section 1: Lecture
          _buildSectionTitle('LECTURE & ENCHAÎNEMENT'),
          const SizedBox(height: 10),
          _buildSettingsCard(
            children: [
              _buildSettingTile(
                icon: LucideIcons.fast_forward,
                iconColor: AppTheme.accentPurple,
                title: 'Lecture automatique de la suite',
                subtitle: 'Enchaîne automatiquement avec le morceau suivant à la fin du titre.',
                value: autoPlayNext,
                onChanged: (val) => context.read<AudioProvider>().setAutoPlayNext(val),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Section 2: Téléchargement & Mode Hors-Ligne
          _buildSectionTitle('TÉLÉCHARGEMENT & HORS-LIGNE'),
          const SizedBox(height: 10),
          _buildSettingsCard(
            children: [
              _buildSettingTile(
                icon: LucideIcons.download,
                iconColor: AppTheme.primaryPink,
                title: 'Téléchargement automatique',
                subtitle: 'Télécharge automatiquement en local chaque morceau écouté pour le mode hors-ligne.',
                value: autoDownload,
                onChanged: (val) => context.read<AudioProvider>().setAutoDownload(val),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Section 3: Données & Réinitialisation
          _buildSectionTitle('STOCKAGE & DONNÉES'),
          const SizedBox(height: 10),
          _buildSettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0x1AEF4444),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        LucideIcons.trash_2,
                        color: AppTheme.accentRed,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vider les données de l\'application',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Efface les morceaux récents, métadonnées et vide le cache.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => _showClearDataDialog(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0x22EF4444),
                        foregroundColor: AppTheme.accentRed,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: Color(0x44EF4444)),
                        ),
                      ),
                      child: const Text(
                        'Vider',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Section 4: Partage
          _buildSectionTitle('APPLICATION & PARTAGE'),
          const SizedBox(height: 10),
          _buildSettingsCard(
            children: [
              InkWell(
                onTap: () => context.read<AudioProvider>().setActiveView('share'),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0x22A855F7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          LucideIcons.qr_code,
                          color: Color(0xFFC084FC),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Partager l\'application (QR Code)',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Générez le QR code instantané pour iOS ou Android.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(LucideIcons.chevron_right, size: 18, color: Colors.white38),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Section 5: Confidentialité & Mentions Légales (Exigence Google Play Store TECH-03)
          _buildSectionTitle('CONFIDENTIALITÉ & MENTIONS LÉGALES'),
          const SizedBox(height: 10),
          _buildSettingsCard(
            children: [
              InkWell(
                onTap: () => _showPrivacyPolicySheet(context),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0x2210B981),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          LucideIcons.shield_check,
                          color: AppTheme.accentEmerald,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Politique de confidentialité',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Stockage local, traitement des données et flux réseau.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(LucideIcons.chevron_right, size: 18, color: Colors.white38),
                    ],
                  ),
                ),
              ),
              const Divider(color: Color(0x14FFFFFF), height: 1),
              InkWell(
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Audio Pulse',
                  applicationVersion: '1.0.0',
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0x223B82F6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          LucideIcons.file_text,
                          color: AppTheme.accentBlue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Licences Open-Source',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Crédits et licences des bibliothèques tierces utilisées.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(LucideIcons.chevron_right, size: 18, color: Colors.white38),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(LucideIcons.shield_check, color: AppTheme.accentEmerald, size: 22),
                      SizedBox(width: 10),
                      Text(
                        'Politique de Confidentialité',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(LucideIcons.x, color: Colors.white70, size: 20),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 20),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  physics: const BouncingScrollPhysics(),
                  children: const [
                    Text(
                      '1. Absence de compte et de pistage publicitaire',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Audio Pulse fonctionne sans création de compte utilisateur, sans identifiant publicitaire et sans SDK d\'analyse comportementale tiers. Aucune donnée personnelle n\'est vendue ni partagée à des courtiers de données.',
                      style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.45),
                    ),
                    SizedBox(height: 16),
                    Text(
                      '2. Stockage local sur votre appareil',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Votre bibliothèque, vos favoris, vos playlists, votre historique de recherche et vos fichiers mis en cache hors-ligne sont enregistrés exclusivement en local dans l\'espace privé de l\'application (SQLite & SharedPreferences).',
                      style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.45),
                    ),
                    SizedBox(height: 16),
                    Text(
                      '3. Requêtes réseau lors des recherches et de la lecture',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Lorsque vous effectuez une recherche musicale ou lancez un flux en streaming, votre appareil se connecte directement aux serveurs de catalogues musicaux et de contenus multimédias (ce qui implique techniquement la transmission standard de votre adresse IP aux serveurs interrogés). Les polices d\'écriture sont intégrées localement sans appel externe.',
                      style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.45),
                    ),
                    SizedBox(height: 16),
                    Text(
                      '4. Suppression intégrale des données',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Vous pouvez à tout moment effacer l\'intégralité de la base locale, de l\'historique et du cache via le bouton « Vider les données de l\'application » dans les Paramètres, ou en désinstallant l\'application.',
                      style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.45),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0x33FFFFFF)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Fermer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showClearDataDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0x22FFFFFF)),
        ),
        title: const Row(
          children: [
            Icon(LucideIcons.trash_2, color: AppTheme.accentRed, size: 20),
            SizedBox(width: 10),
            Text(
              'Vider les données ?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        content: const Text(
          'Cette action va effacer tous les morceaux de votre liste, réinitialiser la file d\'attente et vider le cache en mémoire.',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await context.read<AudioProvider>().clearTracksAndCache();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Données et cache de l\'application vidés'),
                    backgroundColor: const Color(0xFF1E293B),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Vider', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppTheme.textMuted,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF14141A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x1AFFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(
            value: value,
            activeTrackColor: AppTheme.primaryPink,
            activeThumbColor: Colors.white,
            inactiveThumbColor: Colors.white70,
            inactiveTrackColor: Colors.white12,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
