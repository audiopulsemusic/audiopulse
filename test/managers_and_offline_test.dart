import 'package:flutter_test/flutter_test.dart';
import 'package:audiopulse_flutter/models/track.dart';
import 'package:audiopulse_flutter/models/album.dart';
import 'package:audiopulse_flutter/models/artist.dart';
import 'package:audiopulse_flutter/models/app_view.dart';
import 'package:audiopulse_flutter/providers/managers/navigation_manager.dart';

void main() {
  group('NavigationManager Tests', () {
    late NavigationManager navManager;

    setUp(() {
      navManager = NavigationManager();
    });

    test('Initial view is home', () {
      expect(navManager.activeView, AppView.home);
      expect(navManager.activeViewId, 'home');
      expect(navManager.isFullPlayerOpen, isFalse);
      expect(navManager.isQueueOpen, isFalse);
    });

    test('setActiveView updates active view with AppView or String', () {
      navManager.setActiveView(AppView.search);
      expect(navManager.activeView, AppView.search);

      navManager.setActiveView('offline');
      expect(navManager.activeView, AppView.offline);

      navManager.setActiveView('settings');
      expect(navManager.activeView, AppView.settings);
    });

    test('selectArtistAndNavigate sets selected artist and changes view to artist', () {
      final artist = Artist(
        id: 'art_123',
        name: 'Daft Punk',
        avatarUrl: 'https://example.com/avatar.jpg',
        bannerUrl: '',
        bio: 'French electronic music duo',
      );

      navManager.selectArtistAndNavigate(artist);
      expect(navManager.selectedArtist?.name, 'Daft Punk');
      expect(navManager.activeView, AppView.artist);
    });

    test('Overlay modals toggle accurately', () {
      navManager.openFullPlayer();
      expect(navManager.isFullPlayerOpen, isTrue);

      navManager.closeFullPlayer();
      expect(navManager.isFullPlayerOpen, isFalse);

      navManager.toggleQueue();
      expect(navManager.isQueueOpen, isTrue);

      navManager.toggleQueue();
      expect(navManager.isQueueOpen, isFalse);

      navManager.toggleCreatePlaylist();
      expect(navManager.isCreatePlaylistOpen, isTrue);
    });
  });

  group('Model Immutability and CopyWith Tests', () {
    test('Track copyWith produces a distinct immutable instance', () {
      final track1 = Track(
        id: 't1',
        title: 'One More Time',
        artist: 'Daft Punk',
        coverUrl: 'https://example.com/cover.jpg',
        audioUrl: 'yt://t1',
        duration: 320,
      );

      final track2 = track1.copyWith(
        isDownloaded: true,
        localFilePath: '/storage/downloads/daft_punk_one_more_time.m4a',
        isFavorite: true,
      );

      expect(track1.isDownloaded, isFalse);
      expect(track1.localFilePath, isNull);
      expect(track2.isDownloaded, isTrue);
      expect(track2.localFilePath, '/storage/downloads/daft_punk_one_more_time.m4a');
      expect(track2.isFavorite, isTrue);
    });

    test('Artist copyWith preserves immutability', () {
      final artist1 = Artist(
        id: 'a1',
        name: 'Justice',
        avatarUrl: 'https://example.com/justice.jpg',
        bannerUrl: '',
        bio: 'Electronic duo',
      );

      final artist2 = artist1.copyWith(
        isFollowing: true,
        bio: 'Updated bio',
      );

      expect(artist1.isFollowing, isFalse);
      expect(artist2.isFollowing, isTrue);
      expect(artist2.bio, 'Updated bio');
      expect(artist2.name, 'Justice');
    });

    test('Album copyWith retains all properties', () {
      final album1 = Album(
        id: 'alb_1',
        title: 'Discovery',
        artist: 'Daft Punk',
        coverUrl: 'https://example.com/discovery.jpg',
        releaseYear: 2001,
        tracksCount: 14,
        genre: 'Electronic',
        ambientColor: '#F59E0B',
      );

      final album2 = album1.copyWith(tracksCount: 15);
      expect(album1.tracksCount, 14);
      expect(album2.tracksCount, 15);
      expect(album2.title, 'Discovery');
    });
  });
}
