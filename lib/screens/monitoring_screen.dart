import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../services/mqtt_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/database_service.dart';
import '../widgets/storage_time_info.dart';
import '../models/device.dart';
import 'package:flutter/foundation.dart';
import '../theme/app_theme.dart';
import '../theme/theme_notifier.dart';
import '../main.dart' show themeNotifier;

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

  // Device data state — true hanya setelah data MQTT dari alat diterima
  bool _hasReceivedDeviceData = false;

  // Navigation state
  LatLng? _destinationLocation;
  String? _destinationName;
  final TextEditingController _destinationController = TextEditingController();
  List<LatLng> _routePoints = [];
  bool _isLoadingRoute = false;
  bool _showRoute = false;
  String? _routeInfo;

  // Time configuration state
  bool _isTimeConfigLoading = false;
  int _storageDays = 1;
  int _storageHours = 0;
  int _storageMinutes = 0;
  int _storageSeconds = 0;

  // Storage time data from database
  Map<String, dynamic>? _storageTimeData;

  // Modern color scheme — dark mode aware
  static const Color accentTeal = Color(0xFF00BCD4);
  static const Color warningOrange = Color(0xFFFF9800);

  bool get _isDark => themeNotifier.isDarkMode;

  Color get primaryBlue  => _isDark ? AppTheme.darkPrimaryBlue  : AppTheme.lightPrimaryBlue;
  Color get primaryDark  => _isDark ? AppTheme.darkPrimaryDark  : AppTheme.lightPrimaryDark;
  Color get dangerRed    => AppTheme.dangerRed;
  Color get successGreen => AppTheme.successGreen;
  Color get backgroundGrey => _isDark ? AppTheme.darkBackground : const Color(0xFFF5F7FA);
  Color get cardWhite    => _isDark ? AppTheme.darkCard          : Colors.white;
  Color get cardElevated => _isDark ? AppTheme.darkCardElevated  : Colors.white;
  Color get textPrimary  => _isDark ? AppTheme.darkTextPrimary   : const Color(0xFF2C3E50);
  Color get textSecondary=> _isDark ? AppTheme.darkTextSecondary : const Color(0xFF7B8794);
  Color get inputFill    => _isDark ? AppTheme.darkInputFill     : Colors.white;
  Color get inputBorder  => _isDark ? AppTheme.darkDivider       : Colors.grey.shade300;

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
    _destinationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        debugPrint('App resumed - checking MQTT connection');
        _mqttService.onAppResumed();
        // Update UI state after a short delay to allow reconnection
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _updateConnectionStatus();
          }
        });
        break;
      case AppLifecycleState.paused:
        debugPrint('App paused');
        _mqttService.onAppPaused();
        break;
      case AppLifecycleState.inactive:
        debugPrint('App inactive');
        break;
      case AppLifecycleState.detached:
        debugPrint('App detached');
        break;
      case AppLifecycleState.hidden:
        debugPrint('App hidden');
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
      debugPrint('✅ NotificationService initialized in MonitoringScreen');
    } catch (e) {
      debugPrint('❌ Error initializing NotificationService: $e');
    }

    try {
      await _databaseService.initialize();
      debugPrint('✅ DatabaseService initialized in MonitoringScreen');
    } catch (e) {
      debugPrint('❌ Error initializing DatabaseService: $e');
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

        debugPrint(
          '✅ Latest sensor data loaded: Temp=${_currentTemperature}°C, Location=${_currentLocation.latitude},${_currentLocation.longitude}',
        );
      } else {
        debugPrint('ℹ️ No previous sensor data found in database');
      }

      // Load device settings separately
      await _loadDeviceSettings();
    } catch (e) {
      debugPrint('❌ Error loading latest sensor data: $e');
    }
  }

  Future<void> _loadDeviceSettings() async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        debugPrint('❌ Cannot load device settings: User not authenticated');
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

        debugPrint('✅ Device settings loaded: MaxTemp=${_maxTemperature}°C');
      } else {
        debugPrint('ℹ️ No device settings found, using default values');
        // Set default value and update controller if no settings found
        setState(() {
          _maxTemperature = 30.0;
          _maxTempController.text = _maxTemperature.toString();
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading device settings: $e');
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
        debugPrint('❌ Cannot save device settings: User not authenticated');
        return;
      }

      // Gunakan device ID dari parameter device jika tersedia
      final deviceId = widget.device?.deviceId ?? 'esp32_cooler_box';

      await _databaseService.saveDeviceSettings(
        deviceId: deviceId,
        userId: user.id,
        maxTemperature: _maxTemperature,
      );

      debugPrint(
        '✅ Device settings saved for device $deviceId: MaxTemp=${_maxTemperature}°C',
      );
    } catch (e) {
      debugPrint('❌ Error saving device settings: $e');
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
            debugPrint(
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

    debugPrint('Received MQTT message - Topic: $topic, Payload: $payload');

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

        // Tandai bahwa data dari alat sudah diterima
        if (!_hasReceivedDeviceData && mounted) {
          setState(() {
            _hasReceivedDeviceData = true;
          });
        }

        double? temperature;
        double? latitude;
        double? longitude;
        double? setpoint;

        // Extract device ID (for logging/debugging)
        if (data.containsKey('deviceid')) {
          debugPrint('Received data from device: ${data['deviceid']}');
        }

        // Extract temperature
        if (data.containsKey('temp')) {
          temperature = (data['temp'] as num?)?.toDouble() ?? 0.0;
          debugPrint('Updating temperature to: $temperature°C');
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
            debugPrint('Updating location to: $latitude, $longitude');
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
            debugPrint('Received current setpoint from ESP32: $setpoint°C');
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
        debugPrint('Error parsing JSON payload: $e');
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
      debugPrint('Updating temperature to: $temperature°C (legacy format)');
      setState(() {
        _currentTemperature = temperature;
        _hasReceivedDeviceData = true;
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
          debugPrint('Updating location to: $lat, $lng (legacy format)');
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
      debugPrint(
        'Map location updated to: ${_currentLocation.latitude}, ${_currentLocation.longitude}',
      );
    } catch (e) {
      debugPrint('Error updating map location: $e');
    }
  }

  void _sendMaxTemperature() {
    debugPrint('DEBUG: _sendMaxTemperature called');
    debugPrint('DEBUG: Input text: "${_maxTempController.text}"');

    final maxTemp = double.tryParse(_maxTempController.text);
    debugPrint('DEBUG: Parsed temperature: $maxTemp');

    if (maxTemp != null) {
      debugPrint('DEBUG: Attempting to publish max temperature: $maxTemp');
      debugPrint('DEBUG: MQTT service connected: ${_mqttService.isConnected}');

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
        debugPrint('DEBUG: UI state updated with max temperature: $_maxTemperature');

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
        debugPrint('DEBUG: Success snackbar shown');
      }
    } else {
      debugPrint('DEBUG: Invalid temperature input: "${_maxTempController.text}"');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Masukkan nilai suhu yang valid'),
            backgroundColor: Colors.red,
          ),
        );
        debugPrint('DEBUG: Error snackbar shown');
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
        debugPrint('❌ User belum login, tidak dapat memuat data waktu penyimpanan');
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
        debugPrint('✅ Storage time data loaded: $data');
      }
    } catch (e) {
      debugPrint('❌ Error loading storage time data: $e');
    }
  }

  void _sendTimeConfiguration() async {
    debugPrint('DEBUG: _sendTimeConfiguration called');

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

      debugPrint(
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

      debugPrint('DEBUG: Time configuration payload: ${jsonEncode(payload)}');
      debugPrint('DEBUG: MQTT service connected: ${_mqttService.isConnected}');

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

        debugPrint('✅ Storage time settings saved to database');
      } catch (dbError) {
        debugPrint('❌ Error saving storage time settings: $dbError');
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
        debugPrint('DEBUG: UI state updated with time configuration');
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
        debugPrint('DEBUG: Success snackbar shown for time configuration');
      }
    } catch (e) {
      debugPrint('DEBUG: Error in time configuration: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        debugPrint('DEBUG: Error snackbar shown for time configuration');
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


  // ─────────────── NAVIGATION METHODS ───────────────

  /// Tampilkan dialog input tujuan pengiriman
  void _showDestinationDialog() {
    _destinationController.clear();
    showDialog(
      context: context,
      builder: (ctx) {
        bool isSearching = false;
        List<Map<String, dynamic>> suggestions = [];

        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.flag_rounded, color: Color(0xFF2563EB)),
                  SizedBox(width: 8),
                  Text(
                    'Tujuan Pengiriman',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Titik awal: GPS Alat (CoolerBox)',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _destinationController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Cari alamat tujuan...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: isSearching
                            ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (val) async {
                        if (val.trim().isEmpty) return;
                        setStateDialog(() => isSearching = true);
                        final results = await _geocodeSearch(val.trim());
                        setStateDialog(() {
                          isSearching = false;
                          suggestions = results;
                        });
                      },
                    ),
                    if (suggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Pilih lokasi:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: suggestions.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final s = suggestions[i];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.location_on, size: 18, color: Color(0xFF2563EB)),
                              title: Text(
                                s['displayName'],
                                style: const TextStyle(fontSize: 13),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                _setDestinationAndRoute(
                                  LatLng(s['lat'], s['lng']),
                                  s['displayName'],
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Batal'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final val = _destinationController.text.trim();
                    if (val.isEmpty) return;
                    setStateDialog(() => isSearching = true);
                    final results = await _geocodeSearch(val);
                    setStateDialog(() {
                      isSearching = false;
                      suggestions = results;
                    });
                  },
                  icon: const Icon(Icons.search, size: 16),
                  label: const Text('Cari'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Geocode nama tempat → koordinat via Nominatim (OpenStreetMap, gratis)
  Future<List<Map<String, dynamic>>> _geocodeSearch(String query) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
            '?q=${Uri.encodeComponent(query)}'
            '&format=json&limit=5&addressdetails=1',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'CoolerBoxApp/1.0'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.map((item) {
          return {
            'lat': double.parse(item['lat']),
            'lng': double.parse(item['lon']),
            'displayName': item['display_name'] as String,
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('Geocode error: $e');
    }
    return [];
  }

  /// Set tujuan dan langsung fetch rute dari alat ke tujuan
  Future<void> _setDestinationAndRoute(LatLng destination, String name) async {
    setState(() {
      _destinationLocation = destination;
      _destinationName = name;
    });
    // Titik awal = GPS alat (_currentLocation), bukan GPS HP
    await _fetchRoute(_currentLocation, destination);
  }

  /// Fetch rute dari OSRM (OpenStreetMap Routing Machine) - gratis, no API key
  /// from = GPS alat, to = tujuan pengiriman
  Future<void> _fetchRoute(LatLng from, LatLng to) async {
    setState(() {
      _isLoadingRoute = true;
      _routePoints = [];
      _routeInfo = null;
    });

    try {
      final url =
          'https://router.project-osrm.org/route/v1/driving/'
          '${from.longitude},${from.latitude};'
          '${to.longitude},${to.latitude}'
          '?overview=full&geometries=geojson&steps=false';

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 'Ok' && data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final coords = route['geometry']['coordinates'] as List;
          final distanceM = (route['distance'] as num).toDouble();
          final durationS = (route['duration'] as num).toDouble();

          final points = coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();

          // Format distance & duration
          final distStr = distanceM >= 1000
              ? '${(distanceM / 1000).toStringAsFixed(1)} km'
              : '${distanceM.round()} m';
          final durationMin = (durationS / 60).ceil();
          String durStr;
          if (durationMin >= 60) {
            final h = durationMin ~/ 60;
            final m = durationMin % 60;
            durStr = m > 0 ? '$h jam $m mnt' : '$h jam';
          } else {
            durStr = '$durationMin menit';
          }

          // Estimasi waktu tiba (sekarang + durasi)
          final now = DateTime.now();
          final eta = now.add(Duration(minutes: durationMin));
          final etaStr = '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';

          setState(() {
            _routePoints = points;
            _showRoute = true;
            _routeInfo = '$distStr • $durStr • Tiba ~$etaStr';
          });

          // Fit map to show both alat and destination
          _fitMapToBounds(from, to);
        }
      }
    } catch (e) {
      debugPrint('Error fetching route: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Gagal memuat rute. Periksa koneksi internet.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRoute = false;
        });
      }
    }
  }

  /// Fit peta agar menampilkan kedua titik sekaligus
  void _fitMapToBounds(LatLng a, LatLng b) {
    final minLat = math.min(a.latitude, b.latitude);
    final maxLat = math.max(a.latitude, b.latitude);
    final minLng = math.min(a.longitude, b.longitude);
    final maxLng = math.max(a.longitude, b.longitude);

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    // Hitung zoom level berdasarkan jarak
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = math.max(latDiff, lngDiff);

    double zoom = 13.0;
    if (maxDiff > 0.5) zoom = 10.0;
    else if (maxDiff > 0.2) zoom = 11.0;
    else if (maxDiff > 0.1) zoom = 12.0;
    else if (maxDiff > 0.05) zoom = 13.0;
    else zoom = 14.0;

    _mapController.move(LatLng(centerLat, centerLng), zoom);
  }

  /// Buka Google Maps dengan:
  /// origin = GPS alat (cooler box), destination = tujuan pengiriman
  Future<void> _openExternalNavigation() async {
    if (_destinationLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tentukan tujuan pengiriman terlebih dahulu.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final originLat = _currentLocation.latitude;
    final originLng = _currentLocation.longitude;
    final destLat = _destinationLocation!.latitude;
    final destLng = _destinationLocation!.longitude;

    // Google Maps: dari GPS alat → ke tujuan
    final googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
          '&origin=$originLat,$originLng'
          '&destination=$destLat,$destLng'
          '&travelmode=driving',
    );

    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    } else {
      final geoUri = Uri.parse('geo:$destLat,$destLng?q=$destLat,$destLng');
      if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak dapat membuka aplikasi Maps.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Clear/hapus rute dan tujuan dari peta
  void _clearRoute() {
    setState(() {
      _routePoints = [];
      _showRoute = false;
      _routeInfo = null;
      _destinationLocation = null;
      _destinationName = null;
    });
    _mapController.move(_currentLocation, 15.0);
  }

  /// Widget placeholder saat menunggu data dari alat
  Widget _buildWaitingDeviceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 52,
            height: 52,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFFF59E0B),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Menunggu Data dari Alat',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF92400E),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isConnected
                ? 'Terhubung ke server. Menunggu alat mengirimkan data...'
                : 'Belum terhubung ke server MQTT.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFB45309),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildWaitingDot(0),
              const SizedBox(width: 6),
              _buildWaitingDot(150),
              const SizedBox(width: 6),
              _buildWaitingDot(300),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingDot(int delayMs) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      builder: (_, val, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withValues(alpha: val),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Widget _buildMapWidget() {
    if (_mapLoadError) {
      return Container(
        height: 250,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: inputBorder),
          color: inputFill,
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
        border: Border.all(color: inputBorder),
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
            // Route polyline layer
            if (_showRoute && _routePoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    strokeWidth: 5.0,
                    color: primaryBlue,
                    borderStrokeWidth: 2.0,
                    borderColor: Colors.white,
                  ),
                ],
              ),
            // Marker layer
            MarkerLayer(
              markers: [
                // Device marker (merah)
                Marker(
                  point: _currentLocation,
                  width: 44,
                  height: 44,
                  child: Container(
                    decoration: BoxDecoration(
                      color: dangerRed,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.device_thermostat,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
                // Destination marker (hijau) — tampil jika tujuan sudah ditentukan
                if (_destinationLocation != null && _showRoute)
                  Marker(
                    point: _destinationLocation!,
                    width: 48,
                    height: 56,
                    child: Column(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: successGreen,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: successGreen.withValues(alpha: 0.4),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.flag_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        Container(
                          width: 2,
                          height: 12,
                          color: successGreen,
                        ),
                      ],
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
    return ListenableBuilder(
      listenable: themeNotifier,
      builder: (context, _) => Scaffold(
        backgroundColor: backgroundGrey,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: _isDark ? AppTheme.darkSurface : primaryBlue,
          foregroundColor: _isDark ? AppTheme.darkTextPrimary : Colors.white,
          title: Text(
            widget.device != null
                ? 'Monitoring ${widget.device!.name}'
                : 'Monitoring Suhu',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 20,
              color: cardWhite,
            ),
          ),
          flexibleSpace: _isDark ? null : Container(
            decoration: BoxDecoration(
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
                // Status Bar — 3 kondisi
                Builder(builder: (context) {
                  final Color barColor;
                  final IconData barIcon;
                  final String barText;

                  if (!_isConnected) {
                    barColor = dangerRed;
                    barIcon = Icons.wifi_off;
                    barText = 'Tidak Terhubung';
                  } else if (!_hasReceivedDeviceData) {
                    barColor = const Color(0xFFF59E0B); // amber
                    barIcon = Icons.hourglass_top_rounded;
                    barText = 'Terhubung — Menunggu Data Alat...';
                  } else {
                    barColor = successGreen;
                    barIcon = Icons.wifi;
                    barText = 'Terhubung';
                  }

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: barColor.withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Spinner saat menunggu, ikon biasa jika tidak
                        if (_isConnected && !_hasReceivedDeviceData)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        else
                          Icon(barIcon, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          barText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                // Temperature Display Card — hanya tampil setelah data alat diterima
                if (!_hasReceivedDeviceData)
                  _buildWaitingDeviceCard()
                else
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
                                colors: [cardWhite, cardElevated],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha:0.08),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha:0.04),
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
                                                                .withValues(alpha:0.3),
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
                                              dangerRed.withValues(alpha:0.1),
                                              dangerRed.withValues(alpha:0.05),
                                            ]
                                                : _currentTemperature >
                                                (_maxTemperature * 0.8)
                                                ? [
                                              warningOrange.withValues(alpha:
                                              0.1,
                                              ),
                                              warningOrange.withValues(alpha:
                                              0.05,
                                              ),
                                            ]
                                                : [
                                              primaryBlue.withValues(alpha:0.1),
                                              primaryBlue.withValues(alpha:0.05),
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
                                                .withValues(alpha:0.2),
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
                                            dangerRed.withValues(alpha:0.1),
                                            dangerRed.withValues(alpha:0.05),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: dangerRed.withValues(alpha:0.3),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: dangerRed.withValues(alpha:0.2),
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

                // Maps Card — hanya tampil setelah data alat diterima
                if (_hasReceivedDeviceData)
                  RepaintBoundary(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [cardWhite, cardElevated],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha:0.08),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha:0.04),
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
                                        accentTeal.withValues(alpha:0.1),
                                        accentTeal.withValues(alpha:0.05),
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
                                  Expanded(
                                    child: Text(
                                      'Koordinat: ${_currentLocation.latitude.toStringAsFixed(6)}, ${_currentLocation.longitude.toStringAsFixed(6)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Destination info row
                            if (_destinationName != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: successGreen.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: successGreen.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.flag_rounded, size: 15, color: successGreen),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _destinationName!,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: successGreen,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: _clearRoute,
                                        child: Icon(Icons.close, size: 15, color: successGreen),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // Route info: jarak, waktu, ETA
                            if (_routeInfo != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: primaryBlue.withValues(alpha: 0.07),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: primaryBlue.withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.directions_car, size: 15, color: primaryBlue),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _routeInfo!,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: primaryBlue,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // Navigation buttons
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                // Tombol Atur Tujuan / Hapus Rute
                                Expanded(
                                  child: _isLoadingRoute
                                      ? Container(
                                    height: 44,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: Colors.grey.shade200,
                                    ),
                                    child: const Center(
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                          SizedBox(width: 8),
                                          Text('Memuat rute...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                        ],
                                      ),
                                    ),
                                  )
                                      : ElevatedButton.icon(
                                    onPressed: _showRoute ? _clearRoute : _showDestinationDialog,
                                    icon: Icon(
                                      _showRoute ? Icons.close : Icons.add_location_alt_rounded,
                                      size: 17,
                                    ),
                                    label: Text(
                                      _showRoute ? 'Hapus Rute' : 'Atur Tujuan',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _showRoute
                                          ? Colors.grey.shade600
                                          : primaryBlue,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Tombol Buka Google Maps (hanya aktif jika tujuan sudah ada)
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _destinationLocation != null
                                        ? _openExternalNavigation
                                        : null,
                                    icon: const Icon(Icons.navigation_rounded, size: 17),
                                    label: const Text(
                                      'Buka Maps',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: successGreen,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: Colors.grey.shade300,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(vertical: 10),
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
                        colors: [cardWhite, cardElevated],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha:0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha:0.04),
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
                                      warningOrange.withValues(alpha:0.1),
                                      warningOrange.withValues(alpha:0.05),
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
                                        color: inputFill,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: inputBorder,
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
                                              color: primaryBlue.withValues(alpha:0.1),
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
                                            ? LinearGradient(
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
                                                .withValues(alpha:0.3),
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
                                          color: inputFill,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: inputBorder,
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
                                                color: primaryBlue.withValues(alpha:
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
                                              ? LinearGradient(
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
                                                  .withValues(alpha:0.3),
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
                        colors: [cardWhite, cardElevated],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha:0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha:0.04),
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
                                      accentTeal.withValues(alpha:0.1),
                                      accentTeal.withValues(alpha:0.05),
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
                                            color: inputFill,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: inputBorder,
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
                                                  color: accentTeal.withValues(alpha:
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
                                            color: inputFill,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: inputBorder,
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
                                                  color: primaryBlue.withValues(alpha:
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
                                            color: inputFill,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: inputBorder,
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
                                                      .withValues(alpha:0.1),
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
                                            color: inputFill,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: inputBorder,
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
                                                  color: successGreen.withValues(alpha:
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
                                  accentTeal.withValues(alpha:0.8),
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
                                  color: accentTeal.withValues(alpha:0.3),
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
    debugPrint(
      '🌡️ Checking temperature threshold: Current=$currentTemp°C, Max=$_maxTemperature°C',
    );

    if (currentTemp > _maxTemperature) {
      debugPrint('🚨 Temperature threshold exceeded! Triggering alert...');

      try {
        // Trigger notification and vibration
        _notificationService.showTemperatureAlert(
          currentTemperature: currentTemp,
          maxTemperature: _maxTemperature,
        );

        // Show in-app alert as well
        _showInAppAlert(currentTemp);

        debugPrint('✅ Temperature alert triggered successfully');
      } catch (e) {
        debugPrint('❌ Error triggering temperature alert: $e');
        // Still show in-app alert even if notification fails
        _showInAppAlert(currentTemp);
      }
    } else {
      debugPrint('✅ Temperature within safe limits');
    }
  }

  // Method to handle ESP32 time notification
  void _handleTimeNotification(String payload) {
    debugPrint('🕒 Handling ESP32 time notification: $payload');

    try {
      // Parse JSON payload
      final Map<String, dynamic> data = json.decode(payload);

      // Check if message is true
      if (data.containsKey('message') && data['message'] == true) {
        debugPrint('🚨 ESP32 time notification triggered! Showing alert...');

        // Trigger notification, vibration, and popup
        _notificationService.showTimeNotificationAlert();

        // Show in-app popup alert
        _showTimeNotificationPopup();

        debugPrint('✅ ESP32 time notification alert triggered successfully');
      } else {
        debugPrint('ℹ️ ESP32 time notification message is false or invalid');
      }
    } catch (e) {
      debugPrint('❌ Error parsing ESP32 time notification payload: $e');
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
                            color: primaryColor.withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(icon, color: primaryColor, size: 24),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
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
                      style: TextStyle(
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
                      style: TextStyle(
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

      debugPrint(
        '📊 Sensor data saved to database successfully for device: $deviceId',
      );
    } catch (e) {
      debugPrint('❌ Failed to save sensor data to database: $e');
    }
  }
}