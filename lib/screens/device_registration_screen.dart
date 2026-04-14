import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/device.dart';
import '../services/device_service.dart';
import '../services/auth_service.dart';
import 'monitoring_screen.dart';
import 'profile_screen.dart';
import '../main.dart';

class DeviceRegistrationScreen extends StatefulWidget {
  const DeviceRegistrationScreen({super.key});

  @override
  State<DeviceRegistrationScreen> createState() => _DeviceRegistrationScreenState();
}

class _DeviceRegistrationScreenState extends State<DeviceRegistrationScreen> {
  final _deviceService = DeviceService();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _isLoadingDevices = false;
  List<Device> _devices = [];
  String? _selectedDeviceId;

  @override
  void initState() {
    super.initState();
    _loadUserDevices();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadUserDevices() async {
    setState(() {
      _isLoadingDevices = true;
    });

    try {
      final devices = await _deviceService.getUserDevices();
      setState(() {
        _devices = devices;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memuat daftar alat: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoadingDevices = false;
      });
    }
  }

  Future<void> _showRegistrationDialog() async {
    final deviceIdController = TextEditingController();
    final nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Daftarkan Alat Baru'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Device ID
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: deviceIdController,
                        decoration: InputDecoration(
                          labelText: 'ID Alat *',
                          hintText: 'Masukkan ID unik alat',
                          prefixIcon: const Icon(Icons.device_hub),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {}); // Trigger rebuild for MQTT topic display
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'ID Alat tidak boleh kosong';
                          }
                          if (value.length < 3) {
                            return 'ID Alat minimal 3 karakter';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _scanQRCode(deviceIdController),
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'Scan QR Code',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.blue[50],
                        foregroundColor: Colors.blue[600],
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Device Name
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Nama Alat *',
                    hintText: 'Masukkan nama alat',
                    prefixIcon: const Icon(Icons.devices_other),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Nama Alat tidak boleh kosong';
                  }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                // Info about MQTT topic
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[600], size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Topik MQTT: ${deviceIdController.text.isNotEmpty ? deviceIdController.text : "device_id"}/<topic>',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  Navigator.of(context).pop(true);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
              ),
              child: const Text('Daftarkan'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await _registerDevice(deviceIdController.text.trim(), nameController.text.trim());
    }

    deviceIdController.dispose();
    nameController.dispose();
  }

  Future<void> _scanQRCode(TextEditingController deviceIdController) async {
    try {
      final String? scannedCode = await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          return Dialog(
            child: Container(
              width: double.maxFinite,
              height: 400,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Scan QR Code',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: MobileScanner(
                      onDetect: (capture) {
                        final List<Barcode> barcodes = capture.barcodes;
                        if (barcodes.isNotEmpty) {
                          final String? code = barcodes.first.rawValue;
                          if (code != null && code.isNotEmpty) {
                            Navigator.of(context).pop(code);
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Arahkan kamera ke QR Code',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (scannedCode != null && scannedCode.isNotEmpty) {
        setState(() {
          deviceIdController.text = scannedCode;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('QR Code berhasil discan: $scannedCode'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal scan QR Code: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _registerDevice(String deviceId, String deviceName) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        throw Exception('Pengguna tidak login');
      }

      // Cek apakah device ID sudah ada
      final existingDevice = await _deviceService.getDeviceByDeviceId(deviceId);
      if (existingDevice != null) {
        throw Exception('ID Alat sudah terdaftar');
      }

      final newDevice = Device(
        deviceId: deviceId,
        name: deviceName,
        userId: currentUser.id,
      );

      final registeredDevice = await _deviceService.registerDevice(newDevice);
      if (registeredDevice != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Alat berhasil didaftarkan'),
            backgroundColor: Colors.green,
          ),
        );

        // Refresh device list
        await _loadUserDevices();

        // Tanyakan user apakah ingin langsung monitoring
        if (mounted) {
          final goToMonitoring = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Registrasi Berhasil'),
              content: Text('Alat "$deviceName" berhasil didaftarkan.\n\nIngin langsung monitoring device ini?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Nanti'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Monitoring'),
                ),
              ],
            ),
          );

          if (goToMonitoring == true) {
            _selectDeviceForMonitoring(registeredDevice);
          }
        }
      } else {
        throw Exception('Gagal mendaftarkan alat');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _selectDeviceForMonitoring(Device device) {
    setState(() {
      _selectedDeviceId = device.id;
    });

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MonitoringScreen(device: device),
      ),
    );
  }

  Future<void> _deleteDevice(Device device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Alat'),
        content: Text('Apakah Anda yakin ingin menghapus alat "${device.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoadingDevices = true;
      });

      try {
        final success = await _deviceService.deleteDevice(device.id!);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Alat berhasil dihapus'),
              backgroundColor: Colors.green,
            ),
          );
          await _loadUserDevices();
        } else {
          throw Exception('Gagal menghapus alat');
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() {
          _isLoadingDevices = false;
        });
      }
    }
  }

  void _logout() async {
    try {
      await _authService.signOut();
      if (mounted) {
        // Navigasi ulang ke AuthWrapper agar stack dibersihkan dan login muncul
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthWrapper()),
          (route) => false,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal logout: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // SafeArea untuk menghindari notch/tepi layar
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pendaftaran Alat'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      drawer: _buildDrawer(),
      body: RefreshIndicator(
        onRefresh: _loadUserDevices,
        child: SafeArea(
          child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.of(context).size.width < 360 ? 12 : 16,
            vertical: 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Card untuk daftar alat
              _buildDeviceListCard(),
            ],
          ),
        ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showRegistrationDialog,
        backgroundColor: Colors.blue[600],
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Tambah Alat',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          // Header Drawer
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              color: Colors.blue[600],
            ),
            accountName: FutureBuilder(
              future: Future.value(_authService.currentUser),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  final user = snapshot.data!;
                  return Text(
                    user.userMetadata?['full_name'] ?? 'Pengguna',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  );
                }
                return const Text('Pengguna');
              },
            ),
            accountEmail: FutureBuilder(
              future: Future.value(_authService.currentUser),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  final user = snapshot.data!;
                  return Text(user.email ?? '');
                }
                return const Text('');
              },
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(
                Icons.person,
                color: Colors.blue[600],
                size: 40,
              ),
            ),
          ),
          
          // Menu Utama
          ListTile(
            leading: const Icon(Icons.devices),
            title: const Text('Pendaftaran Alat'),
            onTap: () {
              Navigator.of(context).pop();
            },
            selected: true,
            selectedTileColor: Colors.blue[50],
          ),
          
          const Divider(),
          
          // Profile dan Pengaturan
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Profile'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ProfileScreen(),
                ),
              );
            },
          ),
          
          
          const Spacer(),
          
          // Logout
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.of(context).pop();
              _logout();
            },
          ),
        ],
      ),
    );
  }



  Widget _buildDeviceListCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.green[50]!,
              Colors.white,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green[600],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.list_alt,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Daftar Alat Anda',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const Spacer(),
                  if (_isLoadingDevices)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              if (_devices.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(
                          Icons.devices_other,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Belum ada alat terdaftar',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tekan tombol + untuk mendaftarkan alat',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 500;
                    if (!isWide) {
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _devices.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final device = _devices[index];
                          return _buildDeviceCard(device);
                        },
                      );
                    }
                    // Grid untuk layar lebih lebar (landscape/foldable)
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _devices.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 3.2,
                      ),
                      itemBuilder: (context, index) {
                        final device = _devices[index];
                        return _buildDeviceCard(device);
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceCard(Device device) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Colors.grey[50]!,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey[300]!,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.grey[300]!,
              width: 1,
            ),
          ),
          child: Icon(
            Icons.devices,
            color: Colors.grey[600],
            size: 24,
          ),
        ),
        title: Text(
          device.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ID: ${device.deviceId}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Action buttons
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'monitor':
                    _selectDeviceForMonitoring(device);
                    break;
                  case 'delete':
                    _deleteDevice(device);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'monitor',
                  child: Row(
                    children: [
                      Icon(Icons.analytics, size: 18),
                      SizedBox(width: 8),
                      Text('Monitor'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Hapus', style: TextStyle(color: Colors.red)),
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
}