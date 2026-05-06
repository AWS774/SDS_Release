import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

const String _broker = '67d560452e2d4534b5decfc22c4cb938.s1.eu.hivemq.cloud';
const int _port = 8883;
const String _username = 'mobileapps';
const String _password = 'Mobile123!';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (Platform.isAndroid) {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'sds_background_channel',
      'Smart Delivery System',
      description: 'Background service untuk monitoring suhu',
      importance: Importance.high,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'sds_background_channel',
      initialNotificationTitle: 'Smart Delivery System',
      initialNotificationContent: 'Monitoring berjalan di background...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  MqttServerClient? client;
  String? currentTopic;

  // Terima topic dari UI
  service.on('setTopic').listen((event) async {
    currentTopic = event?['topic'];
    if (currentTopic != null && client != null) {
      _subscribeToTopic(client!, currentTopic!, service);
    }
  });

  // Stop service
  service.on('stopService').listen((event) {
    client?.disconnect();
    service.stopSelf();
  });

  // Connect MQTT
  client = await _connectMqtt(service);

  if (client != null && currentTopic != null) {
    _subscribeToTopic(client!, currentTopic!, service);
  }

  // Heartbeat setiap 30 detik
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    if (client == null ||
        client!.connectionStatus?.state != MqttConnectionState.connected) {
      client = await _connectMqtt(service);
      if (client != null && currentTopic != null) {
        _subscribeToTopic(client!, currentTopic!, service);
      }
    }
    service.invoke('update', {'status': 'running'});
  });
}

Future<MqttServerClient?> _connectMqtt(ServiceInstance service) async {
  final clientId = 'sds_background_${DateTime.now().millisecondsSinceEpoch}';
  final client = MqttServerClient.withPort(_broker, clientId, _port);

  client.secure = true;
  client.securityContext = SecurityContext.defaultContext;
  client.keepAlivePeriod = 20;

  try {
    await client.connect(_username, _password);
    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      service.invoke('update', {'status': 'connected'});
      return client;
    }
  } catch (e) {
    service.invoke('update', {'status': 'error: $e'});
  }

  return null;
}

void _subscribeToTopic(
  MqttServerClient client,
  String topic,
  ServiceInstance service,
) {
  client.subscribe(topic, MqttQos.atMostOnce);

  client.updates?.listen((messages) {
    for (var message in messages) {
      final payload = MqttPublishPayload.bytesToStringAsString(
        (message.payload as MqttPublishMessage).payload.message,
      );

      try {
        final data = json.decode(payload);
        final double temp = (data['temp'] ?? 0).toDouble();
        final double setpoint = (data['setpoint'] ?? 25).toDouble();

        service.invoke('mqttData', {
          'topic': message.topic,
          'payload': payload,
        });

        // Kirim notifikasi jika suhu melebihi setpoint
        if (temp >= setpoint) {
          _showTemperatureNotification(temp, setpoint);
        }
      } catch (e) {
        service.invoke('mqttData', {
          'topic': message.topic,
          'payload': payload,
        });
      }
    }
  });
}

Future<void> _showTemperatureNotification(
  double temp,
  double setpoint,
) async {
  final plugin = FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await plugin.initialize(initializationSettings);

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'sds_background_channel',
    'Smart Delivery System',
    channelDescription: 'Background service untuk monitoring suhu',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );

  const NotificationDetails notificationDetails =
      NotificationDetails(android: androidDetails);

  await plugin.show(
    999,
    '🌡️ Peringatan Suhu Tinggi!',
    'Suhu ${temp.toStringAsFixed(1)}°C melebihi batas ${setpoint.toStringAsFixed(1)}°C',
    notificationDetails,
  );
}