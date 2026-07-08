import UserNotifications
import FirebaseMessaging

/// Downloads and attaches the image referenced by `fcm_options.image` (set
/// server-side in push/senders.py for DM alerts) so DM push notifications
/// show the sender's avatar, matching Instagram's message notification.
/// Soft (non-DM) notifications never set that field, so this is a no-op for
/// them beyond passing the content through unchanged.
class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        if let bestAttemptContent = bestAttemptContent {
            FIRMessagingExtensionHelper().populateNotificationContent(
                bestAttemptContent,
                withContentHandler: contentHandler
            )
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}
