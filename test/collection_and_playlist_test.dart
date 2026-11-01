import 'package:flutter_test/flutter_test.dart';
import 'package:audiopulse_flutter/models/album.dart';
import 'package:audiopulse_flutter/models/collection_type.dart';
import 'package:audiopulse_flutter/models/track.dart';
import 'package:audiopulse_flutter/services/database_service.dart';

void main() {
  test('Album infers collection type from legacy genre and round-trips wire type', () {
    final playlist = Album.fromJson({
      'id': 'legacy-pl',
      'title': 'Mix',
      'artist': 'Artist',
      'coverUrl': '',
      'releaseYear': 2025,
      'tracksCount': 2,
      'genre': 'YouTube Playlist',
      'ambientColor': '#000000',
    });
    expect(playlist.collectionType, CollectionType.playlist);
    expect(playlist.toJson()['collectionType'], 'playlist');

    final ep = Album.fromJson({
      'id': 'ep',
      'title': 'EP',
      'artist': 'Artist',
      'genre': 'EP',
      'coverUrl': '',
      'releaseYear': 2025,
      'tracksCount': 3,
      'ambientColor': '#000000',
    });
    expect(ep.collectionType, CollectionType.ep);
  });

  test('SQLite persists playlists and prevents duplicate playlist tracks', () async {
    final service = DatabaseService.instance;
    await service.database;

    final playlist = await service.createPlaylist('Persistent', 'Description');
    final track = Track(
      id: 'playlist_track_${DateTime.now().microsecondsSinceEpoch}',
      title: 'Track',
      artist: 'Artist',
      coverUrl: '',
      audioUrl: 'yt://playlist',
      duration: 120,
    );
    expect(await service.addTrackToPlaylist(playlist.id, track), isTrue);
    expect(await service.addTrackToPlaylist(playlist.id, track), isFalse);

    final playlists = await service.getAllPlaylists();
    final saved = playlists.firstWhere((item) => item.id == playlist.id);
    expect(saved.tracks.map((item) => item.id), [track.id]);
  });
}
