import 'package:flutter/material.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'posture_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AwesomeNotifications().initialize(
    null,
    [
      NotificationChannel(
        channelKey: 'posture_alert',
        channelName: 'Posture Alerts',
        channelDescription: 'Notifications for bad posture',
        defaultColor: Colors.red,
        importance: NotificationImportance.High,
        channelShowBadge: true,
      ),
    ],
  );
  await AwesomeNotifications().isNotificationAllowed().then((isAllowed) {
    if (!isAllowed) {
      AwesomeNotifications().requestPermissionToSendNotifications();
    }
  });
  runApp(const PostureApp());
}

class PostureApp extends StatelessWidget {
  const PostureApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Posture Corrector',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const PosturePage(),
    );
  }
}
