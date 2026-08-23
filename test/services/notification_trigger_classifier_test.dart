import 'package:flutter_test/flutter_test.dart';
import 'package:hilight/services/notification_trigger_classifier.dart';

void main() {
  NotificationEvent event({
    String? category,
    String packageName = 'com.example.app',
    bool isOngoing = false,
  }) =>
      NotificationEvent(
        category: category,
        packageName: packageName,
        isOngoing: isOngoing,
      );

  group('NotificationTriggers.resolve (prd-v1.2.md §2)', () {
    test('category "call" fires the incoming-call trigger when enabled',
        () {
      final kind = NotificationTriggers.resolve(
        event(category: 'call'),
        (k) => k == TriggerKind.incomingCall,
      );
      expect(kind, TriggerKind.incomingCall);
    });

    test('a disabled trigger never fires even on a matching category', () {
      // Only SMS enabled; a call notification must not fall through.
      expect(
        NotificationTriggers.resolve(
          event(category: 'call'),
          (k) => k == TriggerKind.sms,
        ),
        isNull,
      );
    });

    test('"missed_call" deliberately does not fire the call trigger', () {
      expect(
        NotificationTriggers.resolve(
          event(category: 'missed_call'),
          (_) => true,
        ),
        isNull,
      );
    });

    test('category "msg" fires the SMS trigger', () {
      expect(
        NotificationTriggers.resolve(
          event(
            category: 'msg',
            packageName: 'com.google.android.apps.messaging',
          ),
          (_) => true,
        ),
        TriggerKind.sms,
      );
    });

    test('category "msg" fires the SMS trigger for messaging apps', () {
      expect(
        NotificationTriggers.resolve(
          event(
            category: 'msg',
            packageName: 'com.google.android.apps.messaging',
          ),
          (k) => k == TriggerKind.sms,
        ),
        TriggerKind.sms,
      );
    });

    test('chat platforms labeling "msg" never fire the SMS trigger '
        '(regression: Snapchat/WhatsApp flashed with App-notifications off)',
        () {
      for (final pkg in const [
        'com.snapchat.android',
        'com.whatsapp',
        'com.instagram.android',
      ]) {
        // With ONLY the SMS trigger enabled, chat DMs must stay silent.
        expect(
          NotificationTriggers.resolve(
            event(category: 'msg', packageName: pkg),
            (k) => k == TriggerKind.sms,
          ),
          isNull,
          reason: '$pkg must not fire the SMS trigger',
        );
        // They fall through to the generic app-notification path instead.
        expect(
          NotificationTriggers.resolve(
            event(category: 'msg', packageName: pkg),
            (k) => k == TriggerKind.appNotification,
          ),
          TriggerKind.appNotification,
          reason: '$pkg "msg" notifications are app notifications',
        );
      }
    });

    test('category-less notifications never fire call/SMS triggers '
        '(strict category matching — no package fallbacks)', () {
      expect(
        NotificationTriggers.resolve(event(), (_) => true),
        TriggerKind.appNotification,
      );
    });

    test('ongoing notifications never fire the app-notification trigger', () {
      expect(
        NotificationTriggers.resolve(
          event(packageName: 'com.some.music', isOngoing: true),
          (_) => true,
        ),
        isNull,
      );
    });

    test('alarm-or-timer ambiguity prefers alarm, falls back to timer', () {
      expect(
        NotificationTriggers.resolve(
          event(category: 'alarm'),
          (k) => k == TriggerKind.alarm || k == TriggerKind.timer,
        ),
        TriggerKind.alarm,
      );
      expect(
        NotificationTriggers.resolve(
          event(category: 'alarm'),
          (k) => k == TriggerKind.timer,
        ),
        TriggerKind.timer,
      );
      expect(
        NotificationTriggers.resolve(event(category: 'alarm'), (_) => false),
        isNull,
      );
    });

    test('"stopwatch" and reserved state/transport categories stay silent',
        () {
      expect(
        NotificationTriggers.resolve(
          event(category: 'stopwatch'),
          (_) => true,
        ),
        isNull,
      );
      expect(
        NotificationTriggers.resolve(event(category: 'transport'), (_) => true),
        isNull,
      );
      expect(
        NotificationTriggers.resolve(
          event(category: 'sys', packageName: 'com.android.systemui'),
          (_) => true,
        ),
        isNull,
      );
    });

    test('content categories like "social" fire the generic app trigger', () {
      expect(
        NotificationTriggers.resolve(
          event(category: 'social'),
          (k) => k == TriggerKind.appNotification,
        ),
        TriggerKind.appNotification,
      );
    });
  });
}
