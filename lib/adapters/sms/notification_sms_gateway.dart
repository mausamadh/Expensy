import '../../domain/sms_import/ports/ports.dart';
import '../../services/notification_service.dart';

class NotificationSmsGateway implements SmsNotificationGateway {
  const NotificationSmsGateway();

  @override
  Future<void> notifyImported({
    required String inboxId,
    required String description,
  }) =>
      NotificationService().showSmsNotification(
        inboxId: inboxId,
        title: 'Transaction parsed',
        body: description,
      );

  @override
  Future<void> notifyVerificationRequired({
    required String inboxId,
    required String reason,
  }) =>
      NotificationService().showSmsNotification(
        inboxId: inboxId,
        title: 'SMS needs verification',
        body: reason,
      );

  @override
  Future<void> notifyImportFailed({
    required String inboxId,
    required String reason,
  }) =>
      NotificationService().showSmsNotification(
        inboxId: inboxId,
        title: 'SMS import failed',
        body: reason,
      );
}
