import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../services/fetch/apple_music_service.dart';
import '../services/library_sync_service.dart';
import '../theme/app_theme.dart';

enum ImportStep { intro, scanning, confirm, importing, success }

class AppleMusicImportWizard extends StatefulWidget {
  const AppleMusicImportWizard({super.key});

  /// Méthode statique pour afficher le Wizard facilement depuis n'importe où
  static void show(BuildContext context) {
    if (kIsWeb || (!Platform.isMacOS && !Platform.isIOS)) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AppleMusicImportWizard(),
    );
  }

  @override
  State<AppleMusicImportWizard> createState() => _AppleMusicImportWizardState();
}

class _AppleMusicImportWizardState extends State<AppleMusicImportWizard> {
  ImportStep _currentStep = ImportStep.intro;
  List<String> _releases = [];
  String _errorMessage = '';
  bool _isPaused = false;

  Future<void> _startScan() async {
    setState(() {
      _currentStep = ImportStep.scanning;
      _errorMessage = '';
    });

    final appleService = AppleMusicService();
    final releases = await appleService.getLocalReleases();

    if (!mounted) return;

    if (releases.isEmpty) {
      setState(() {
        _errorMessage = "Aucune sortie trouvée ou permission refusée.";
        _currentStep = ImportStep.intro;
      });
    } else {
      setState(() {
        _releases = releases;
        _currentStep = ImportStep.confirm;
      });
    }
  }

  int _currentIndex = 0;
  String _currentArtist = '';

  Future<void> _startImport() async {
    setState(() {
      _currentStep = ImportStep.importing;
      _currentIndex = 0;
      _currentArtist = _releases.firstOrNull ?? '';
      _isPaused = false;
    });

    // Appel du véritable moteur de synchronisation en arrière-plan
    await LibrarySyncService.instance.syncReleases(
      _releases,
      onProgress: (index, total, itemName) {
        if (mounted) {
          setState(() {
            _currentIndex = index;
            _currentArtist = itemName;
          });
        }
      },
    );

    if (!mounted) return;
    setState(() {
      _currentStep = ImportStep.success;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0D14),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x33FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 30,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _buildCurrentStep(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case ImportStep.intro:
        return _buildIntroStep();
      case ImportStep.scanning:
        return _buildScanningStep();
      case ImportStep.confirm:
        return _buildConfirmStep();
      case ImportStep.importing:
        return _buildImportingStep();
      case ImportStep.success:
        return _buildSuccessStep();
    }
  }

  Widget _buildIntroStep() {
    return Column(
      key: const ValueKey('intro'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.primaryPink.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(LucideIcons.music, size: 40, color: AppTheme.primaryPink),
        ),
        const SizedBox(height: 24),
        const Text(
          "Retrouvez votre musique",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          "Importez instantanément vos artistes favoris depuis la bibliothèque de votre appareil vers AudioPulse.",
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
          textAlign: TextAlign.center,
        ),
        if (_errorMessage.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            _errorMessage,
            style: const TextStyle(fontSize: 13, color: Colors.redAccent),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _startScan,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryPink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: const Text("Analyser ma bibliothèque", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Plus tard", style: TextStyle(color: AppTheme.textMuted)),
        )
      ],
    );
  }

  Widget _buildScanningStep() {
    return Column(
      key: const ValueKey('scanning'),
      mainAxisSize: MainAxisSize.min,
      children: const [
        SizedBox(height: 40),
        CircularProgressIndicator(color: AppTheme.primaryPink),
        SizedBox(height: 24),
        Text(
          "Analyse en cours...",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        SizedBox(height: 8),
        Text(
          "Nous cherchons vos artistes locaux.",
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        SizedBox(height: 40),
      ],
    );
  }

  Widget _buildConfirmStep() {
    return Column(
      key: const ValueKey('confirm'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.cyan.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(LucideIcons.users, size: 40, color: Colors.cyanAccent),
        ),
        const SizedBox(height: 24),
        Text(
          "${_releases.length} morceaux trouvés !",
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          "Voulez-vous lancer l'importation de ces catalogues via notre moteur de recherche unifié ?",
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _startImport,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyan.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: const Text("Lancer l'importation", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Annuler", style: TextStyle(color: AppTheme.textMuted)),
        )
      ],
    );
  }

  Widget _buildImportingStep() {
    final double progress = _releases.isEmpty ? 0 : (_currentIndex / _releases.length);
    final int percent = (progress * 100).toInt();

    return Column(
      key: const ValueKey('importing'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 30),
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                value: progress > 0 ? progress : null,
                strokeWidth: 6,
                backgroundColor: Colors.cyan.withOpacity(0.2),
                color: _isPaused ? Colors.orangeAccent : Colors.cyanAccent,
              ),
            ),
            Text(
              "$percent%",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            )
          ],
        ),
        const SizedBox(height: 24),
        Text(
          _isPaused ? "Synchronisation en pause" : "Synchronisation en cours...",
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 12),
        Text(
          "Association de la sortie :\n$_currentArtist",
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          "($_currentIndex sur ${_releases.length} albums)",
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isPaused = !_isPaused;
                });
                if (_isPaused) {
                  LibrarySyncService.instance.pause();
                } else {
                  LibrarySyncService.instance.resume();
                }
              },
              icon: Icon(_isPaused ? LucideIcons.play : LucideIcons.pause, size: 16),
              label: Text(_isPaused ? "Reprendre" : "Pause"),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isPaused ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                foregroundColor: _isPaused ? Colors.greenAccent : Colors.orangeAccent,
                elevation: 0,
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: () {
                LibrarySyncService.instance.cancel();
                setState(() {
                  _currentStep = ImportStep.success;
                });
              },
              icon: const Icon(LucideIcons.square, size: 16),
              label: const Text("Arrêter"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.withOpacity(0.2),
                foregroundColor: Colors.redAccent,
                elevation: 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSuccessStep() {
    return Column(
      key: const ValueKey('success'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(LucideIcons.check, size: 40, color: Colors.greenAccent),
        ),
        const SizedBox(height: 24),
        const Text(
          "Importation réussie !",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          "Tous vos artistes sont maintenant disponibles dans votre bibliothèque AudioPulse.",
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white10,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: const Text("Fermer", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}

