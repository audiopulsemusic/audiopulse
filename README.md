# 🎵 Audio Pulse — Lecteur Musical & Hors-Ligne (Flutter)

[![Latest Release](https://img.shields.io/github/v/release/audiopulsemusic/audiopulse?color=EC4899&label=T%C3%A9l%C3%A9charger%20APK&logo=android)](https://github.com/audiopulsemusic/audiopulse/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-8B5CF6.svg)](LICENSE)

Application musicale multiplateforme (**Android, iOS, macOS, Linux, Windows**) écrite en **Dart / Flutter**, avec écoute en arrière-plan, mode hors-ligne complet, compatibilité **Android Auto / Apple CarPlay**, import de file d'attente et interface Cyber Glassmorphism.

---

## 📥 Téléchargement & Installation (Android / Obtainium)

- **[Télécharger la dernière version (`.apk`) sur GitHub Releases](https://github.com/audiopulsemusic/audiopulse/releases/latest)** :
  - **`app-arm64-v8a-release.apk`** *(Recommandé — 99 % des smartphones Android récents)*
  - **`app-armeabi-v7a-release.apk`** *(Anciens appareils Android 32 bits)*
  - **`app-x86_64-release.apk`** *(Chromebooks & Émulateurs)*
- **Mise à jour automatique via [Obtainium](https://github.com/ImranR98/Obtainium)** : ajoutez simplement l'URL `https://github.com/audiopulsemusic/audiopulse`.

---

## 🚀 Fonctionnalités Clés

- **Moteur Audio Hi-Fi** : Lecture en streaming 24-bit, seek précis, volume, modes boucle (*off, all, one*), lecture aléatoire (*shuffle*), et synchronisation de file d'attente (*queue*).
- **Design System Cyber & Glassmorphism** :
  - Palette sombre `#06080C` avec accents néons (`#EC4899`, `#8B5CF6`, `#10B981`).
  - Effets de flou translucides (*glass panels*), ombres portées douces et halos dynamiques adaptés à la couleur d'ambiance de chaque morceau.
- **Spectre Audio FFT en Temps Réel** : Visualiseur de fréquences 16 bandes animé dans le lecteur plein écran et dans le mini player.
- **Studio Égaliseur EQ 10-Band** : Sliders de fréquences (60Hz, 230Hz, 910Hz, 4kHz, 14kHz), amplification des basses (*Bass Boost*) et bascule *Son Spatial 3D*.
- **Préréglages Acoustiques** : *Flat, Bass Boost, Vocal Clarity, Electronic, Rock, Club Rave*.
- **Vues & Navigation** :
  - **Accueil (`HomeView`)** : Recherche en direct, filtres par genre, liste des morceaux avec lecture/téléchargement, carrousels d'albums, artistes et playlists.
  - **Explorer (`ExploreView`)** : Canaux musicaux thématiques en tuiles dégradées.
  - **Recherche Instantanée (`SearchView`)** : Recherche multi-entités (morceaux, albums, artistes).
  - **Bibliothèque Utilisateur (`LibraryView`)** : Profil Hi-Fi, statut d'abonnement, gestion et création de playlists.
  - **Page Artiste (`ArtistView`)** : Hero banner grand format avec biographie et discographie.
  - **Page Playlist (`PlaylistView`)** : En-tête avec bouton de lecture globale et table des titres.
- **Inspecteur Backend API (`ApiDevModal`)** : Test de connectivité en direct vers API REST externe avec basculement automatique sur le moteur local *Mock Engine*.

---

## 📱 Lancement de l'Application

### Prérequis
- Flutter SDK (v3.38+ recommandé)
- Dart SDK (v3.10+)

### Commandes

1. Se placer dans le dossier Flutter :
```bash
cd audiopulse_flutter
```

2. Installer les dépendances :
```bash
flutter pub get
```

3. Lancer l'application :
- **Sur navigateur Chrome (Web) :**
  ```bash
  flutter run -d chrome
  ```
- **Sur macOS (Desktop natif) :**
  ```bash
  flutter run -d macos
  ```
- **Sur simulateur iOS :**
  ```bash
  flutter run -d ios
  ```
- **Sur émulateur Android :**
  ```bash
  flutter run -d android
  ```

4. Lancer les tests unitaires et widget :
```bash
flutter test
```

5. Vérifier la conformité du code :
```bash
flutter analyze
```

---

## 📂 Architecture du Projet

```
audiopulse_flutter/
├── lib/
│   ├── data/
│   │   └── mock_data.dart            # Données locales de test (titres, artistes, playlists)
│   ├── models/
│   │   ├── album.dart
│   │   ├── api_config.dart
│   │   ├── artist.dart
│   │   ├── equalizer_state.dart
│   │   ├── playlist.dart
│   │   ├── track.dart
│   │   └── user_profile.dart
│   ├── providers/
│   │   └── audio_provider.dart       # Gestionnaire d'état global réactif
│   ├── services/
│   │   ├── api_service.dart          # Client API REST / Mock
│   │   └── audio_player_service.dart # Pilote du lecteur audio just_audio
│   ├── theme/
│   │   └── app_theme.dart            # Tokens de couleurs, thème sombre et glassmorphism
│   ├── views/
│   │   ├── artist_view.dart
│   │   ├── explore_view.dart
│   │   ├── home_view.dart
│   │   ├── library_view.dart
│   │   ├── playlist_view.dart
│   │   └── search_view.dart
│   ├── widgets/
│   │   ├── api_dev_modal.dart
│   │   ├── app_network_image.dart
│   │   ├── bottom_nav.dart
│   │   ├── create_playlist_modal.dart
│   │   ├── equalizer_modal.dart
│   │   ├── fullscreen_player.dart
│   │   ├── header_bar.dart
│   │   ├── mini_player.dart
│   │   ├── queue_drawer.dart
│   │   └── sidebar_nav.dart
│   └── main.dart                     # Point d'entrée de l'application
├── test/
│   ├── audio_provider_test.dart      # Tests unitaires de la logique métier
│   └── widget_test.dart              # Test d'intégration de l'interface
└── pubspec.yaml                      # Configuration et dépendances Flutter
```
