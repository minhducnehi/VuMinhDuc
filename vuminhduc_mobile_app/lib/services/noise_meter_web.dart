// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;

class NoiseMeterService {
  static final NoiseMeterService instance = NoiseMeterService._internal();
  NoiseMeterService._internal();

  bool isSupported() => true;

  bool isListening() {
    try {
      final meter = js.context['noiseMeter'];
      if (meter != null) {
        return meter.callMethod('getIsListening') == true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> startListening({double sensitivity = 1.0}) async {
    try {
      final meter = js.context['noiseMeter'];
      if (meter != null) {
        final res = meter.callMethod('start', [sensitivity]);
        return res != null;
      }
    } catch (_) {}
    return false;
  }

  void setSensitivity(double sensitivity) {
    try {
      final meter = js.context['noiseMeter'];
      if (meter != null) {
        meter.callMethod('setSensitivity', [sensitivity]);
      }
    } catch (_) {}
  }

  void stopListening() {
    try {
      final meter = js.context['noiseMeter'];
      if (meter != null) {
        meter.callMethod('stop');
      }
    } catch (_) {}
  }

  double getDecibel() {
    try {
      final meter = js.context['noiseMeter'];
      if (meter != null) {
        final val = meter.callMethod('getDecibel');
        if (val != null) {
          return (val as num).toDouble();
        }
      }
    } catch (_) {}
    return 0.0;
  }

  List<double> getWaveform() {
    try {
      final meter = js.context['noiseMeter'];
      if (meter != null) {
        final bars = meter.callMethod('getBars');
        if (bars != null) {
          final len = bars['length'] as int? ?? 0;
          final List<double> result = [];
          for (int i = 0; i < len; i++) {
            result.add((bars[i] as num).toDouble());
          }
          return result;
        }
      }
    } catch (_) {}
    return [];
  }
}
