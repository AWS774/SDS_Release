import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'dart:async';
import '../services/mqtt_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/database_service.dart';
import '../widgets/storage_time_info.dart';
import '../models/device.dart';

// Enum for popup types
enum PopupType { temperature, time }

// Color constants for popups
const Color dangerRed = Color(0xFFE53E3E);
const Color warningOrange = Color(0xFFFF8C00);
const Color textPrimary = Color(0xFF2D3748);
const Color textSecondary = Color(0xFF718096);

class MonitoringScreen extends StatefulWidget {
  final Device? device;

  const MonitoringScreen({super.key, this.device});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final MqttService _mqttService = MqttService();
  final AuthService _authService = AuthService();
  final NotificationService _notificationService = NotificationService();
  final DatabaseService _databaseService = DatabaseService();
  final TextEditingController _maxTempController = TextEditingController();
  final MapController _mapController = MapController();

  // Time configuration controllers
  final TextEditingController _daysController = TextEditingController();
  final TextEditingController _hoursController = TextEditingController();
  final TextEditingController _minutesController = TextEditingController();
  final TextEditingController _secondsController = TextEditingController();

  // Animation controllers
  late AnimationController _temperatureAnimationController;
  late AnimationController _pulseAnimationController;
  late Animation<double> _temperatureAnimation;
  late Animation<double> _pulseAnimation;

  // Data variables
  double _currentTemperature = 0.0;
  double _maxTemperature = 30.0;
  LatLng _currentLocation = const LatLng(-6.2088, 106.8456); // Default Jakarta

  // UI state
  bool _isConnected = false;
  String _connectionStatus = 'Disconnected';
  bool _mapLoadError = false;
  bool _isReconnecting = false;
  int _reconnectionAttempts = 0;

  // Time configuration state
  bool _isTimeConfigLoading = false;
  int _storageDays = 1;
  int _storageHours = 0;
  int _storageMinutes = 0;
  int _storageSeconds = 0;

  // Storage time data from database
  Map<String, dynamic>? _storageTimeData;

  // Modern color scheme
  static const Color primaryBlue = Color(0xFF2196F3);
  static const Color primaryDark = Color(0xFF1976D2);
  static const Color accentTeal = Color(0xFF00BCD4);
  static const Color warningOrange = Color(0xFFFF9800);
  static const Color dangerRed = Color(0xFFE53935);
  static const Color successGreen = Color(0xFF4CAF50);
  static const Color backgroundGrey = Color(0xFFF5F7FA);
  static const Color cardWhite = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF2C3E50);
  static const Color textSecondary = Color(0xFF7B8794);

  @override
  void initState() {
    super.initState();
    // Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Initialize animations
    _temperatureAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _pulseAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _temperatureAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _temperatureAnimationController,
        curve: Curves.easeOutBack,
      ),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(
        parent: _pulseAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _initializeServices();
    _loadLatestSensorData();
    _loadStorageTimeData();
    _connectToMqtt();
    // Don't set controller text here - it will be set after loading from database

    // Initialize time configuration controllers with default values
    _daysController.text = _storageDays.toString();
    _hoursController.text = _storageHours.toString();
    _minutesController.text = _storageMinutes.toString();
    _secondsController.text = _storageSeconds.toString();
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    _mqttService.disconnect();
    _maxTempController.dispose();
    _daysController.dispose();
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    _temperatureAnimationController.dispose();
    _pulseAnimationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        print('App resumed - checking MQTT connection');
        _mqttService.onAppResumed();
        // Update UI state after a short delay to allow reconnection
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _updateConnectionStatus();
          }
        });
        break;
      case AppLifecycleState.paused:
        print('App paused');
        _mqttService.onAppPaused();
        break;
      case AppLifecycleState.inactive:
        print('App inactive');
        break;
      case AppLifecycleState.detached:
        print('App detached');
        break;
      case AppLifecycleState.hidden:
        print('App hidden');
        break;
    }
  }

  void _updateConnectionStatus() {
    if (mounted) {
      setState(() {
        _isConnected = _mqttService.isConnected;
        _connectionStatus = _mqttService.connectionStatus;
        _isReconnecting = _mqttService.isReconnecting;
        _reconnectionAttempts = _mqttService.reconnectionAttempts;
      });
    }
  }

  Future<void> _initializeServices() async {
    try {
      await _notificationService.initialize();
      print('✅ NotificationService initialized in MonitoringScreen');
    } catch (e) {
      print('❌ Error initializing NotificationService: $e');
    }

    try {
      await _databaseService.initialize();
      print('✅ DatabaseService initialized in MonitoringScreen');
    } catch (e) {
      print('❌ Error initializing DatabaseService: $e');
    }
  }

  Future<void> _loadLatestSensorData() async {
    try {
      // Gunakan device ID dari parameter device jika tersedia
      final deviceId = widget.device?.deviceId ?? 'esp32_cooler_box';

      // Load latest sensor data from database
      final latestData = await _databaseService.getLatestSensorData(deviceId);

      if (latestData != null && mounted) {
        setState(() {
          // Update temperature if available
          if (latestData['temperature'] != null) {
            _currentTemperature = (latestData['temperature'] as num).toDouble();
          }

          // Update location if available
          if (latestData['latitude'] != null &&
              latestData['longitude'] != null) {
            _currentLocation = LatLng(
              (latestData['latitude'] as num).toDouble(),
              (latestData['longitude'] as num).toDouble(),
            );
          }
        });

        print(
          '✅ Latest sensor data loaded: Temp=${_currentTemperature}°C, Location=${_currentLocation.latitude},${_currentLocation.longitude}',
        );
      } else {
        print('ℹ️ No previous sensor data found in database');
      }

      // Load device settings separately
      await _loadDeviceSettings();
    } catch (e) {
      print('❌ Error loading latest sensor data: $e');
    }
  }

  Future<void> _loadDeviceSettings() async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        print('❌ Cannot load device settings: User not authenticated');
        // Set default value and update controller if user not authenticated
        setState(() {
          _maxTemperature = 30.0;
          _maxTempController.text = _maxTemperature.toString();
        });
        return;
      }

      final settings = await _databaseService.getDeviceSettings(
        deviceId: widget.device?.deviceId ?? 'esp32_cooler_box',
        userId: user.id,
      );

      if (settings != null && mounted) {
        setState(() {
          if (settings['max_temperature'] != null) {
            _maxTemperature = (settings['max_temperature'] as num).toDouble();
            _maxTempController.text = _maxTemperature.toString();
          } else {
            // If max_temperature is null in database, use default
            _maxTemperature = 30.0;
            _maxTempController.text = _maxTemperature.toString();
          }
        });

        print('✅ Device settings loaded: MaxTemp=${_maxTemperature}°C');
      } else {
        print('ℹ️ No device settings found, using default values');
        // Set default value and update controller if no settings found
        setState(() {
          _maxTemperature = 30.0;
          _maxTempController.text = _maxTemperature.toString();
        });
      }
    } catch (e) {
      print('❌ Error loading device settings: $e');
      // Set default value and update controller on error
      setState(() {
        _maxTemperature = 30.0;
        _maxTempController.text = _maxTemperature.toString();
      });
    }
  }

  Future<void> _saveDeviceSettings() async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        print('❌ Cannot save device settings: User not authenticated');
        return;
      }

      // Gunakan device ID dari parameter device jika tersedia
      final deviceId = widget.device?.deviceId ?? 'esp32_cooler_box';

      await _databaseService.saveDeviceSettings(
        deviceId: deviceId,
        userId: user.id,
        maxTemperature: _maxTemperature,
      );

      print(
        '✅ Device settings saved for device $deviceId: MaxTemp=${_maxTemperature}°C',
      );
    } catch (e) {
      print('❌ Error saving device settings: $e');
    }
  }

  Future<void> _connectToMqtt() async {
    try {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _connectionStatus = 'Connecting...';
        });
      }

      // Dapatkan user ID dari auth service
      final user = _authService.currentUser;
      final userId = user?.id;

      await _mqttService.connect(userId: userId);

      // Check if connection was successful
      if (_mqttService.isConnected) {
        if (mounted) {
          setState(() {
            _isConnected = true;
            _connectionStatus = _mqttService.connectionStatus;
          });
        }

        // Subscribe to combined sensor data topic with callback
        // Gunakan device ID dari parameter jika tersedia
        final deviceTopic =
            widget.device != null
                ? '${widget.device!.deviceId}/data'
                : 'esp32/data';

        _mqttService.subscribe(deviceTopic, _handleMqttMessage);

        // Subscribe to time notification topic
        final timeTopic =
            widget.device != null
                ? '${widget.device!.deviceId}/time_notification'
                : 'esp32/time_notification';

        _mqttService.subscribe(timeTopic, _handleMqttMessage);

        // Listen to incoming messages (keeping for backward compatibility)
        _mqttService.messageStream.listen((message) {
          final topic = message['topic'] as String?;
          final payload = message['payload'] as String?;
          if (topic != null && payload != null) {
            print(
              'MonitoringScreen: Received message from stream - Topic: $topic, Payload: $payload',
            );
            _handleMqttMessage(topic, payload);
          }
        });
      } else {
        if (mounted) {
          setState(() {
            _isConnected = false;
            _connectionStatus = _mqttService.connectionStatus;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _connectionStatus = 'Connection Failed: $e';
        });
      }
    }
  }

  void _handleMqttMessage(String topic, String payload) {
    if (!mounted) return;

    print('Received MQTT message - Topic: $topic, Payload: $payload');

    // Check if message is from the selected device
    final expectedDataTopic =
        widget.device != null
            ? '${widget.device!.deviceId}/data'
            : 'esp32/data';
    final expectedTimeTopic =
        widget.device != null
            ? '${widget.device!.deviceId}/time_notification'
            : 'esp32/time_notification';

    if (topic == expectedDataTopic) {
      try {
        // Parse JSON payload
        final Map<String, dynamic> data = json.decode(payload);

        double? temperature;
        double? latitude;
        double? longitude;
        double? setpoint;

        // Extract device ID (for logging/debugging)
        if (data.containsKey('deviceid')) {
          print('Received data from device: ${data['deviceid']}');
        }

        // Extract temperature
        if (data.containsKey('temp')) {
          temperature = (data['temp'] as num?)?.toDouble() ?? 0.0;
          print('Updating temperature to: $temperature°C');
          setState(() {
            _currentTemperature = temperature!;
          });

          // Check if temperature exceeds maximum threshold
          _checkTemperatureThreshold(temperature);
        }

        // Extract GPS coordinates
        if (data.containsKey('lat') && data.containsKey('long')) {
          latitude = (data['lat'] as num?)?.toDouble();
          longitude = (data['long'] as num?)?.toDouble();

          if (latitude != null &&
              longitude != null &&
              latitude != 0.0 &&
              longitude != 0.0) {
            final newLocation = LatLng(latitude, longitude);
            print('Updating location to: $latitude, $longitude');
            setState(() {
              _currentLocation = newLocation;
            });
            _updateMapLocation();
          }
        }

        // Extract setpoint (current max temperature setting from ESP32)
        if (data.containsKey('setpoint')) {
          setpoint = (data['setpoint'] as num?)?.toDouble();
          if (setpoint != null) {
            print('Received current setpoint from ESP32: $setpoint°C');
            setState(() {
              _maxTemperature = setpoint!;
              _maxTempController.text = setpoint.toString();
            });
          }
        }

        // Save to database
        _saveSensorDataToDatabase(
          temperature: temperature,
          latitude: latitude,
          longitude: longitude,
        );
      } catch (e) {
        print('Error parsing JSON payload: $e');
        // Fallback: try to handle as separate topics for backward compatibility
        _handleLegacyFormat(topic, payload);
      }
    } else if (topic == expectedTimeTopic) {
      // Handle ESP32 time notification
      _handleTimeNotification(payload);
    } else {
      // Handle legacy format for backward compatibility
      _handleLegacyFormat(topic, payload);
    }
  }

  void _handleLegacyFormat(String topic, String payload) {
    if (topic == 'esp32/temperature') {
      final temperature = double.tryParse(payload) ?? 0.0;
      print('Updating temperature to: $temperature°C (legacy format)');
      setState(() {
        _currentTemperature = temperature;
      });

      // Check if temperature exceeds maximum threshold
      _checkTemperatureThreshold(temperature);

      // Save temperature data to database
      _saveSensorDataToDatabase(temperature: temperature);
    } else if (topic == 'esp32/gps') {
      // Expected format: "lat,lng"
      final coords = payload.split(',');
      if (coords.length == 2) {
        final lat = double.tryParse(coords[0]);
        final lng = double.tryParse(coords[1]);
        if (lat != null && lng != null) {
          final newLocation = LatLng(lat, lng);
          print('Updating location to: $lat, $lng (legacy format)');
          setState(() {
            _currentLocation = newLocation;
          });
          _updateMapLocation();

          // Save GPS data to database using sensor_data table
          _saveSensorDataToDatabase(latitude: lat, longitude: lng);
        }
      }
    }
  }

  void _updateMapLocation() {
    if (!mounted) return;

    try {
      _mapController.move(_currentLocation, 15.0);
      print(
        'Map location updated to: ${_currentLocation.latitude}, ${_currentLocation.longitude}',
      );
    } catch (e) {
      debugPrint('Error updating map location: $e');
    }
  }

  void _sendMaxTemperature() {
    print('DEBUG: _sendMaxTemperature called');
    print('DEBUG: Input text: "${_maxTempController.text}"');

    final maxTemp = double.tryParse(_maxTempController.text);
    print('DEBUG: Parsed temperature: $maxTemp');

    if (maxTemp != null) {
      print('DEBUG: Attempting to publish max temperature: $maxTemp');
      print('DEBUG: MQTT service connected: ${_mqttService.isConnected}');

      // Gunakan device-specific topic
      final deviceTopic =
          widget.device != null
              ? '${widget.device!.deviceId}/setpoint'
              : 'esp32/setpoint';

      _mqttService.publish(deviceTopic, jsonEncode({'atur_setpoint': maxTemp}));

      if (mounted) {
        setState(() {
          _maxTemperature = maxTemp;
        });
        print('DEBUG: UI state updated with max temperature: $_maxTemperature');

        // Save max temperature to device settings table
        _saveDeviceSettings();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Suhu maksimal diatur ke ${maxTemp}°C'),
            backgroundColor: Colors.green,
          ),
        );
        print('DEBUG: Success snackbar shown');
      }
    } else {
      print('DEBUG: Invalid temperature input: "${_maxTempController.text}"');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Masukkan nilai suhu yang valid'),
            backgroundColor: Colors.red,
          ),
        );
        print('DEBUG: Error snackbar shown');
      }
    }
  }

  Future<void> _loadStorageTimeData() async {
    try {
      // Gunakan device ID dari parameter device jika tersedia
      final deviceId = widget.device?.deviceId ?? 'esp32_cooler_box';
      final user = _authService.currentUser;

      // Validasi user login
      if (user == null) {
        print('❌ User belum login, tidak dapat memuat data waktu penyimpanan');
        return;
      }

      final data = await _databaseService.getStorageTimeSettings(
        deviceId: deviceId,
        userId: user.id,
      );
      if (data != null && mounted) {
        setState(() {
          _storageTimeData = data;
        });
        print('✅ Storage time data loaded: $data');
      }
    } catch (e) {
      print('❌ Error loading storage time data: $e');
    }
  }

  void _sendTimeConfiguration() async {
    print('DEBUG: _sendTimeConfiguration called');

    // Set loading state
    if (mounted) {
      setState(() {
        _isTimeConfigLoading = true;
      });
    }

    try {
      // Parse input values
      final days = int.tryParse(_daysController.text) ?? 0;
      final hours = int.tryParse(_hoursController.text) ?? 0;
      final minutes = int.tryParse(_minutesController.text) ?? 0;
      final seconds = int.tryParse(_secondsController.text) ?? 0;

      print(
        'DEBUG: Parsed time values - Days: $days, Hours: $hours, Minutes: $minutes, Seconds: $seconds',
      );

      // Validate input ranges
      if (days < 0 ||
          hours < 0 ||
          hours > 23 ||
          minutes < 0 ||
          minutes > 59 ||
          seconds < 0 ||
          seconds > 59) {
        throw Exception('Nilai waktu tidak valid');
      }

      // Check if all values are zero
      if (days == 0 && hours == 0 && minutes == 0 && seconds == 0) {
        throw Exception('Waktu penyimpanan tidak boleh 0 semua');
      }

      // Calculate start and end times
      final startTime = DateTime.now();
      final endTime = startTime.add(
        Duration(days: days, hours: hours, minutes: minutes, seconds: seconds),
      );

      // Create JSON payload
      final payload = {
        'days': days,
        'hours': hours,
        'minutes': minutes,
        'seconds': seconds,
      };

      print('DEBUG: Time configuration payload: ${jsonEncode(payload)}');
      print('DEBUG: MQTT service connected: ${_mqttService.isConnected}');

      // Send via MQTT - gunakan device-specific topic
      final deviceTopic =
          widget.device != null
              ? '${widget.device!.deviceId}/time'
              : 'esp32/time';

      _mqttService.publish(deviceTopic, jsonEncode(payload));

      // Save to database
      try {
        // Gunakan device ID dari parameter device jika tersedia
        final deviceId = widget.device?.deviceId ?? 'esp32_cooler_box';
        final user = _authService.currentUser;

        // Validasi user login
        if (user == null) {
          throw Exception('User belum login. Silakan login terlebih dahulu.');
        }

        await _databaseService.saveStorageTimeSettings(
          deviceId: deviceId,
          userId: user.id,
          days: days,
          hours: hours,
          minutes: minutes,
          seconds: seconds,
          startTime: startTime,
          endTime: endTime,
        );

        // Update local storage time data
        setState(() {
          _storageTimeData = {
            'days': days,
            'hours': hours,
            'minutes': minutes,
            'seconds': seconds,
            'start_time': startTime.toIso8601String(),
            'end_time': endTime.toIso8601String(),
          };
        });

        print('✅ Storage time settings saved to database');
      } catch (dbError) {
        print('❌ Error saving storage time settings: $dbError');
        throw dbError; // Re-throw agar error ditangani di catch block luar
      }

      // Update local state
      if (mounted) {
        setState(() {
          _storageDays = days;
          _storageHours = hours;
          _storageMinutes = minutes;
          _storageSeconds = seconds;
        });
        print('DEBUG: UI state updated with time configuration');
      }

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Waktu penyimpanan diatur ke ${days}d ${hours}h ${minutes}m ${seconds}s',
            ),
            backgroundColor: Colors.green,
          ),
        );
        print('DEBUG: Success snackbar shown for time configuration');
      }
    } catch (e) {
      print('DEBUG: Error in time configuration: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        print('DEBUG: Error snackbar shown for time configuration');
      }
    } finally {
      // Reset loading state
      if (mounted) {
        setState(() {
          _isTimeConfigLoading = false;
        });
      }
    }
  }

  Widget _buildMapWidget() {
    if (_mapLoadError) {
      return Container(
        height: 250,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
          color: Colors.grey.shade100,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Maps tidak dapat dimuat',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Koordinat: ${_currentLocation.latitude.toStringAsFixed(6)}, ${_currentLocation.longitude.toStringAsFixed(6)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _mapLoadError = false;
                });
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentLocation,
            initialZoom: 15.0,
            minZoom: 5.0,
            maxZoom: 18.0,
            onMapReady: () {
              // Map is ready, move to current location
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) {
                  _mapController.move(_currentLocation, 15.0);
                }
              });
            },
          ),
          children: [
            // Tile layer - using OpenStreetMap
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.cooler_box',
              maxZoom: 18,
              errorTileCallback: (tile, error, stackTrace) {
                debugPrint('Error loading tile: $error');
                if (mounted) {
                  setState(() {
                    _mapLoadError = true;
                  });
                }
              },
            ),
            // Marker layer
            MarkerLayer(
              markers: [
                Marker(
                  point: _currentLocation,
                  width: 40,
                  height: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundGrey,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          widget.device != null
              ? 'Monitoring ${widget.device!.name}'
              : 'Monitoring Suhu',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: cardWhite,
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [primaryBlue, primaryDark],
            ),
          ),
        ),
        actions: const [],
      ),
      body: RepaintBoundary(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Simple Status Bar
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _isConnected ? successGreen : dangerRed,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: (_isConnected ? successGreen : dangerRed)
                          .withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isConnected ? Icons.wifi : Icons.wifi_off,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isConnected ? 'Terhubung' : 'Tidak Terhubung',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // Temperature Display Card
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _temperatureAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 0.95 + (0.05 * _temperatureAnimation.value),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [cardWhite, cardWhite.withOpacity(0.9)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Suhu Saat Ini',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                            color: textSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        AnimatedBuilder(
                                          animation:
                                              _currentTemperature >
                                                      _maxTemperature
                                                  ? _pulseAnimation
                                                  : _temperatureAnimation,
                                          builder: (context, child) {
                                            return Transform.scale(
                                              scale:
                                                  _currentTemperature >
                                                          _maxTemperature
                                                      ? _pulseAnimation.value
                                                      : 1.0,
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  '${_currentTemperature.toStringAsFixed(1)}°C',
                                                  maxLines: 1,
                                                  style: TextStyle(
                                                    fontSize: 42,
                                                    fontWeight: FontWeight.w700,
                                                    color:
                                                        _currentTemperature >
                                                                _maxTemperature
                                                            ? dangerRed
                                                            : _currentTemperature >
                                                                (_maxTemperature *
                                                                    0.8)
                                                            ? warningOrange
                                                            : primaryBlue,
                                                    shadows: [
                                                      Shadow(
                                                        color: (_currentTemperature >
                                                                    _maxTemperature
                                                                ? dangerRed
                                                                : primaryBlue)
                                                            .withOpacity(0.3),
                                                        blurRadius: 8,
                                                        offset: const Offset(
                                                          0,
                                                          2,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors:
                                            _currentTemperature >
                                                    _maxTemperature
                                                ? [
                                                  dangerRed.withOpacity(0.1),
                                                  dangerRed.withOpacity(0.05),
                                                ]
                                                : _currentTemperature >
                                                    (_maxTemperature * 0.8)
                                                ? [
                                                  warningOrange.withOpacity(
                                                    0.1,
                                                  ),
                                                  warningOrange.withOpacity(
                                                    0.05,
                                                  ),
                                                ]
                                                : [
                                                  primaryBlue.withOpacity(0.1),
                                                  primaryBlue.withOpacity(0.05),
                                                ],
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: (_currentTemperature >
                                                    _maxTemperature
                                                ? dangerRed
                                                : _currentTemperature >
                                                    (_maxTemperature * 0.8)
                                                ? warningOrange
                                                : primaryBlue)
                                            .withOpacity(0.2),
                                        width: 2,
                                      ),
                                    ),
                                    child: AnimatedBuilder(
                                      animation:
                                          _currentTemperature > _maxTemperature
                                              ? _pulseAnimation
                                              : _temperatureAnimation,
                                      builder: (context, child) {
                                        return Transform.scale(
                                          scale:
                                              _currentTemperature >
                                                      _maxTemperature
                                                  ? _pulseAnimation.value
                                                  : 1.0,
                                          child: Icon(
                                            _getTemperatureIcon(
                                              _currentTemperature,
                                            ),
                                            size: 48,
                                            color:
                                                _currentTemperature >
                                                        _maxTemperature
                                                    ? dangerRed
                                                    : _currentTemperature >
                                                        (_maxTemperature * 0.8)
                                                    ? warningOrange
                                                    : primaryBlue,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              if (_currentTemperature > _maxTemperature)
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        dangerRed.withOpacity(0.1),
                                        dangerRed.withOpacity(0.05),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: dangerRed.withOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: dangerRed.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.warning_rounded,
                                          color: dangerRed,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'PERINGATAN: Suhu melebihi batas maksimal (${_maxTemperature}°C)!',
                                          style: TextStyle(
                                            color: dangerRed,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),

              // Maps Card - Now using flutter_map
              RepaintBoundary(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [cardWhite, cardWhite.withOpacity(0.9)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    accentTeal.withOpacity(0.1),
                                    accentTeal.withOpacity(0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.location_on_rounded,
                                color: accentTeal,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Lokasi Device',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            height: 250,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.grey.shade200,
                                width: 1,
                              ),
                            ),
                            child: _buildMapWidget(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: backgroundGrey,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.my_location_rounded,
                                size: 16,
                                color: textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Koordinat: ${_currentLocation.latitude.toStringAsFixed(6)}, ${_currentLocation.longitude.toStringAsFixed(6)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Temperature Settings Card
              RepaintBoundary(
                child: Container(
                  width: double.infinity,
                  constraints: BoxConstraints(
                    minHeight: 200,
                    maxWidth: MediaQuery.of(context).size.width - 32,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [cardWhite, cardWhite.withOpacity(0.9)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal:
                          MediaQuery.of(context).size.width > 600 ? 24 : 16,
                      vertical:
                          MediaQuery.of(context).size.width > 600 ? 24 : 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header Row
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(
                                MediaQuery.of(context).size.width > 600
                                    ? 12
                                    : 10,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    warningOrange.withOpacity(0.1),
                                    warningOrange.withOpacity(0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.tune_rounded,
                                color: warningOrange,
                                size:
                                    MediaQuery.of(context).size.width > 600
                                        ? 24
                                        : 20,
                              ),
                            ),
                            SizedBox(
                              width:
                                  MediaQuery.of(context).size.width > 600
                                      ? 12
                                      : 8,
                            ),
                            Expanded(
                              child: Text(
                                'Pengaturan Suhu Maksimal',
                                style: TextStyle(
                                  fontSize:
                                      MediaQuery.of(context).size.width > 600
                                          ? 20
                                          : 18,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(
                          height:
                              MediaQuery.of(context).size.width > 600 ? 20 : 16,
                        ),

                        // Input Row - Responsive Layout
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isSmallScreen = constraints.maxWidth < 400;

                            if (isSmallScreen) {
                              // Stack layout for small screens
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Input Field
                                  Container(
                                    constraints: BoxConstraints(maxHeight: 80),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                        width: 1,
                                      ),
                                    ),
                                    child: TextField(
                                      controller: _maxTempController,
                                      keyboardType: TextInputType.number,
                                      maxLength: 5, // Limit input length
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: textPrimary,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Suhu Maksimal (°C)',
                                        labelStyle: TextStyle(
                                          color: textSecondary,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                        ),
                                        border: InputBorder.none,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                        counterText:
                                            '', // Hide character counter
                                        prefixIcon: Container(
                                          margin: const EdgeInsets.all(8),
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: primaryBlue.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.device_thermostat_rounded,
                                            color: primaryBlue,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // Send Button
                                  Container(
                                    width: double.infinity,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      gradient:
                                          _isConnected
                                              ? const LinearGradient(
                                                colors: [
                                                  primaryBlue,
                                                  primaryDark,
                                                ],
                                              )
                                              : LinearGradient(
                                                colors: [
                                                  Colors.grey.shade400,
                                                  Colors.grey.shade500,
                                                ],
                                              ),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow:
                                          _isConnected
                                              ? [
                                                BoxShadow(
                                                  color: primaryBlue
                                                      .withOpacity(0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ]
                                              : null,
                                    ),
                                    child: ElevatedButton(
                                      onPressed:
                                          _isConnected
                                              ? _sendMaxTemperature
                                              : null,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        foregroundColor: Colors.white,
                                        shadowColor: Colors.transparent,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        'Kirim',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            } else {
                              // Row layout for larger screens
                              return Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Container(
                                      constraints: BoxConstraints(
                                        maxHeight: 80,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                          width: 1,
                                        ),
                                      ),
                                      child: TextField(
                                        controller: _maxTempController,
                                        keyboardType: TextInputType.number,
                                        maxLength: 5, // Limit input length
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: textPrimary,
                                        ),
                                        decoration: InputDecoration(
                                          labelText: 'Suhu Maksimal (°C)',
                                          labelStyle: TextStyle(
                                            color: textSecondary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          border: InputBorder.none,
                                          contentPadding: const EdgeInsets.all(
                                            16,
                                          ),
                                          counterText:
                                              '', // Hide character counter
                                          prefixIcon: Container(
                                            margin: const EdgeInsets.all(8),
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: primaryBlue.withOpacity(
                                                0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Icon(
                                              Icons.device_thermostat_rounded,
                                              color: primaryBlue,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Flexible(
                                    flex: 1,
                                    child: Container(
                                      constraints: BoxConstraints(
                                        minWidth: 80,
                                        maxWidth: 120,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient:
                                            _isConnected
                                                ? const LinearGradient(
                                                  colors: [
                                                    primaryBlue,
                                                    primaryDark,
                                                  ],
                                                )
                                                : LinearGradient(
                                                  colors: [
                                                    Colors.grey.shade400,
                                                    Colors.grey.shade500,
                                                  ],
                                                ),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow:
                                            _isConnected
                                                ? [
                                                  BoxShadow(
                                                    color: primaryBlue
                                                        .withOpacity(0.3),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ]
                                                : null,
                                      ),
                                      child: ElevatedButton(
                                        onPressed:
                                            _isConnected
                                                ? _sendMaxTemperature
                                                : null,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          foregroundColor: Colors.white,
                                          shadowColor: Colors.transparent,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: const Text(
                                            'Kirim',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }
                          },
                        ),

                        SizedBox(
                          height:
                              MediaQuery.of(context).size.width > 600 ? 16 : 12,
                        ),

                        // Info Container
                        Container(
                          width: double.infinity,
                          constraints: BoxConstraints(minHeight: 40),
                          padding: EdgeInsets.all(
                            MediaQuery.of(context).size.width > 600 ? 12 : 10,
                          ),
                          decoration: BoxDecoration(
                            color: backgroundGrey,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Suhu maksimal saat ini: ${_maxTemperature.toStringAsFixed(1)}°C',
                                  style: TextStyle(
                                    fontSize:
                                        MediaQuery.of(context).size.width > 600
                                            ? 14
                                            : 13,
                                    color: textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Time Configuration Settings Card
              RepaintBoundary(
                child: Container(
                  width: double.infinity,
                  constraints: BoxConstraints(
                    minHeight: 200,
                    maxWidth: MediaQuery.of(context).size.width - 32,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [cardWhite, cardWhite.withOpacity(0.9)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal:
                          MediaQuery.of(context).size.width > 600 ? 24 : 16,
                      vertical:
                          MediaQuery.of(context).size.width > 600 ? 24 : 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header Row
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(
                                MediaQuery.of(context).size.width > 600
                                    ? 12
                                    : 10,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    accentTeal.withOpacity(0.1),
                                    accentTeal.withOpacity(0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.schedule_rounded,
                                color: accentTeal,
                                size:
                                    MediaQuery.of(context).size.width > 600
                                        ? 24
                                        : 20,
                              ),
                            ),
                            SizedBox(
                              width:
                                  MediaQuery.of(context).size.width > 600
                                      ? 12
                                      : 8,
                            ),
                            Expanded(
                              child: Text(
                                'Pengaturan Waktu Penyimpanan',
                                style: TextStyle(
                                  fontSize:
                                      MediaQuery.of(context).size.width > 600
                                          ? 20
                                          : 18,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(
                          height:
                              MediaQuery.of(context).size.width > 600 ? 20 : 16,
                        ),

                        // Time Input Fields - Grid Layout
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isSmallScreen = constraints.maxWidth < 400;

                            return Column(
                              children: [
                                // First row: Days and Hours
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                            width: 1,
                                          ),
                                        ),
                                        child: TextField(
                                          controller: _daysController,
                                          keyboardType: TextInputType.number,
                                          maxLength: 3,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            color: textPrimary,
                                          ),
                                          decoration: InputDecoration(
                                            labelText: 'Hari',
                                            labelStyle: TextStyle(
                                              color: textSecondary,
                                              fontWeight: FontWeight.w500,
                                              fontSize: 14,
                                            ),
                                            border: InputBorder.none,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal:
                                                      isSmallScreen ? 12 : 16,
                                                  vertical:
                                                      isSmallScreen ? 12 : 16,
                                                ),
                                            counterText: '',
                                            prefixIcon: Container(
                                              margin: const EdgeInsets.all(8),
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: accentTeal.withOpacity(
                                                  0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                Icons.calendar_today_rounded,
                                                color: accentTeal,
                                                size: 18,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                            width: 1,
                                          ),
                                        ),
                                        child: TextField(
                                          controller: _hoursController,
                                          keyboardType: TextInputType.number,
                                          maxLength: 2,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            color: textPrimary,
                                          ),
                                          decoration: InputDecoration(
                                            labelText: 'Jam (0-23)',
                                            labelStyle: TextStyle(
                                              color: textSecondary,
                                              fontWeight: FontWeight.w500,
                                              fontSize: 14,
                                            ),
                                            border: InputBorder.none,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal:
                                                      isSmallScreen ? 12 : 16,
                                                  vertical:
                                                      isSmallScreen ? 12 : 16,
                                                ),
                                            counterText: '',
                                            prefixIcon: Container(
                                              margin: const EdgeInsets.all(8),
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: primaryBlue.withOpacity(
                                                  0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                Icons.access_time_rounded,
                                                color: primaryBlue,
                                                size: 18,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                // Second row: Minutes and Seconds
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                            width: 1,
                                          ),
                                        ),
                                        child: TextField(
                                          controller: _minutesController,
                                          keyboardType: TextInputType.number,
                                          maxLength: 2,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            color: textPrimary,
                                          ),
                                          decoration: InputDecoration(
                                            labelText: 'Menit (0-59)',
                                            labelStyle: TextStyle(
                                              color: textSecondary,
                                              fontWeight: FontWeight.w500,
                                              fontSize: 14,
                                            ),
                                            border: InputBorder.none,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal:
                                                      isSmallScreen ? 12 : 16,
                                                  vertical:
                                                      isSmallScreen ? 12 : 16,
                                                ),
                                            counterText: '',
                                            prefixIcon: Container(
                                              margin: const EdgeInsets.all(8),
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: warningOrange
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                Icons.timer_rounded,
                                                color: warningOrange,
                                                size: 18,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                            width: 1,
                                          ),
                                        ),
                                        child: TextField(
                                          controller: _secondsController,
                                          keyboardType: TextInputType.number,
                                          maxLength: 2,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            color: textPrimary,
                                          ),
                                          decoration: InputDecoration(
                                            labelText: 'Detik (0-59)',
                                            labelStyle: TextStyle(
                                              color: textSecondary,
                                              fontWeight: FontWeight.w500,
                                              fontSize: 14,
                                            ),
                                            border: InputBorder.none,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal:
                                                      isSmallScreen ? 12 : 16,
                                                  vertical:
                                                      isSmallScreen ? 12 : 16,
                                                ),
                                            counterText: '',
                                            prefixIcon: Container(
                                              margin: const EdgeInsets.all(8),
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: successGreen.withOpacity(
                                                  0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                Icons.timer_10_rounded,
                                                color: successGreen,
                                                size: 18,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 16),

                        // Submit Button
                        Container(
                          width: double.infinity,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient:
                                (_isConnected && !_isTimeConfigLoading)
                                    ? LinearGradient(
                                      colors: [
                                        accentTeal,
                                        accentTeal.withOpacity(0.8),
                                      ],
                                    )
                                    : LinearGradient(
                                      colors: [
                                        Colors.grey.shade400,
                                        Colors.grey.shade500,
                                      ],
                                    ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow:
                                (_isConnected && !_isTimeConfigLoading)
                                    ? [
                                      BoxShadow(
                                        color: accentTeal.withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                    : null,
                          ),
                          child: ElevatedButton(
                            onPressed:
                                (_isConnected && !_isTimeConfigLoading)
                                    ? _sendTimeConfiguration
                                    : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child:
                                _isTimeConfigLoading
                                    ? Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        const Text(
                                          'Mengirim...',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    )
                                    : const Text(
                                      'Set Waktu Penyimpanan',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Storage Time Info Widget
                        if (_storageTimeData != null)
                          StorageTimeInfo(
                            storageData: _storageTimeData,
                            onRefresh: _loadStorageTimeData,
                          ),

                        const SizedBox(height: 12),

                        // Info Container
                        Container(
                          width: double.infinity,
                          constraints: BoxConstraints(minHeight: 40),
                          padding: EdgeInsets.all(
                            MediaQuery.of(context).size.width > 600 ? 12 : 10,
                          ),
                          decoration: BoxDecoration(
                            color: backgroundGrey,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Waktu penyimpanan saat ini: ${_storageDays}d ${_storageHours}h ${_storageMinutes}m ${_storageSeconds}s',
                                  style: TextStyle(
                                    fontSize:
                                        MediaQuery.of(context).size.width > 600
                                            ? 14
                                            : 13,
                                    color: textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to get appropriate temperature icon
  IconData _getTemperatureIcon(double temperature) {
    if (temperature > _maxTemperature) {
      return Icons.local_fire_department_rounded;
    } else if (temperature > (_maxTemperature * 0.8)) {
      return Icons.device_thermostat_rounded;
    } else if (temperature > 15) {
      return Icons.thermostat_rounded;
    } else {
      return Icons.ac_unit_rounded;
    }
  }

  // Popup management variables
  bool _isTemperaturePopupShowing = false;
  bool _isTimePopupShowing = false;

  // Method to check temperature threshold and trigger alerts
  void _checkTemperatureThreshold(double currentTemp) {
    print(
      '🌡️ Checking temperature threshold: Current=$currentTemp°C, Max=$_maxTemperature°C',
    );

    if (currentTemp > _maxTemperature) {
      print('🚨 Temperature threshold exceeded! Triggering alert...');

      try {
        // Trigger notification and vibration
        _notificationService.showTemperatureAlert(
          currentTemperature: currentTemp,
          maxTemperature: _maxTemperature,
        );

        // Show in-app alert as well
        _showInAppAlert(currentTemp);

        print('✅ Temperature alert triggered successfully');
      } catch (e) {
        print('❌ Error triggering temperature alert: $e');
        // Still show in-app alert even if notification fails
        _showInAppAlert(currentTemp);
      }
    } else {
      print('✅ Temperature within safe limits');
    }
  }

  // Method to handle ESP32 time notification
  void _handleTimeNotification(String payload) {
    print('🕒 Handling ESP32 time notification: $payload');

    try {
      // Parse JSON payload
      final Map<String, dynamic> data = json.decode(payload);

      // Check if message is true
      if (data.containsKey('message') && data['message'] == true) {
        print('🚨 ESP32 time notification triggered! Showing alert...');

        // Trigger notification, vibration, and popup
        _notificationService.showTimeNotificationAlert();

        // Show in-app popup alert
        _showTimeNotificationPopup();

        print('✅ ESP32 time notification alert triggered successfully');
      } else {
        print('ℹ️ ESP32 time notification message is false or invalid');
      }
    } catch (e) {
      print('❌ Error parsing ESP32 time notification payload: $e');
      // Still show popup even if JSON parsing fails
      _showTimeNotificationPopup();
    }
  }

  void _showInAppAlert(double currentTemp) {
    if (!mounted) return;

    // Check if temperature popup is already showing
    if (_isTemperaturePopupShowing) return;

    _showEnhancedPopup(
      type: PopupType.temperature,
      title: 'Peringatan Suhu Tinggi!',
      message:
          'Suhu telah mencapai/melampaui batas maksimum ${currentTemp.toStringAsFixed(1)}°C',
      subMessage: 'Segera periksa perangkat',
      icon: Icons.thermostat,
      primaryColor: dangerRed,
      primaryButtonText: 'Tutup',
      onPrimaryPressed: () {
        Navigator.of(context).pop();
      },
    );
  }

  void _showTimeNotificationPopup() {
    if (!mounted) return;

    // Check priority: temperature popup has higher priority
    if (_isTemperaturePopupShowing) {
      // Queue time popup to show after temperature popup is dismissed
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_isTemperaturePopupShowing) {
          _showTimeNotificationPopup();
        }
      });
      return;
    }

    // Check if time popup is already showing
    if (_isTimePopupShowing) return;

    _showEnhancedPopup(
      type: PopupType.time,
      title: 'Waktu Penyimpanan Peringatan',
      message: 'Waktu penyimpanan telah melebihi batas maksimum',
      subMessage: 'Data mungkin tidak tersimpan dengan optimal',
      icon: Icons.hourglass_empty,
      primaryColor: warningOrange,
      primaryButtonText: 'OK',
      onPrimaryPressed: () {
        Navigator.of(context).pop();
      },
    );
  }

  // Enhanced popup widget with animations and auto-dismiss
  void _showEnhancedPopup({
    required PopupType type,
    required String title,
    required String message,
    required String subMessage,
    required IconData icon,
    required Color primaryColor,
    required String primaryButtonText,
    String? secondaryButtonText,
    required VoidCallback onPrimaryPressed,
    VoidCallback? onSecondaryPressed,
  }) {
    if (!mounted) return;

    // Set popup state
    if (type == PopupType.temperature) {
      _isTemperaturePopupShowing = true;
    } else {
      _isTimePopupShowing = true;
    }

    // Auto-dismiss timer
    Timer? autoDismissTimer;
    bool isManuallyDismissed = false;

    void dismissPopup() {
      if (!isManuallyDismissed && mounted) {
        isManuallyDismissed = true;
        autoDismissTimer?.cancel();
        Navigator.of(context).pop();
      }
    }

    // Set auto-dismiss timer for 5 seconds
    autoDismissTimer = Timer(const Duration(seconds: 5), () {
      if (!isManuallyDismissed && mounted) {
        dismissPopup();
      }
    });

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Container(); // Placeholder
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
            ),
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              contentPadding: const EdgeInsets.all(16),
              content: SizedBox(
                width: 280,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header with icon and title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(icon, color: primaryColor, size: 24),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Main message
                    Text(
                      message,
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                        height: 1.3,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),

                    // Sub message
                    Text(
                      subMessage,
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 11,
                        color: textSecondary,
                        height: 1.2,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),

                    // Action buttons
                    Row(
                      children: [
                        if (secondaryButtonText != null &&
                            onSecondaryPressed != null) ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                isManuallyDismissed = true;
                                autoDismissTimer?.cancel();
                                onSecondaryPressed();
                                // Reset popup state
                                if (type == PopupType.temperature) {
                                  _isTemperaturePopupShowing = false;
                                } else {
                                  _isTimePopupShowing = false;
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: primaryColor),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                minimumSize: const Size(0, 36),
                              ),
                              child: Text(
                                secondaryButtonText,
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: primaryColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              isManuallyDismissed = true;
                              autoDismissTimer?.cancel();
                              onPrimaryPressed();
                              // Reset popup state
                              if (type == PopupType.temperature) {
                                _isTemperaturePopupShowing = false;
                              } else {
                                _isTimePopupShowing = false;
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              elevation: 2,
                              minimumSize: const Size(0, 36),
                            ),
                            child: Text(
                              primaryButtonText,
                              style: const TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ).then((_) {
      // Reset popup state when dialog is dismissed
      if (type == PopupType.temperature) {
        _isTemperaturePopupShowing = false;
      } else {
        _isTimePopupShowing = false;
      }
      autoDismissTimer?.cancel();
    });
  }

  // Database saving methods
  Future<void> _saveSensorDataToDatabase({
    double? temperature,
    double? latitude,
    double? longitude,
  }) async {
    try {
      // Gunakan device ID dari parameter device jika tersedia
      final deviceId = widget.device?.deviceId ?? 'esp32_cooler_box';

      await _databaseService.saveSensorData(
        deviceId: deviceId,
        temperature: temperature ?? _currentTemperature,
        latitude: latitude,
        longitude: longitude,
      );

      print(
        '📊 Sensor data saved to database successfully for device: $deviceId',
      );
    } catch (e) {
      print('❌ Failed to save sensor data to database: $e');
    }
  }
}
