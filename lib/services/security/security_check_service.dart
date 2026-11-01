import "dart:io";
import "package:flutter/foundation.dart";

/// Lightweight, non-blocking environment integrity and root/jailbreak diagnostics.
class SecurityCheckService {
  const SecurityCheckService._();

  static Future<bool> isCompromisedDevice() async {
    if (kIsWeb) return false;
    try {
      if (Platform.isAndroid) {
        return _checkAndroidRoot();
      } else if (Platform.isIOS) {
        return _checkIOSJailbreak();
      }
    } catch (e) {
      if (kDebugMode) debugPrint("[SecurityCheck] Diagnostic error: $e");
    }
    return false;
  }

  static bool _checkAndroidRoot() {
    const rootPaths = [
      "/system/app/Superuser.apk",
      "/sbin/su",
      "/system/bin/su",
      "/system/xbin/su",
      "/data/local/xbin/su",
      "/data/local/bin/su",
      "/system/sd/xbin/su",
      "/system/bin/failsafe/su",
      "/data/local/su",
    ];

    for (final path in rootPaths) {
      if (File(path).existsSync()) return true;
    }
    return false;
  }

  static bool _checkIOSJailbreak() {
    const jailbreakPaths = [
      "/Applications/Cydia.app",
      "/Library/MobileSubstrate/MobileSubstrate.dylib",
      "/bin/bash",
      "/usr/sbin/sshd",
      "/etc/apt",
      "/private/var/lib/apt/",
    ];

    for (final path in jailbreakPaths) {
      if (File(path).existsSync()) return true;
    }
    return false;
  }

  /// Run diagnostics non-blockingly at startup
  static void runStartupDiagnostics() {
    isCompromisedDevice().then((compromised) {
      if (compromised && kDebugMode) {
        debugPrint("[SecurityCheck] ⚠️ Avertissement : environnement rooté ou jailbreaké détecté.");
      }
    }).catchError((_) {});
  }
}
