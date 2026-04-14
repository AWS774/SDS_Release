import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/device.dart';
import 'package:flutter/foundation.dart';

class DeviceService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Initialize Supabase connection
  Future<void> initialize() async {
    try {
      await _supabase.auth.currentUser;
      debugPrint('✅ DeviceService: Supabase initialized');
    } catch (e) {
      debugPrint('❌ DeviceService: Supabase initialization failed: $e');
      rethrow;
    }
  }

  // Check if Supabase is initialized
  bool get isInitialized {
    return _supabase.auth.currentUser != null;
  }

  // Register new device
  Future<Device?> registerDevice(Device device) async {
    try {
      if (!isInitialized) {
        await initialize();
      }

      final response = await _supabase
          .from('devices')
          .insert(device.toMap())
          .select()
          .single();

      debugPrint('✅ Device registered successfully: ${device.name}');
      return Device.fromMap(response, response['id'].toString());
    } on PostgrestException catch (error) {
      debugPrint('❌ DeviceService: Database error registering device: ${error.message}');
      return null;
    } catch (e) {
      debugPrint('❌ DeviceService: Error registering device: $e');
      return null;
    }
  }

  // Get all devices for current user
  Future<List<Device>> getUserDevices() async {
    try {
      if (!isInitialized) {
        await initialize();
      }

      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        debugPrint('❌ DeviceService: No user logged in');
        return [];
      }

      final response = await _supabase
          .from('devices')
          .select()
          .eq('user_id', currentUser.id)
          .order('created_at', ascending: false);

      final devices = response.map((data) {
        return Device.fromMap(data, data['id'].toString());
      }).toList();

      debugPrint('✅ DeviceService: Retrieved ${devices.length} devices for user');
      return devices;
    } on PostgrestException catch (error) {
      debugPrint('❌ DeviceService: Database error getting devices: ${error.message}');
      return [];
    } catch (e) {
      debugPrint('❌ DeviceService: Error getting devices: $e');
      return [];
    }
  }

  // Get active devices for current user
  Future<List<Device>> getActiveDevices() async {
    try {
      if (!isInitialized) {
        await initialize();
      }

      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        debugPrint('❌ DeviceService: No user logged in');
        return [];
      }

      final response = await _supabase
          .from('devices')
          .select()
          .eq('user_id', currentUser.id)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      final devices = response.map((data) {
        return Device.fromMap(data, data['id'].toString());
      }).toList();

      debugPrint('✅ DeviceService: Retrieved ${devices.length} active devices for user');
      return devices;
    } on PostgrestException catch (error) {
      debugPrint('❌ DeviceService: Database error getting active devices: ${error.message}');
      return [];
    } catch (e) {
      debugPrint('❌ DeviceService: Error getting active devices: $e');
      return [];
    }
  }

  // Get device by device_id
  Future<Device?> getDeviceByDeviceId(String deviceId) async {
    try {
      if (!isInitialized) {
        await initialize();
      }

      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        debugPrint('❌ DeviceService: No user logged in');
        return null;
      }

      final response = await _supabase
          .from('devices')
          .select()
          .eq('device_id', deviceId)
          .eq('user_id', currentUser.id)
          .maybeSingle();

      if (response == null) {
        debugPrint('⚠️ DeviceService: Device not found: $deviceId');
        return null;
      }

      debugPrint('✅ DeviceService: Found device: $deviceId');
      return Device.fromMap(response, response['id'].toString());
    } on PostgrestException catch (error) {
      debugPrint('❌ DeviceService: Database error getting device: ${error.message}');
      return null;
    } catch (e) {
      debugPrint('❌ DeviceService: Error getting device: $e');
      return null;
    }
  }

  // Update device
  Future<Device?> updateDevice(Device device) async {
    try {
      if (!isInitialized) {
        await initialize();
      }

      if (device.id == null) {
        debugPrint('❌ DeviceService: Cannot update device without ID');
        return null;
      }

      final updatedDevice = device.copyWith(
        updatedAt: DateTime.now(),
      );

      final response = await _supabase
          .from('devices')
          .update(updatedDevice.toMap())
          .eq('id', device.id!)
          .select()
          .single();

      debugPrint('✅ Device updated successfully: ${device.name}');
      return Device.fromMap(response, response['id'].toString());
    } on PostgrestException catch (error) {
      debugPrint('❌ DeviceService: Database error updating device: ${error.message}');
      return null;
    } catch (e) {
      debugPrint('❌ DeviceService: Error updating device: $e');
      return null;
    }
  }

  // Delete device
  Future<bool> deleteDevice(String deviceId) async {
    try {
      if (!isInitialized) {
        await initialize();
      }

      await _supabase
          .from('devices')
          .delete()
          .eq('id', deviceId);

      debugPrint('✅ Device deleted successfully: $deviceId');
      return true;
    } on PostgrestException catch (error) {
      debugPrint('❌ DeviceService: Database error deleting device: ${error.message}');
      return false;
    } catch (e) {
      debugPrint('❌ DeviceService: Error deleting device: $e');
      return false;
    }
  }

  // Set device active/inactive
  Future<bool> setDeviceActive(String deviceId, bool isActive) async {
    try {
      if (!isInitialized) {
        await initialize();
      }

      await _supabase
          .from('devices')
          .update({'is_active': isActive, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', deviceId);

      debugPrint('✅ Device ${isActive ? 'activated' : 'deactivated'}: $deviceId');
      return true;
    } on PostgrestException catch (error) {
      debugPrint('❌ DeviceService: Database error setting device active: ${error.message}');
      return false;
    } catch (e) {
      debugPrint('❌ DeviceService: Error setting device active: $e');
      return false;
    }
  }

  // Check if device exists
  Future<bool> deviceExists(String deviceId) async {
    try {
      if (!isInitialized) {
        await initialize();
      }

      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        return false;
      }

      final response = await _supabase
          .from('devices')
          .select('id')
          .eq('device_id', deviceId)
          .eq('user_id', currentUser.id)
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint('❌ DeviceService: Error checking device existence: $e');
      return false;
    }
  }

  // Get device count for current user
  Future<int> getDeviceCount() async {
    try {
      if (!isInitialized) {
        await initialize();
      }

      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        return 0;
      }

      final response = await _supabase
          .from('devices')
          .select('id')
          .eq('user_id', currentUser.id);

      return response.length;
    } catch (e) {
      debugPrint('❌ DeviceService: Error getting device count: $e');
      return 0;
    }
  }
}