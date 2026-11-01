package com.audiopulse.audiopulse_flutter

import android.app.SearchManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.media.MediaMetadata
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Bundle
import android.provider.MediaStore
import android.provider.Settings
import androidx.annotation.NonNull
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity: AudioServiceActivity() {
    private val APPLE_CHANNEL = "com.audiopulse/apple_music"
    private val SCRAPER_METHOD_CHANNEL = "com.audiopulse/media_scraper"
    private val SCRAPER_EVENT_CHANNEL = "com.audiopulse/media_scraper_events"
    private val VOICE_SEARCH_CHANNEL = "com.audiopulse/voice_search"

    private var voiceChannel: MethodChannel? = null
    private var pendingVoiceSearch: Map<String, Any?>? = null

    private var eventSink: EventChannel.EventSink? = null
    private var scraperJob: Job? = null
    private val coroutineScope = CoroutineScope(Dispatchers.Main + Job())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureVoiceSearchIntent(intent, dispatchLive = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureVoiceSearchIntent(intent, dispatchLive = true)
    }

    private fun captureVoiceSearchIntent(intent: Intent?, dispatchLive: Boolean) {
        if (intent?.action != MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH) return
        val query = intent.getStringExtra(SearchManager.QUERY) ?: ""
        val extrasMap = mutableMapOf<String, String>()
        val bundle = intent.extras
        if (bundle != null) {
            val knownKeys = listOf(
                MediaStore.EXTRA_MEDIA_FOCUS,
                MediaStore.EXTRA_MEDIA_ARTIST,
                MediaStore.EXTRA_MEDIA_ALBUM,
                MediaStore.EXTRA_MEDIA_TITLE,
                // Clé historique toujours émise par Google Assistant pour les playlists
                "android.intent.extra.playlist",
                MediaStore.EXTRA_MEDIA_GENRE,
            )
            for (key in knownKeys) {
                val value = bundle.getString(key)
                if (!value.isNullOrBlank()) {
                    extrasMap[key] = value
                }
            }
        }
        val payload = mapOf<String, Any?>(
            "query" to query,
            "extras" to extrasMap,
        )
        // Neutralise l'action pour éviter un re-déclenchement lors d'une rotation d'écran
        intent.action = Intent.ACTION_MAIN

        val channel = voiceChannel
        if (dispatchLive && channel != null) {
            channel.invokeMethod("onVoiceSearch", payload)
        } else {
            pendingVoiceSearch = payload
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Pont Google Assistant / Android Auto (MEDIA_PLAY_FROM_SEARCH)
        voiceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOICE_SEARCH_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "consumePendingVoiceSearch") {
                    val pending = pendingVoiceSearch
                    pendingVoiceSearch = null
                    result.success(pending)
                } else {
                    result.notImplemented()
                }
            }
        }

        // Apple Music (NOT SUPPORTED ON ANDROID)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APPLE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getLocalReleases") {
                result.error("NOT_SUPPORTED", "L'importation Apple Music directe n'est disponible que sur iOS et macOS.", null)
            } else {
                result.notImplemented()
            }
        }

        // MethodChannel pour Permissions & Lancement du scan
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCRAPER_METHOD_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "scanActivePlayers") {
                if (!isNotificationServiceEnabled()) {
                    result.error("PERMISSION_DENIED", "Accès aux notifications requis", null)
                } else {
                    // Start scraping in background
                    startScraping()
                    result.success(null)
                }
            } else if (call.method == "requestPermission") {
                startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                result.success(true)
            } else if (call.method == "openAppSettings") {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", packageName, null)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                result.success(true)
            } else if (call.method == "checkPermission") {
                result.success(isNotificationServiceEnabled())
            } else if (call.method == "setMaxBrightness") {
                val layoutParams = window.attributes
                layoutParams.screenBrightness = 1.0f
                window.attributes = layoutParams
                result.success(true)
            } else if (call.method == "resetBrightness") {
                val layoutParams = window.attributes
                layoutParams.screenBrightness = android.view.WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                window.attributes = layoutParams
                result.success(true)
            } else {
                result.notImplemented()
            }
        }

        // EventChannel pour le streaming des morceaux capturés
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SCRAPER_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    scraperJob?.cancel()
                }
            }
        )
    }

    private fun startScraping() {
        scraperJob?.cancel()
        scraperJob = coroutineScope.launch {
            try {
                val mediaSessionManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
                val componentName = ComponentName(this@MainActivity, NotificationScraperService::class.java)
                val controllers = mediaSessionManager.getActiveSessions(componentName)

                if (controllers.isEmpty()) {
                    eventSink?.success("LOG::Aucun lecteur actif trouvé.")
                    eventSink?.endOfStream()
                    return@launch
                }

                // On prend le premier lecteur actif qui joue ou est en pause (ex: Spotify)
                val controller = controllers.firstOrNull { it.packageName != packageName } ?: controllers.first()
                eventSink?.success("LOG::Début de l'aspiration sur " + controller.packageName)

                val results = mutableSetOf<String>()
                var index = 0

                while (isActive) {
                    val metadata = controller.metadata
                    if (metadata == null) {
                        eventSink?.success("LOG::Pas de métadonnées.")
                        break
                    }

                    val title = metadata.getString(MediaMetadata.METADATA_KEY_TITLE) ?: "Inconnu"
                    val artist = metadata.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: "Inconnu"
                    val album = metadata.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: "Single"
                    val duration = metadata.getLong(MediaMetadata.METADATA_KEY_DURATION) / 1000 // ms to s

                    val trackStr = "$title|||$artist|||$album|||$duration"

                    // Si le morceau a déjà été capturé, la file d'attente a bouclé ou est terminée
                    if (!results.add(trackStr)) {
                        eventSink?.success("LOG::Fin de la file d'attente détectée ($index morceaux importés).")
                        break
                    }

                    index++
                    eventSink?.success("TRACK::$trackStr")

                    // Envoi de la commande Suivant
                    eventSink?.success("LOG::Morceau [$index] : $title. Commande 'Suivant' envoyée...")
                    controller.transportControls.skipToNext()

                    // Attendre que la musique change (max 2.0s)
                    var waited = 0
                    var trackChanged = false
                    while (waited < 20 && isActive) {
                        delay(100)
                        val newMetadata = controller.metadata
                        val newTitle = newMetadata?.getString(MediaMetadata.METADATA_KEY_TITLE)
                        val newArtist = newMetadata?.getString(MediaMetadata.METADATA_KEY_ARTIST)
                        if (newTitle != null && (newTitle != title || newArtist != artist)) {
                            eventSink?.success("LOG::Nouveau morceau détecté après ${waited * 100}ms.")
                            trackChanged = true
                            break
                        }
                        waited++
                    }

                    if (!trackChanged) {
                        eventSink?.success("LOG::Aucun morceau suivant détecté, fin de la file d'attente.")
                        break
                    }
                }
                
                eventSink?.success("LOG::Fin de l'aspiration.")
                eventSink?.endOfStream()
            } catch (e: Exception) {
                eventSink?.error("ERROR", e.message, null)
                eventSink?.endOfStream()
            }
        }
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val enabledListeners = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        val expectedComponent = ComponentName(this, NotificationScraperService::class.java)
        val fullFlat = expectedComponent.flattenToString()
        val shortFlat = expectedComponent.flattenToShortString()
        return enabledListeners.split(":").any { entry ->
            entry == fullFlat || entry == shortFlat
        }
    }

    override fun onDestroy() {
        scraperJob?.cancel()
        scraperJob = null
        eventSink = null
        coroutineScope.cancel()
        super.onDestroy()
    }
}
