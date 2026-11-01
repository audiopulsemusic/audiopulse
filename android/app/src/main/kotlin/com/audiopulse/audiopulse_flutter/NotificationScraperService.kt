package com.audiopulse.audiopulse_flutter

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class NotificationScraperService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        // Pas besoin de l'utiliser activement, c'est juste pour avoir la permission MEDIA_CONTENT_CONTROL.
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
    }
}
