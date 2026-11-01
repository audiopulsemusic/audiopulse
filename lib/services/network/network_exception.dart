/// Typed business errors for all network / stream operations.
///
/// These allow the UI and playback pipeline to distinguish "no result" from
/// real failures (timeout, service down, invalid response, blocked content,
/// security violation) instead of collapsing every failure into an empty list.
sealed class NetworkException implements Exception {
  const NetworkException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The request did not complete within the configured timeout.
class NetworkTimeoutException extends NetworkException {
  const NetworkTimeoutException([super.message = 'La requête a expiré.']);
}

/// The network is unreachable (no connection, DNS failure, host down).
class NetworkUnavailableException extends NetworkException {
  const NetworkUnavailableException([super.message = 'Service injoignable.']);
}

/// A response was received but is unusable: bad status, malformed JSON, or an
/// unexpected structure.
class InvalidResponseException extends NetworkException {
  const InvalidResponseException([super.message = 'Réponse invalide.']);

  /// Creates an exception for a non-success status code.
  factory InvalidResponseException.status(int statusCode) {
    final reason = switch (statusCode) {
      >= 500 && <= 599 => 'Erreur serveur ($statusCode).',
      404 => 'Contenu introuvable ($statusCode).',
      _ => 'Réponse inattendue ($statusCode).',
    };
    return InvalidResponseException(reason);
  }
}

/// The requested content was removed, region-locked, or no longer available.
class ContentUnavailableException extends NetworkException {
  const ContentUnavailableException([super.message = 'Contenu indisponible.']);
}

/// The audio stream could not be resolved from the provided track.
class StreamResolutionException extends NetworkException {
  const StreamResolutionException([super.message = 'Résolution du flux impossible.']);
}

/// The URL/host failed security validation (non-HTTPS, private/local/loopback
/// address, banned host, unexpected redirection, oversized response).
class SecurityValidationException extends NetworkException {
  const SecurityValidationException([super.message = 'URL refusée par validation de sécurité.']);
}

/// A download failed or was aborted (size limit, network failure, bad content).
class DownloadException extends NetworkException {
  const DownloadException([super.message = 'Téléchargement impossible.']);
}