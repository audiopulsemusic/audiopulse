import 'package:flutter_test/flutter_test.dart';
import 'package:audiopulse_flutter/services/audio_fetch_service.dart';
import 'package:audiopulse_flutter/models/track.dart';

void main() {
  group('AudioFetchService Structured Album Metadata Tests', () {
    final fetchService = AudioFetchService.instance;

    test('fetchAlbumDetailsAndTracks works with structured metadata', () async {
      final track = Track(
        id: 'l6wxQqbZGFM',
        title: 'Too Many',
        artist: 'Tyga',
        album: 'NSFW',
        albumId: 'MPREb_4EHYZXS7xtT',
        duration: 145,
        coverUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4',
        audioUrl: 'yt://l6wxQqbZGFM',
        genre: 'Album',
        ambientColor: '#EC4899',
      );

      final albumDetails = await fetchService.fetchAlbumDetailsAndTracks(track);
      expect(albumDetails.albumName, isNotNull);
      expect(albumDetails.tracks, isNotEmpty);
    });
  });
}
