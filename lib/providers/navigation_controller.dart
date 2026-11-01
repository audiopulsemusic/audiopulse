import 'package:flutter/foundation.dart';

import '../models/album.dart';
import '../models/app_view.dart';
import '../models/artist.dart';
import '../models/playlist.dart';

class NavigationController extends ChangeNotifier {
  AppView _activeView = AppView.home;
  Artist? _selectedArtist;
  Album? _selectedAlbum;
  Playlist? _selectedPlaylist;
  bool _fullPlayerOpen = false;
  bool _queueOpen = false;

  AppView get activeView => _activeView;
  Artist? get selectedArtist => _selectedArtist;
  Album? get selectedAlbum => _selectedAlbum;
  Playlist? get selectedPlaylist => _selectedPlaylist;
  bool get isFullPlayerOpen => _fullPlayerOpen;
  bool get isQueueOpen => _queueOpen;

  void setView(AppView view) {
    if (_activeView == view) return;
    _activeView = view;
    notifyListeners();
  }

  void selectArtist(Artist artist) {
    _selectedArtist = artist;
    _activeView = AppView.artist;
    notifyListeners();
  }

  void selectAlbum(Album album) {
    _selectedAlbum = album;
    _activeView = AppView.album;
    notifyListeners();
  }

  void selectPlaylist(Playlist playlist) {
    _selectedPlaylist = playlist;
    _activeView = AppView.playlist;
    notifyListeners();
  }

  void setFullPlayerOpen(bool value) {
    _fullPlayerOpen = value;
    notifyListeners();
  }

  void setQueueOpen(bool value) {
    _queueOpen = value;
    notifyListeners();
  }
}
