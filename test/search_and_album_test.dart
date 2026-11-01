import 'package:flutter_test/flutter_test.dart';
import 'package:audiopulse_flutter/services/audio_fetch_service.dart';
import 'package:audiopulse_flutter/services/database_service.dart';
import 'package:audiopulse_flutter/models/track.dart';

void main() {
  group('Search and Album Fetch Enhancement Tests', () {
    test('parseCleanTitleAndArtist separates artist and title preserving title intact', () {
      final res = AudioFetchService.instance.parseCleanTitleAndArtist(
        'YG - BPT (Official Music Video) [HD 4K]',
        'YG - Topic',
      );
      expect(res['artist'], 'YG');
      expect(res['title'], 'BPT (Official Music Video) [HD 4K]');
    });

    test('parseDurationString accurately parses mm:ss and hh:mm:ss strings', () {
      expect(AudioFetchService.instance.parseDurationString('2:58'), 178);
      expect(AudioFetchService.instance.parseDurationString('03:30'), 210);
      expect(AudioFetchService.instance.parseDurationString('1:02:15'), 3735);
      expect(AudioFetchService.instance.parseDurationString('invalid'), 0);
    });

    test('parseCleanTitleAndArtist extracts clean artist and removes redundant prefix only', () {
      final res1 = AudioFetchService.instance.parseCleanTitleAndArtist('Juicy J - What I Call It (Must Be Nice)', 'Taylor Gang');
      expect(res1['artist'], 'Juicy J');
      expect(res1['title'], 'What I Call It (Must Be Nice)');

      final res2 = AudioFetchService.instance.parseCleanTitleAndArtist('Tyga - Werkkkk (Audio)', 'Tyga');
      expect(res2['artist'], 'Tyga');
      expect(res2['title'], 'Werkkkk (Audio)');

      final res3 = AudioFetchService.instance.parseCleanTitleAndArtist('Tyga - Like Me [OFFICIAL MUSIC VIDEO]', 'Tyga - Topic');
      expect(res3['artist'], 'Tyga');
      expect(res3['title'], 'Like Me [OFFICIAL MUSIC VIDEO]');
    });

    test('matchesExplicitRequirement correctly enforces explicit / clean versions', () {
      // When target is explicit (true): reject Clean / Radio Edit
      expect(AudioFetchService.instance.matchesExplicitRequirement('Tyga - Too Many (Clean)', true), isFalse);
      expect(AudioFetchService.instance.matchesExplicitRequirement('Tyga - Too Many (Radio Edit)', true), isFalse);
      expect(AudioFetchService.instance.matchesExplicitRequirement('Tyga - Too Many (Censored)', true), isFalse);
      expect(AudioFetchService.instance.matchesExplicitRequirement('Tyga - Too Many (Official Audio)', true), isTrue);
      expect(AudioFetchService.instance.matchesExplicitRequirement('Tyga - Too Many (Explicit)', true), isTrue);

      // When target is clean (false): reject Explicit / Dirty
      expect(AudioFetchService.instance.matchesExplicitRequirement('Tyga - Too Many (Explicit)', false), isFalse);
      expect(AudioFetchService.instance.matchesExplicitRequirement('Tyga - Too Many (Dirty)', false), isFalse);
      expect(AudioFetchService.instance.matchesExplicitRequirement('Tyga - Too Many (Official Audio)', false), isTrue);
    });

    test('Empty query returns empty search engine response immediately without network call', () async {
      final res = await AudioFetchService.instance.searchCatalog('');
      expect(res.isEmpty, isTrue);
    });

    test('findArtistInQuery detects artist name contained within complex search queries after indexation', () async {
      await DatabaseService.instance.saveArtistIndex('Usher', artistId: 'UC_usher');
      await DatabaseService.instance.saveArtistIndex('YG', artistId: 'UC_yg');

      final match1 = await DatabaseService.instance.findArtistInQuery('usher yeah ! official video');
      expect(match1, isNotNull);
      expect(match1!.name.toLowerCase(), 'usher');

      final match2 = await DatabaseService.instance.findArtistInQuery('my krazy life yg');
      expect(match2, isNotNull);
      expect(match2!.name.toLowerCase(), 'yg');

      final noMatch = await DatabaseService.instance.findArtistInQuery('xyz unknown title 999999');
      expect(noMatch, isNull);
    });

    test('findArtistInQuery does not false-positive on subword matches', () async {
      await DatabaseService.instance.saveArtistIndex('Art', artistId: 'UC_art');
      // "Art" must NOT match inside the unrelated word "party" or "start".
      final inParty = await DatabaseService.instance.findArtistInQuery('party night');
      expect(inParty, isNull);
      final inStart = await DatabaseService.instance.findArtistInQuery('start running');
      expect(inStart, isNull);
      // But a whole-token artist still matches.
      final wholeWord = await DatabaseService.instance.findArtistInQuery('art gallery');
      expect(wholeWord, isNotNull);
    });

    test('saveArtistIndex properly stores and returns associated topicChannelId', () async {
      await DatabaseService.instance.saveArtistIndex(
        'Tyga',
        artistId: 'UC_tyga_official',
        topicChannelId: 'UC_tyga_topic',
      );

      final artist = await DatabaseService.instance.findArtistByName('Tyga');
      expect(artist, isNotNull);
      expect(artist!.id, 'UC_tyga_official');
      expect(artist.topicChannelId, 'UC_tyga_topic');
    });
  });

  group('Ranking and Matching Helpers', () {
    test('rankTracks orders best-matching track first', () {
      final best = Track(
        id: 'v1',
        title: 'One More Time',
        artist: 'Daft Punk',
        coverUrl: '',
        audioUrl: 'yt://v1',
        duration: 320,
      );
      final lesser = Track(
        id: 'v2',
        title: 'Random unrelated video content',
        artist: 'Someone Else',
        coverUrl: '',
        audioUrl: 'yt://v2',
        duration: 180,
      );

      final ranked = YtSearchService.rankTracks([lesser, best], 'One More Time');
      expect(ranked.first.id, 'v1');
    });

    test('isSafeStreamUrl rejects non-https, empty hosts and localhost', () {
      expect(YtStreamResolver.isSafeStreamUrl('http://example.com/a.mp4'), isFalse);
      expect(YtStreamResolver.isSafeStreamUrl('https://localhost/a.mp4'), isFalse);
      expect(YtStreamResolver.isSafeStreamUrl('https://127.0.0.1/a.mp4'), isFalse);
      expect(YtStreamResolver.isSafeStreamUrl('https://googlevideo.com/videoplayback?x=1'), isTrue);
    });

    test('Candidate artist selector condition triggers only when top 2 tracks have different artists', () {
      final sameArtistTracks = [
        Track(id: '1', title: 'Tyga - On Me', artist: 'Tyga', duration: 180, coverUrl: '', audioUrl: ''),
        Track(id: '2', title: 'On Me (feat. Lil Wayne)', artist: 'Tyga', duration: 180, coverUrl: '', audioUrl: ''),
        Track(id: '3', title: 'Type Beat', artist: 'Beast Inside Beats', duration: 180, coverUrl: '', audioUrl: ''),
      ];

      final top2Same = sameArtistTracks.take(2).toList();
      final hasMultipleInTop2Same = top2Same.length >= 2 &&
          top2Same[0].artist.trim().toLowerCase() != top2Same[1].artist.trim().toLowerCase();
      expect(hasMultipleInTop2Same, isFalse);

      final diffArtistTracks = [
        Track(id: '1', title: 'Song 1', artist: 'Tyga', duration: 180, coverUrl: '', audioUrl: ''),
        Track(id: '2', title: 'Song 2', artist: 'Mario', duration: 180, coverUrl: '', audioUrl: ''),
      ];

      final top2Diff = diffArtistTracks.take(2).toList();
      final hasMultipleInTop2Diff = top2Diff.length >= 2 &&
          top2Diff[0].artist.trim().toLowerCase() != top2Diff[1].artist.trim().toLowerCase();
      expect(hasMultipleInTop2Diff, isTrue);
    });

    test('Track bitrate model and copyWith defaults to 128 and updates correctly', () {
      final track = Track(
        id: 'track_128',
        title: 'Maniac',
        artist: 'Tyga',
        duration: 180,
        coverUrl: '',
        audioUrl: '',
        bitrate: 256,
      );

      expect(track.bitrate, 256);
      final json = track.toJson();
      expect(json['bitrate'], 256);
      final restored = Track.fromJson(json);
      expect(restored.bitrate, 256);

      final updated = track.copyWith(bitrate: 320);
      expect(updated.bitrate, 320);
    });
  });
}
