import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../services/vietmap_service.dart';
import 'vietmap_viewer_widget.dart';

class VietmapFullScreenDialog extends StatelessWidget {
  final String memberName;
  final String roleName;
  final double latitude;
  final double longitude;
  final String address;
  final double speed;
  final String lastUpdated;

  const VietmapFullScreenDialog({
    super.key,
    required this.memberName,
    required this.roleName,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.speed,
    required this.lastUpdated,
  });

  static Future<void> show(
    BuildContext context, {
    required String memberName,
    required String roleName,
    required double latitude,
    required double longitude,
    required String address,
    double speed = 0,
    String lastUpdated = 'Vừa xong',
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => VietmapFullScreenDialog(
        memberName: memberName,
        roleName: roleName,
        latitude: latitude,
        longitude: longitude,
        address: address,
        speed: speed,
        lastUpdated: lastUpdated,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 720),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0369A1), Color(0xFF0284C7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.child_care, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bản đồ vị trí con yêu: $memberName',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '$roleName • Định vị VietMap vệ tinh',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Vietmap Viewer lớn
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: VietmapViewerWidget(
                  latitude: latitude,
                  longitude: longitude,
                  title: memberName,
                  address: address,
                  height: 380,
                  showControls: true,
                ),
              ),
            ),

            // Bảng thông tin chi tiết vị trí & GPS
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.place, color: Color(0xFFE11D48), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            address,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildInfoChip(
                          icon: Icons.gps_fixed,
                          label: '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
                          color: const Color(0xFF0284C7),
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: '$latitude,$longitude'));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Đã sao chép tọa độ GPS vào bộ nhớ tạm')),
                            );
                          },
                        ),
                        _buildInfoChip(
                          icon: Icons.speed,
                          label: '${speed.toStringAsFixed(1)} km/h',
                          color: const Color(0xFF16A34A),
                        ),
                        _buildInfoChip(
                          icon: Icons.access_time,
                          label: lastUpdated,
                          color: const Color(0xFFD97706),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Nút hành động dẫn đường và liên hệ
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.directions, size: 20),
                      label: const Text('Chỉ Đường Đến Con', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () {
                        VietmapService.openDirectionsToChild(latitude, longitude, childName: memberName);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    label: const Text('Vietmap Web'),
                    onPressed: () {
                      VietmapService.openVietmapWeb(latitude, longitude);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: chip);
    }
    return chip;
  }
}
