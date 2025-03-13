import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

Future<void> sendNotification() async {
  await AwesomeNotifications().createNotification(
    content: NotificationContent(
      id: 10,
      channelKey: 'posture_alert',
      title: 'Bad Posture Detected',
      body: 'Please correct your posture!',
    ),
  );
}

void vibrate() {
  Vibration.vibrate(
    pattern: [0, 500, 100, 500, 100, 500],
    intensities: [0, 128, 0, 255, 0, 64],
  );
}
