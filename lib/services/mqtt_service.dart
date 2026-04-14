import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:flutter/foundation.dart';

class MqttService {
  MqttServerClient? _client;
  final StreamController<Map<String, String>> _messageController =
      StreamController<Map<String, String>>.broadcast();

  String connectionStatus = 'Disconnected';
  
  // Reconnection variables
  Timer? _reconnectionTimer;
  Timer? _heartbeatTimer;
  bool _isReconnecting = false;
  bool _shouldReconnect = true;
  int _reconnectionAttempts = 0;
  static const int _maxReconnectionAttempts = 5;
  static const Duration _reconnectionDelay = Duration(seconds: 5);
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  
  // Store connection parameters for reconnection
  String? _lastUserId;
  List<String> _subscribedTopics = [];
  Map<String, Function(String, String)> _topicCallbacks = {};

  // HiveMQ Cloud configuration - sesuai dengan referensi
  static const String _broker =
      '67d560452e2d4534b5decfc22c4cb938.s1.eu.hivemq.cloud';
  static const int _port = 8883;
  static const String _username = 'mobileapps';
  static const String _password = 'Mobile123!';

  Stream<Map<String, String>> get messageStream => _messageController.stream;
  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;
  
  bool get isReconnecting => _isReconnecting;
  int get reconnectionAttempts => _reconnectionAttempts;

  Future<void> connect({String? userId}) async {
    _lastUserId = userId;
    _shouldReconnect = true;
    
    // Stop any existing reconnection attempts
    _stopReconnectionTimer();
    
    // Gunakan user ID sebagai client ID jika tersedia, jika tidak gunakan timestamp
    final String clientId = userId != null 
        ? 'flutter_cooler_box_$userId'
        : 'flutter_cooler_box_${DateTime.now().millisecondsSinceEpoch}';

    _client = MqttServerClient.withPort(_broker, clientId, _port);

    // Konfigurasi untuk HiveMQ Cloud sesuai dengan example
    _client!.secure = true;
    _client!.securityContext =
        SecurityContext.defaultContext; // Penting untuk TLS
    _client!.keepAlivePeriod = 20; // Sesuai dengan HiveMQ Cloud example
    _client!.onDisconnected = _onDisconnected;
    _client!.onConnected = _onConnected;
    _client!.onSubscribed = _onSubscribed;

    try {
      connectionStatus = 'Connecting to HiveMQ Cloud...';
      _isReconnecting = false;

      debugPrint('Attempting to connect to: $_broker:$_port with MQTT v3.1.1');
      debugPrint('Username: $_username');
      debugPrint('Client ID: $clientId');

      // Connect dengan username dan password sesuai HiveMQ Cloud example
      await _client!.connect(_username, _password);
    } catch (e) {
      debugPrint('client exception - $e');
      connectionStatus = 'Connection error: $e';
      _client!.disconnect();
      
      // Start reconnection if should reconnect
      if (_shouldReconnect) {
        _startReconnection();
      }
      return;
    }

    // Check connection status sesuai HiveMQ Cloud example
    if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
      connectionStatus = 'Connected to HiveMQ Cloud';
      _reconnectionAttempts = 0;
      _isReconnecting = false;
      debugPrint('client connected');
      
      // Resubscribe to all previously subscribed topics
      _resubscribeToTopics();
      
      // Start heartbeat monitoring
      _startHeartbeat();
    } else {
      debugPrint(
        'ERROR client connection failed - disconnecting, status is ${_client!.connectionStatus}',
      );
      connectionStatus =
          'Connection failed: ${_client!.connectionStatus!.returnCode}';
      _client!.disconnect();
      
      // Start reconnection if should reconnect
      if (_shouldReconnect) {
        _startReconnection();
      }
    }
  }

  void subscribe(String topic, Function(String, String) onMessage) {
    debugPrint('MQTT: Attempting to subscribe to topic: $topic');
    
    // Store topic and callback for reconnection
    if (!_subscribedTopics.contains(topic)) {
      _subscribedTopics.add(topic);
    }
    _topicCallbacks[topic] = onMessage;
    
    if (_client == null) {
      debugPrint('MQTT: Client is null, cannot subscribe');
      return;
    }

    if (!_client!.connectionStatus!.state.toString().contains('connected')) {
      debugPrint('MQTT: Client not connected, current state: ${_client!.connectionStatus!.state}');
      return;
    }

    try {
      _client!.subscribe(topic, MqttQos.atMostOnce);
      debugPrint('MQTT: Successfully subscribed to topic: $topic');

      _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
        debugPrint('MQTT: Received message update, count: ${c?.length ?? 0}');
        
        if (c != null && c.isNotEmpty) {
          for (var message in c) {
            final MqttPublishMessage recMess = message.payload as MqttPublishMessage;
            final String payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
            final String receivedTopic = message.topic;
            
            debugPrint('MQTT: Raw message received');
            debugPrint('MQTT: Topic: $receivedTopic');
            debugPrint('MQTT: Payload: $payload');
            debugPrint('MQTT: Payload length: ${payload.length}');
            debugPrint('MQTT: Calling onMessage callback...');
            
            try {
              onMessage(receivedTopic, payload);
              debugPrint('MQTT: onMessage callback completed successfully');
            } catch (e) {
              debugPrint('MQTT: Error in onMessage callback: $e');
            }
          }
        } else {
          debugPrint('MQTT: Received empty or null message list');
        }
      }, onError: (error) {
        debugPrint('MQTT: Error in message listener: $error');
      });
    } catch (e) {
      debugPrint('MQTT: Error during subscription: $e');
    }
  }

  void publish(String topic, String message) {
    debugPrint('MQTT: Attempting to publish message');
    debugPrint('MQTT: Topic: $topic');
    debugPrint('MQTT: Message: $message');
    debugPrint('MQTT: Client status: ${_client?.connectionStatus?.state}');
    
    if (_client == null) {
      debugPrint('MQTT: Cannot publish - Client is null');
      return;
    }
    
    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      try {
        final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder();
        builder.addString(message);

        debugPrint('MQTT: Publishing message "$message" to topic "$topic"');
        _client!.publishMessage(topic, MqttQos.exactlyOnce, builder.payload!);
        debugPrint('MQTT: Message published successfully');
      } catch (e) {
        debugPrint('MQTT: Error publishing message: $e');
      }
    } else {
      debugPrint('MQTT: Cannot publish - Client not connected');
      debugPrint('MQTT: Current connection state: ${_client?.connectionStatus?.state}');
      debugPrint('MQTT: Connection status: ${_client?.connectionStatus}');
    }
  }

  // Publish JSON data for sensor readings
  void publishSensorData({
    required double temperature,
    required double latitude,
    required double longitude,
  }) {
    final Map<String, dynamic> sensorData = {
      'temp': temperature,
      'lat': latitude,
      'long': longitude,
    };

    final String jsonPayload = json.encode(sensorData);
    publish('esp32/data', jsonPayload);
  }

  void disconnect() {
    _shouldReconnect = false;
    _stopReconnectionTimer();
    _stopHeartbeat();
    _client?.disconnect();
    _messageController.close();
  }

  // Auto-reconnection methods
  void _startReconnection() {
    if (_isReconnecting || !_shouldReconnect) return;
    
    _isReconnecting = true;
    _reconnectionAttempts++;
    
    if (_reconnectionAttempts > _maxReconnectionAttempts) {
      debugPrint('MQTT: Max reconnection attempts reached. Stopping reconnection.');
      connectionStatus = 'Max reconnection attempts reached';
      _isReconnecting = false;
      return;
    }
    
    connectionStatus = 'Reconnecting... (${_reconnectionAttempts}/$_maxReconnectionAttempts)';
    debugPrint('MQTT: Starting reconnection attempt $_reconnectionAttempts');
    
    _reconnectionTimer = Timer(_reconnectionDelay, () {
      if (_shouldReconnect) {
        connect(userId: _lastUserId);
      }
    });
  }
  
  void _stopReconnectionTimer() {
    _reconnectionTimer?.cancel();
    _reconnectionTimer = null;
  }
  
  void _resubscribeToTopics() {
    for (String topic in _subscribedTopics) {
      final callback = _topicCallbacks[topic];
      if (callback != null) {
        subscribe(topic, callback);
      }
    }
  }
  
  // Heartbeat monitoring
  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      _checkConnection();
    });
  }
  
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
  
  void _checkConnection() {
    if (_client == null || !isConnected) {
      debugPrint('MQTT: Connection lost detected by heartbeat');
      if (_shouldReconnect) {
        _startReconnection();
      }
    }
  }
  
  // Force reconnection method (can be called externally)
  Future<void> forceReconnect() async {
    debugPrint('MQTT: Force reconnection requested');
    _reconnectionAttempts = 0;
    _stopReconnectionTimer();
    
    if (_client != null) {
      _client!.disconnect();
    }
    
    await connect(userId: _lastUserId);
  }
  
  // App lifecycle methods
  void onAppResumed() {
    debugPrint('MQTT: App resumed, checking connection...');
    if (!isConnected && _shouldReconnect) {
      forceReconnect();
    }
  }
  
  void onAppPaused() {
    debugPrint('MQTT: App paused');
    // Keep connection alive but stop heartbeat to save battery
    _stopHeartbeat();
  }

  // Callback methods
  void _onSubscribed(String topic) {
    connectionStatus = 'Connected & Subscribed to: $topic';
    debugPrint('Subscription confirmed for topic $topic');
  }

  void _onDisconnected() {
    connectionStatus = 'Disconnected from HiveMQ Cloud';
    debugPrint('OnDisconnected client callback - Client disconnection');
    
    _stopHeartbeat();
    
    // Start reconnection if should reconnect and not already reconnecting
    if (_shouldReconnect && !_isReconnecting) {
      _startReconnection();
    }
  }

  void _onConnected() {
    connectionStatus = 'Connected to HiveMQ Cloud';
    _reconnectionAttempts = 0;
    _isReconnecting = false;
    debugPrint('OnConnected client callback - Client connection was sucessful');
    
    // Start heartbeat monitoring
    _startHeartbeat();
  }
}
