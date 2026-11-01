import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../theme/app_theme.dart';

class AppNetworkImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final double borderRadius;
  final BoxFit fit;
  final Widget? fallbackIcon;

  const AppNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.borderRadius = 8.0,
    this.fit = BoxFit.cover,
    this.fallbackIcon,
  });

  Widget _buildFallback() {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFF131720), // Fond très sombre pour le côté fantôme
      child: Center(
        child: fallbackIcon ??
            const Icon(
              LucideIcons.music,
              color: Color(0x40FFFFFF), // Blanc très transparent (mode fantôme)
              size: 24,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cleanUrl = imageUrl.trim();

    if (cleanUrl.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: _buildFallback(),
      );
    }

    // Détermination de la taille de cache mémoire pour éviter le décodage plein format
    final int? calculatedCacheWidth = width != null ? (width! * 2.0).round().clamp(64, 1024) : null;
    final int? calculatedCacheHeight = height != null ? (height! * 2.0).round().clamp(64, 1024) : null;

    // Gestion des chemins de fichiers locaux
    if (cleanUrl.startsWith('/') || cleanUrl.startsWith('file://')) {
      final path = cleanUrl.startsWith('file://') ? cleanUrl.replaceFirst('file://', '') : cleanUrl;
      final file = File(path);
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: file.existsSync()
            ? Image.file(
                file,
                width: width,
                height: height,
                fit: fit,
                cacheWidth: calculatedCacheWidth,
                cacheHeight: calculatedCacheHeight,
                errorBuilder: (_, _, _) => _buildFallback(),
              )
            : _buildFallback(),
      );
    }

    // Normalisation des URLs Google User Content vers un ratio 1:1 HD carré
    String effectiveUrl = cleanUrl;
    if (cleanUrl.contains('maxresdefault.jpg')) {
      effectiveUrl = cleanUrl.replaceFirst('maxresdefault.jpg', 'hqdefault.jpg');
    } else if ((cleanUrl.contains('googleusercontent.com') || cleanUrl.contains('ggpht.com')) && cleanUrl.contains('=')) {
      final base = cleanUrl.split('=')[0];
      effectiveUrl = '$base=w544-h544-l90-rj';
    }

    // Détection des vignettes YouTube 4:3 letterboxées (bandes noires en haut/bas)
    final isYoutubeLetterboxed = fit == BoxFit.cover &&
        (effectiveUrl.contains('i.ytimg.com') || effectiveUrl.contains('img.youtube.com')) &&
        (effectiveUrl.contains('hqdefault.jpg') || effectiveUrl.contains('mqdefault.jpg') || effectiveUrl.contains('default.jpg'));

    Widget imageWidget = Image.network(
      effectiveUrl,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: calculatedCacheWidth,
      cacheHeight: calculatedCacheHeight,
      errorBuilder: (context, error, stackTrace) => _buildFallback(),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: width,
          height: height,
          color: const Color(0xFF0F172A),
        );
      },
    );

    // Zoom 1.334x centré pour éliminer les bandes noires horizontales et obtenir un carré 1:1 parfait
    if (isYoutubeLetterboxed) {
      imageWidget = Transform.scale(
        scale: 1.334,
        child: imageWidget,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: imageWidget,
    );
  }
}
