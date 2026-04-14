class Device {
  final String? id;
  final String deviceId;
  final String name;
  final String userId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isActive;

  Device({
    this.id,
    required this.deviceId,
    required this.name,
    required this.userId,
    DateTime? createdAt,
    this.updatedAt,
    this.isActive = true,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'device_id': deviceId,
      'device_name': name,
      'user_id': userId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'is_active': isActive,
    };
  }

  factory Device.fromMap(Map<String, dynamic> map, String id) {
    return Device(
      id: id,
      deviceId: map['device_id'] ?? '',
      name: map['device_name'] ?? '',
      userId: map['user_id'] ?? '',
      createdAt: map['created_at'] != null 
          ? DateTime.parse(map['created_at']) 
          : DateTime.now(),
      updatedAt: map['updated_at'] != null 
          ? DateTime.parse(map['updated_at']) 
          : null,
      isActive: map['is_active'] ?? true,
    );
  }

  Device copyWith({
    String? id,
    String? deviceId,
    String? name,
    String? userId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
  }) {
    return Device(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      name: name ?? this.name,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }
}