import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'package:flutter/foundation.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  late SupabaseClient _supabase;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await Supabase.initialize(
        url: SupabaseConfig.supabaseUrl,
        anonKey: SupabaseConfig.supabaseAnonKey,
      );
      _supabase = Supabase.instance.client;
      _isInitialized = true;
      debugPrint('DatabaseService: Initialized successfully');
    } catch (e) {
      debugPrint('DatabaseService: Initialization failed: $e');
      rethrow;
    }
  }

  Future<bool> saveSensorData({
    required String deviceId,
    double? temperature,
    double? latitude,
    double? longitude,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final data = {
        'device_id': deviceId, // Keep as string, not UUID
        'temperature': temperature,
        'latitude': latitude,
        'longitude': longitude,
        'recorded_at': DateTime.now().toIso8601String(),
      };

      // Remove null values
      data.removeWhere((key, value) => value == null);

      final response = await _supabase
          .from('sensor_data')
          .insert(data);

      debugPrint('DatabaseService: Sensor data saved successfully');
      return true;
    } catch (e) {
      debugPrint('DatabaseService: Failed to save sensor data: $e');
      return false;
    }
  }

  Future<bool> saveDeviceSettings({
    required String deviceId,
    required String userId,
    required double maxTemperature,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final data = {
        'device_id': deviceId,
        'user_id': userId,
        'max_temperature': maxTemperature,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Use upsert to update if exists, insert if not
      final response = await _supabase
          .from('device_settings')
          .upsert(data, onConflict: 'device_id,user_id');

      debugPrint('DatabaseService: Device settings saved successfully');
      return true;
    } catch (e) {
      debugPrint('DatabaseService: Failed to save device settings: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getDeviceSettings({
    required String deviceId,
    required String userId,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final response = await _supabase
          .from('device_settings')
          .select()
          .eq('device_id', deviceId)
          .eq('user_id', userId)
          .limit(1);

      if (response.isNotEmpty) {
        return response.first;
      }
      return null;
    } catch (e) {
      debugPrint('DatabaseService: Failed to get device settings: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getSensorData({
    String? deviceId,
    int limit = 100,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      var query = _supabase
          .from('sensor_data')
          .select()
          .order('recorded_at', ascending: false)
          .limit(limit);

      if (deviceId != null) {
        query = _supabase
            .from('sensor_data')
            .select()
            .eq('device_id', deviceId)
            .order('recorded_at', ascending: false)
            .limit(limit);
      }

      final response = await query;
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('DatabaseService: Failed to get sensor data: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getLatestSensorData(String deviceId) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final response = await _supabase
          .from('sensor_data')
          .select()
          .eq('device_id', deviceId)
          .order('recorded_at', ascending: false)
          .limit(1);

      if (response.isNotEmpty) {
        return response.first;
      }
      return null;
    } catch (e) {
      debugPrint('DatabaseService: Failed to get latest sensor data: $e');
      return null;
    }
  }

  Future<bool> saveStorageTimeSettings({
    required String deviceId,
    required String userId,
    required int days,
    required int hours,
    required int minutes,
    required int seconds,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final data = {
        'device_id': deviceId,
        'user_id': userId,
        'days': days,
        'hours': hours,
        'minutes': minutes,
        'seconds': seconds,
        'start_time': (startTime ?? DateTime.now()).toIso8601String(),
        'end_time': endTime?.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Coba upsert terlebih dahulu
      try {
        final response = await _supabase
            .from('storage_time_settings')
            .upsert(data, onConflict: 'device_id,user_id')
            .select();

        debugPrint('DatabaseService: Upsert response length: ${response.length}');
        debugPrint('DatabaseService: Storage time settings saved successfully (upsert)');
        return true;
      } catch (upsertError) {
        debugPrint('DatabaseService: Upsert failed, attempting fallback: $upsertError');
        // Fallback: cek apakah record ada, lalu update atau insert manual
        try {
          final existing = await _supabase
              .from('storage_time_settings')
              .select('id')
              .eq('device_id', deviceId)
              .eq('user_id', userId)
              .limit(1);

          if (existing is List && existing.isNotEmpty && existing.first is Map && (existing.first as Map).containsKey('id')) {
            final recordId = (existing.first as Map)['id'];
            await _supabase
                .from('storage_time_settings')
                .update(data)
                .eq('id', recordId);
            debugPrint('DatabaseService: Fallback update succeeded for id=$recordId');
          } else {
            await _supabase
                .from('storage_time_settings')
                .insert(data);
            debugPrint('DatabaseService: Fallback insert succeeded');
          }
          return true;
        } catch (fallbackError) {
          debugPrint('DatabaseService: Fallback save failed: $fallbackError');
          return false;
        }
      }
    } catch (e) {
      debugPrint('DatabaseService: Unexpected error saving storage time settings: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getStorageTimeSettings({
    required String deviceId,
    required String userId,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final response = await _supabase
          .from('storage_time_settings')
          .select()
          .eq('device_id', deviceId)
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1);

      if (response.isNotEmpty) {
        return response.first;
      }
      return null;
    } catch (e) {
      debugPrint('DatabaseService: Failed to get storage time settings: $e');
      return null;
    }
  }
}