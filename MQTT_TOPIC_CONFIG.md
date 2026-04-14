# Konfigurasi Topic MQTT

## Format Topic
Setelah device didaftarkan, topic MQTT akan mengikuti format:
```
deviceid/<topic_purpose>
```

## Contoh Topic
Jika device ID adalah `cooler123`, maka topic yang tersedia:

### Monitoring Topics (Publish dari device)
- `cooler123/temperature` - Data suhu
- `cooler123/humidity` - Data kelembaban  
- `cooler123/status` - Status device (on/off/error)
- `cooler123/battery` - Level baterai
- `cooler123/location` - Lokasi GPS

### Control Topics (Subscribe ke device)
- `cooler123/control/temperature` - Set target suhu
- `cooler123/control/power` - Kontrol on/off
- `cooler123/control/mode` - Ubah mode operasi

### Notification Topics
- `cooler123/alert/high_temp` - Alert suhu tinggi
- `cooler123/alert/low_battery` - Alert baterai lemah
- `cooler123/alert/maintenance` - Alert maintenance

## Cara Penggunaan
1. Device mendaftar dengan ID unik (contoh: `cooler123`)
2. Device publish ke topic `cooler123/temperature` dengan payload suhu
3. Aplikasi subscribe ke topic `cooler123/+` untuk menerima semua data dari device
4. Aplikasi publish ke `cooler123/control/power` untuk mengontrol device

## MQTT Broker Configuration
- **Broker**: HiveMQ Cloud (67d560452e2d4534b5decfc22c4cb938.s1.eu.hivemq.cloud)
- **Port**: 8883 (TLS)
- **Protocol**: MQTT over TLS
- **Authentication**: Username & Password