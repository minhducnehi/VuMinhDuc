import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/vietmap_service.dart';

class VietmapViewerWidget extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String title;
  final String? address;
  final double height;
  final bool showControls;
  final VoidCallback? onFullScreen;

  const VietmapViewerWidget({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.title,
    this.address,
    this.height = 240,
    this.showControls = true,
    this.onFullScreen,
  });

  @override
  State<VietmapViewerWidget> createState() => _VietmapViewerWidgetState();
}

class _VietmapViewerWidgetState extends State<VietmapViewerWidget> {
  int _currentZoom = 16;
  bool _isLoading = true;
  Uint8List? _mapBytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMap();
  }

  @override
  void didUpdateWidget(covariant VietmapViewerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude ||
        oldWidget.address != widget.address) {
      _loadMap();
    }
  }

  Future<void> _loadMap() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final bytes = await VietmapService.fetchStaticMapBytes(
        lat: widget.latitude,
        lng: widget.longitude,
        zoom: _currentZoom,
        width: 650,
        height: (widget.height * 1.5).round(),
        address: widget.address ?? widget.title,
      );

      if (!mounted) return;
      if (bytes != null && bytes.isNotEmpty) {
        setState(() {
          _mapBytes = bytes;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _error = 'Không thể tải ảnh bản đồ Vietmap. Vui lòng kiểm tra kết nối.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Lỗi kết nối Vietmap: $e';
      });
    }
  }

  void _zoomIn() {
    if (_currentZoom < 19) {
      setState(() => _currentZoom++);
      _loadMap();
    }
  }

  void _zoomOut() {
    if (_currentZoom > 12) {
      setState(() => _currentZoom--);
      _loadMap();
    }
  }

  void _showApiKeyDialog() {
    final ctrl = TextEditingController(text: VietmapService.apiKey);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.vpn_key, color: Color(0xFF0284C7)),
            SizedBox(width: 8),
            Text('API Key Vietmap', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ứng dụng đang dùng API VietMap để tải bản đồ thời gian thực vị trí của con.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                labelText: 'VietMap API Key',
                hintText: 'Nhập API Key từ Vietmap Console',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.key),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '💡 Mẹo: Có thể lấy key miễn phí tại: https://maps.vietmap.vn/console-v2/ (Hoặc giữ nguyên "test" để chạy thử).',
              style: TextStyle(fontSize: 11, color: Color(0xFF0369A1)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await VietmapService.resetApiKey();
              if (ctx.mounted) Navigator.pop(ctx);
              _loadMap();
            },
            child: const Text('Mặc định (test)', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final newKey = ctrl.text.trim();
              if (newKey.isNotEmpty) {
                await VietmapService.setCustomApiKey(newKey);
              }
              if (ctx.mounted) Navigator.pop(ctx);
              _loadMap();
            },
            child: const Text('Lưu API Key'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 1. Hình ảnh bản đồ Vietmap
          Positioned.fill(
            child: _isLoading
                ? Container(
                    color: const Color(0xFFF1F5F9),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF0284C7)),
                          SizedBox(height: 10),
                          Text('Đang tải bản đồ Vietmap...', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                        ],
                      ),
                    ),
                  )
                : _mapBytes != null
                    ? Image.memory(
                        _mapBytes!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _buildFallbackMap(),
                      )
                    : _buildFallbackMap(),
          ),

          // 2. Watermark / Badge Vietmap phía trên bên trái
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.map, size: 14, color: Color(0xFF0284C7)),
                  SizedBox(width: 5),
                  Text(
                    'VIETMAP API 🇻🇳',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0284C7),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Nút Cài đặt Key và Phóng to phía trên bên phải
          Positioned(
            top: 10,
            right: 10,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMapIconButton(
                  icon: Icons.vpn_key,
                  tooltip: 'Cài đặt VietMap API Key',
                  onTap: _showApiKeyDialog,
                ),
                const SizedBox(width: 6),
                _buildMapIconButton(
                  icon: Icons.refresh,
                  tooltip: 'Làm mới bản đồ',
                  onTap: _loadMap,
                ),
                if (widget.onFullScreen != null) ...[
                  const SizedBox(width: 6),
                  _buildMapIconButton(
                    icon: Icons.fullscreen,
                    tooltip: 'Xem toàn màn hình',
                    onTap: widget.onFullScreen!,
                  ),
                ],
              ],
            ),
          ),

          // 4. Pin đánh dấu vị trí con ở trung tâm
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.child_care, color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        widget.title,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.location_on,
                  color: Color(0xFFE11D48),
                  size: 38,
                ),
                const SizedBox(height: 24), // Offset cân bằng chân kim chỉ
              ],
            ),
          ),

          // 5. Thanh công cụ Zoom (+ / -) ở góc dưới bên phải
          if (widget.showControls)
            Positioned(
              bottom: 12,
              right: 12,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: _zoomIn,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.add, size: 20, color: Color(0xFF1E293B)),
                      ),
                    ),
                    Container(height: 1, width: 28, color: const Color(0xFFE2E8F0)),
                    InkWell(
                      onTap: _zoomOut,
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.remove, size: 20, color: Color(0xFF1E293B)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 6. Thanh công cụ phía dưới bên trái: Zoom + Nút Mở Google Maps / Vietmap
          Positioned(
            bottom: 10,
            left: 10,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Zoom: $_currentZoom',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => VietmapService.openDirectionsToChild(
                    widget.latitude,
                    widget.longitude,
                    childName: widget.title,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D4ED8),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.directions, color: Colors.white, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'Google Maps',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => VietmapService.openVietmapWeb(
                    widget.latitude,
                    widget.longitude,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map, color: Colors.white, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'VietMap Live',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapIconButton({required IconData icon, required String tooltip, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 4),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: 18, color: const Color(0xFF0F172A)),
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }

  Widget _buildFallbackMap() {
    return Container(
      color: const Color(0xFFF1F5F9),
      padding: const EdgeInsets.all(12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, size: 36, color: Color(0xFFE11D48)),
            const SizedBox(height: 4),
            Text(
              'Tọa độ: ${widget.latitude.toStringAsFixed(5)}, ${widget.longitude.toStringAsFixed(5)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
            if (widget.address != null) ...[
              const SizedBox(height: 2),
              Text(
                widget.address!,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 2),
              Text(
                _error!,
                style: const TextStyle(fontSize: 10, color: Color(0xFFD97706)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => VietmapService.openDirectionsToChild(
                    widget.latitude,
                    widget.longitude,
                    childName: widget.title,
                  ),
                  icon: const Icon(Icons.directions, size: 14),
                  label: const Text('Xem Google Maps', style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1D4ED8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => VietmapService.openVietmapWeb(
                    widget.latitude,
                    widget.longitude,
                  ),
                  icon: const Icon(Icons.map, size: 14),
                  label: const Text('Mở VietMap', style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _loadMap,
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('Thử lại', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
