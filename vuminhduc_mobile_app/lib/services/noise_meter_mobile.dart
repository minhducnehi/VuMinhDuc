import 'dart:async';
import 'dart:math';
import 'package:noise_meter/noise_meter.dart';
import 'package:permission_handler/permission_handler.dart';

class NoiseMeterService {
  static final NoiseMeterService instance = NoiseMeterService._internal();
  NoiseMeterService._internal();

  NoiseMeter? _noiseMeter;
  StreamSubscription<NoiseReading>? _noiseSubscription;
  bool _isListening = false;
  double _currentDecibel = 40.0;
  double _sensitivity = 1.0;
  List<double> _waveform = List.filled(14, 20.0);

  bool isSupported() => true;
  bool isListening() => _isListening;

  void setSensitivity(double sensitivity) {
    _sensitivity = sensitivity;
  }

  Future<bool> startListening({double sensitivity = 1.0}) async {
    _sensitivity = sensitivity;
    if (_isListening) return true;

    try {
      var status = await Permission.microphone.status;
      if (!status.isGranted) {
        status = await Permission.microphone.request();
      }
      if (!status.isGranted) {
        return false;
      }

      _noiseMeter ??= NoiseMeter();
      _noiseSubscription?.cancel();
      _noiseSubscription = _noiseMeter!.noise.listen(
        (NoiseReading reading) {
          _isListening = true;
          // meanDecibel phản ánh mức âm trung bình mượt mà, tránh xung đột ngột ảo
          double rawDb = reading.meanDecibel;
          if (rawDb.isNaN || rawDb.isInfinite || rawDb < 25) {
            rawDb = reading.maxDecibel;
          }
          if (rawDb.isNaN || rawDb.isInfinite || rawDb < 25) {
            rawDb = 35.0;
          }

          // Chuẩn hóa theo ngưỡng âm thanh thực tế
          double boosted = 40.0 + (rawDb - 40.0) * _sensitivity;
          _currentDecibel = double.parse(boosted.clamp(28.0, 115.0).toStringAsFixed(1));

          // Cập nhật 14 cột phổ sóng âm thanh theo tín hiệu mic điện thoại
          final now = DateTime.now().millisecondsSinceEpoch;
          _waveform = List<double>.generate(14, (i) {
            double jitter = sin(now / 150.0 + i * 0.9) * 10.0;
            return (_currentDecibel * 0.65 + jitter).clamp(10.0, 95.0);
          });
        },
        onError: (err) {
          _isListening = false;
        },
        cancelOnError: false,
      );
      _isListening = true;
      return true;
    } catch (_) {
      _isListening = false;
      return false;
    }
  }

  void stopListening() {
    _noiseSubscription?.cancel();
    _noiseSubscription = null;
    _isListening = false;
  }

  double getDecibel() => _currentDecibel;

  List<double> getWaveform() => _waveform;
}
