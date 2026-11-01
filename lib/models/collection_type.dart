enum CollectionType {
  album,
  ep,
  single,
  playlist,
  compilation,
  release,
  unknown;

  static CollectionType fromWire(Object? value, {String? legacyGenre}) {
    final raw = (value ?? legacyGenre)?.toString().trim().toLowerCase() ?? '';
    if (raw.contains('playlist') || raw.contains('sélection')) return playlist;
    if (raw == 'single' || raw.contains('single')) return single;
    if (raw == 'ep' || raw.contains(' ep')) return ep;
    if (raw.contains('compilation')) return compilation;
    if (raw.contains('sortie officielle') || raw == 'release') return release;
    if (raw.contains('album')) return album;
    return unknown;
  }

  String get wireName => name;
}
