# Analisis Arsitektur Aplikasi Cooler Box IoT

## 1. Gambaran Umum Aplikasi

Aplikasi **Cooler Box IoT** adalah aplikasi mobile berbasis Flutter yang digunakan untuk memantau dan mengelola perangkat cooler box pintar. Aplikasi ini memungkinkan pengguna untuk:
- Melakukan registrasi dan login pengguna
- Mendaftarkan perangkat cooler box melalui QR code
- Memantau suhu, lokasi, dan waktu penyimpanan perangkat
- Menerima notifikasi alert ketika suhu melebihi batas
- Mengelola waktu penyimpanan perangkat

## 2. Struktur Folder dan File

```
lib/
├── config/
│   └── supabase_config.dart          # Konfigurasi Supabase
├── models/
│   └── device.dart                   # Model data perangkat
├── screens/
│   ├── login_screen.dart            # Halaman login
│   ├── device_registration_screen.dart  # Halaman registrasi perangkat
│   ├── monitoring_screen.dart       # Halaman monitoring perangkat
│   └── profile_screen.dart          # Halaman profil pengguna
├── services/
│   ├── auth_service.dart            # Layanan autentikasi
│   ├── device_service.dart          # Layanan manajemen perangkat
│   ├── mqtt_service.dart            # Layanan komunikasi MQTT
│   ├── database_service.dart        # Layanan database Supabase
│   └── notification_service.dart    # Layanan notifikasi
├── widgets/
│   └── storage_time_info.dart       # Widget informasi waktu penyimpanan
├── main.dart                        # Entry point aplikasi
└── mqttreference.txt                # Referensi MQTT (file teks)
```

## 3. Arsitektur Aplikasi

### 3.1 Pola Desain yang Digunakan
Aplikasi ini menerapkan pola **MVVM (Model-View-ViewModel)** dengan Service Layer:
- **Model**: Definisi struktur data (Device)
- **View**: Widget Flutter (Screens)
- **ViewModel**: Logic di dalam StatefulWidget
- **Service**: Business logic dan integrasi eksternal

### 3.2 Alur Data Utama
```
User Interface (Screens)
         ↕
    Services Layer
    (Auth, Device, MQTT, Database, Notification)
         ↕
    External Services
(Supabase, HiveMQ Cloud, SharedPreferences)
```

## 4. Komponen Utama

### 4.1 Entry Point - main.dart
- **Fungsi**: Inisialisasi aplikasi dan Supabase
- **Widget Utama**: MyApp, AuthWrapper, MqttHomePage
- **State Management**: StatefulWidget dengan setState

### 4.2 Model Data - device.dart
```dart
class Device {
  final String id;
  final String deviceId;      // ID perangkat IoT
  final String name;          // Nama perangkat
  final String userId;        // ID pengguna pemilik
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;        // Status aktif perangkat
}
```

### 4.3 Layanan (Services)

#### AuthService
- **Fungsi**: Manajemen autentikasi pengguna
- **Method utama**: signUp(), signIn(), signOut(), resetPassword()
- **Penyimpanan**: SharedPreferences untuk session
- **Integrasi**: Supabase Authentication

#### DeviceService
- **Fungsi**: CRUD operasi perangkat
- **Method utama**: registerDevice(), getUserDevices(), deleteDevice()
- **Integrasi**: Supabase Database

#### MqttService
- **Fungsi**: Komunikasi real-time dengan perangkat IoT
- **Fitur**: Auto-reconnection, heartbeat mechanism
- **Broker**: HiveMQ Cloud (mqtts://e85b8b6a3e8b4c98b7e1c3e8b7e1c3e8.s1.eu.hivemq.cloud:8883)
- **Topic**: Temperature, location, storage time

#### DatabaseService
- **Fungsi**: Operasi database untuk sensor data dan settings
- **Method**: saveSensorData(), getDeviceSettings(), saveStorageTime()
- **Integrasi**: Supabase Database

#### NotificationService
- **Fungsi**: Menampilkan notifikasi dan getaran
- **Fitur**: Temperature alerts, time notifications
- **Library**: flutter_local_notifications, vibration

## 5. Alur Eksekusi Aplikasi

### 5.1 Proses Login
```
1. User memasukkan email & password
2. LoginScreen → AuthService.signIn()
3. AuthService → Supabase.auth.signInWithPassword()
4. Jika sukses → simpan session di SharedPreferences
5. Navigasi ke DeviceRegistrationScreen
```

### 5.2 Registrasi Perangkat
```
1. User scan QR Code (deviceId)
2. DeviceRegistrationScreen → DeviceService.registerDevice()
3. DeviceService → Supabase.from('devices').insert()
4. Refresh daftar perangkat
```

### 5.3 Monitoring Perangkat
```
1. MonitoringScreen → MqttService.connect()
2. Subscribe ke topic: "esp32/{deviceId}/temperature"
3. Terima data → update UI secara real-time
4. Cek threshold suhu → trigger notifikasi jika melebihi batas
5. Simpan data sensor ke database
```

## 6. Integrasi Eksternal

### 6.1 Supabase
- **Authentication**: User management
- **Database**: Tabel devices, sensor_data, device_settings
- **Konfigurasi**: URL dan Anon Key di supabase_config.dart

### 6.2 MQTT Broker (HiveMQ Cloud)
- **Host**: mqtss://e85b8b6a3e8b4c98b7e1c3e8b7e1c3e8.s1.eu.hivemq.cloud:8883
- **Authentication**: Username & password
- **Topic Structure**:
  - `esp32/{deviceId}/temperature`
  - `esp32/{deviceId}/location`
  - `esp32/{deviceId}/storage_time`

### 6.3 Flutter Plugins
- **flutter_local_notifications**: Notifikasi lokal
- **vibration**: Getaran alert
- **mobile_scanner**: QR Code scanning
- **flutter_map**: Peta lokasi
- **shared_preferences**: Local storage

## 7. Business Logic dan Aturan

### 7.1 Autentikasi
- User harus login untuk mengakses fitur
- Session disimpan di SharedPreferences
- Auto logout jika token expired

### 7.2 Manajemen Perangkat
- Setiap user hanya bisa melihat perangkat miliknya
- Perangkat didaftarkan via QR Code scanning
- Status aktif/nonaktif tidak lagi ditampilkan di UI (sudah disederhanakan)

### 7.3 Monitoring
- Sistem monitoring real-time via MQTT
- Notifikasi suhu jika > batas maksimal (dapat diatur user)
- Waktu penyimpanan dapat diatur dan dimonitor
- Data lokasi ditampilkan di peta

### 7.4 Notifikasi
- Temperature alert: Notifikasi + getaran pola alarm
- Time notification: Notifikasi waktu penyimpanan
- Permission request untuk Android 13+

## 8. Error Handling

### 8.1 Mekanisme Error Handling
- **Try-catch blocks** di setiap service method
- **Print statements** untuk debugging (perlu diganti dengan proper logging)
- **User feedback** via SnackBar untuk error UI
- **Rethrow exceptions** untuk error kritis

### 8.2 Error yang Ditangani
- **Network errors**: Koneksi internet terputus
- **Authentication errors**: Login gagal, token expired
- **Database errors**: Query gagal, constraint violation
- **MQTT errors**: Koneksi broker gagal, publish/subscribe error

## 9. Keamanan

### 9.1 Implementasi Keamanan
- **Supabase Row Level Security (RLS)** untuk data isolation
- **Environment variables** untuk sensitive data (URL, API keys)
- **Secure storage** untuk session (SharedPreferences)
- **MQTT over SSL/TLS** untuk komunikasi aman

### 9.2 Area yang Perlu Ditingkatkan
- **Input validation** perlu ditingkatkan
- **Error message handling** untuk tidak expose sensitive info
- **Rate limiting** untuk prevent abuse

## 10. Performa dan Optimasi

### 10.1 Mekanisme yang Sudah Ada
- **Lazy loading** untuk data perangkat
- **Auto-reconnection** untuk MQTT
- **Singleton pattern** untuk services
- **Proper disposal** untuk controllers

### 10.2 Rekomendasi Optimasi
- Implementasi caching untuk data yang sering diakses
- Pagination untuk daftar perangkat (jika jumlah besar)
- Background sync untuk data offline
- Image optimization untuk assets

## 11. Diagram Alur Sistem

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Flutter App   │────▶│   Service Layer  │────▶│  External APIs  │
│                 │     │                  │     │                 │
│ - LoginScreen   │     │ - AuthService    │     │ - Supabase      │
│ - DeviceReg     │     │ - DeviceService  │     │ - HiveMQ Cloud  │
│ - Monitoring    │     │ - MqttService    │     │                 │
│ - Profile       │     │ - DatabaseService│     └─────────────────┘
└─────────────────┘     │ - Notification   │
        │                 │   Service        │
        │                 └──────────────────┘
        │                         │
        ▼                         ▼
┌─────────────────┐     ┌──────────────────┐
│   Local Storage │     │   Device Hardware  │
│                 │     │                    │
│ - SharedPrefs   │     │ - Camera (QR)     │
│ - Cache         │     │ - GPS Location    │
│                 │     │ - Vibration       │
└─────────────────┘     └──────────────────┘
```

## 12. Kesimpulan

Aplikasi Cooler Box IoT memiliki arsitektur yang terstruktur dengan baik menggunakan pola MVVM dan service layer. Integrasi dengan Supabase untuk backend dan HiveMQ untuk komunikasi real-time memberikan fondasi yang kuat. Namun, ada beberapa area yang bisa ditingkatkan:

1. **Error handling** perlu lebih komprehensif
2. **State management** bisa dipertimbangkan untuk migrasi ke Provider/BLoC
3. **Testing** belum tersedia (unit test, integration test)
4. **Documentation** perlu ditambahkan di level kode
5. **Logging** proper untuk production debugging

Aplikasi ini siap untuk dikembangkan lebih lanjut dengan fitur-fitur tambahan seperti analytics, reporting, dan multi-device synchronization.