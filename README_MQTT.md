# MQTT Cooler Box Flutter App

Aplikasi Flutter sederhana yang dapat menerima pesan MQTT dari HiveMQ Cloud broker.

## Fitur

- Koneksi ke HiveMQ Cloud broker menggunakan SSL/TLS
- Menampilkan status koneksi real-time
- Menerima dan menampilkan pesan MQTT
- History pesan yang diterima (maksimal 10 pesan terakhir)
- UI yang sederhana dan responsif

## Konfigurasi HiveMQ Cloud

Sebelum menjalankan aplikasi, Anda perlu mengubah konfigurasi berikut di file `lib/main.dart`:

```dart
// Ganti dengan informasi HiveMQ Cloud Anda
const String broker = 'your-hivemq-cluster.s1.eu.hivemq.cloud'; // URL cluster HiveMQ Anda
const String username = 'your_username'; // Username HiveMQ Anda
const String password = 'your_password'; // Password HiveMQ Anda
const String topic = 'cooler_box/hello'; // Topic yang akan di-subscribe
```

## Cara Menjalankan

1. Pastikan Flutter sudah terinstall
2. Jalankan `flutter pub get` untuk mengunduh dependencies
3. Update konfigurasi HiveMQ Cloud di `lib/main.dart`
4. Jalankan aplikasi dengan `flutter run`

## Testing MQTT

Untuk testing, Anda dapat mengirim pesan ke topic `cooler_box/hello` menggunakan:

1. **HiveMQ Web Client**: https://www.hivemq.com/demos/websocket-client/
2. **MQTT Explorer**: https://mqtt-explorer.com/
3. **Command line dengan mosquitto**:
   ```bash
   mosquitto_pub -h your-hivemq-cluster.s1.eu.hivemq.cloud -p 8883 -u your_username -P your_password --cafile ca.crt -t "cooler_box/hello" -m "Hello from MQTT!"
   ```

## Dependencies

- `mqtt_client: ^10.2.0` - Library untuk koneksi MQTT
- `flutter/material.dart` - UI framework Flutter

## Struktur Aplikasi

- **Connection Status Card**: Menampilkan status koneksi ke broker
- **Latest Message Card**: Menampilkan pesan terakhir yang diterima
- **Message History**: List pesan yang diterima dengan timestamp
- **Floating Action Button**: Tombol untuk reconnect ke broker

## Troubleshooting

1. **Connection Failed**: Pastikan kredensial HiveMQ Cloud sudah benar
2. **SSL/TLS Error**: Pastikan menggunakan port 8883 untuk koneksi secure
3. **No Messages**: Pastikan topic yang di-subscribe sudah benar dan ada pesan yang dikirim ke topic tersebut