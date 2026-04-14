import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class StorageTimeInfo extends StatelessWidget {
  final Map<String, dynamic>? storageData;
  final VoidCallback? onRefresh;

  const StorageTimeInfo({
    Key? key,
    this.storageData,
    this.onRefresh,
  }) : super(key: key);

  String _formatDuration(int days, int hours, int minutes, int seconds) {
    List<String> parts = [];
    
    if (days > 0) parts.add('${days}h');
    if (hours > 0) parts.add('${hours}j');
    if (minutes > 0) parts.add('${minutes}m');
    if (seconds > 0) parts.add('${seconds}d');
    
    return parts.isEmpty ? '0d' : parts.join(' ');
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '-';
    return DateFormat('dd MMM yyyy, HH:mm').format(dateTime);
  }

  String _getTimeRemaining(DateTime? endTime) {
    if (endTime == null) return 'Tidak ada batas waktu';
    
    final now = DateTime.now();
    final difference = endTime.difference(now);
    
    if (difference.isNegative) {
      return 'Waktu telah habis';
    }
    
    final days = difference.inDays;
    final hours = difference.inHours % 24;
    final minutes = difference.inMinutes % 60;
    
    if (days > 0) {
      return '${days}h ${hours}j lagi';
    } else if (hours > 0) {
      return '${hours}j ${minutes}m lagi';
    } else {
      return '${minutes}m lagi';
    }
  }

  Color _getStatusColor(DateTime? endTime) {
    if (endTime == null) return Colors.grey;
    
    final now = DateTime.now();
    final difference = endTime.difference(now);
    
    if (difference.isNegative) {
      return Colors.red;
    } else if (difference.inHours < 1) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (storageData == null) {
      return _buildEmptyState();
    }

    final days = storageData!['days'] ?? 0;
    final hours = storageData!['hours'] ?? 0;
    final minutes = storageData!['minutes'] ?? 0;
    final seconds = storageData!['seconds'] ?? 0;
    
    final startTime = storageData!['start_time'] != null 
        ? DateTime.parse(storageData!['start_time']) 
        : null;
    
    final endTime = storageData!['end_time'] != null 
        ? DateTime.parse(storageData!['end_time']) 
        : startTime?.add(Duration(days: days, hours: hours, minutes: minutes, seconds: seconds));

    final durationText = _formatDuration(days, hours, minutes, seconds);
    final startTimeText = _formatDateTime(startTime);
    final endTimeText = _formatDateTime(endTime);
    final timeRemaining = _getTimeRemaining(endTime);
    final statusColor = _getStatusColor(endTime);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Colors.grey.shade50,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.blue.shade50,
                  Colors.blue.shade100.withOpacity(0.3),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.access_time,
                    color: Colors.blue.shade700,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Waktu Penyimpanan',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      Text(
                        durationText,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onRefresh != null)
                  IconButton(
                    icon: Icon(
                      Icons.refresh,
                      color: Colors.blue.shade700,
                      size: 20,
                    ),
                    onPressed: onRefresh,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildInfoRow(
                  'Mulai',
                  startTimeText,
                  Icons.play_arrow,
                  Colors.green,
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  'Berakhir',
                  endTimeText,
                  Icons.stop,
                  Colors.red,
                ),
                if (endTime != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: statusColor.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.timer,
                          color: statusColor,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            timeRemaining,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            color: color,
            size: 16,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.access_time,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            'Belum ada pengaturan waktu penyimpanan',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Atur waktu penyimpanan di form pengaturan',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}