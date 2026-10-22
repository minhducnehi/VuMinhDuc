import 'package:flutter_test/flutter_test.dart';
import 'package:vuminhduc_2380614671_app/main.dart';
import 'package:vuminhduc_2380614671_app/services/yamnet_audio_safety_service.dart';

void main() {
  group('1. Kiểm thử Giao diện & Luồng màn hình (UI Smoke Tests)', () {
    testWidgets('Màn hình đăng nhập hiển thị đầy đủ thông tin hệ thống & nút xác thực OTP', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // Kiểm tra tiêu đề nhận diện thương hiệu
      expect(find.textContaining('VŨ MINH ĐỨC'), findsOneWidget);
      expect(find.text('Đăng Nhập Tài Khoản'), findsOneWidget);
      expect(find.text('TIẾP TỤC & GỬI MÃ OTP'), findsOneWidget);
    });
  });

  group('2. Kiểm thử Mô hình AI YAMNet & AudioSet (AI Audio Safety Tests)', () {
    final service = YamnetAudioSafetyService.instance;

    test('Phân loại chính xác Tiếng la hét / Kêu cứu khẩn cấp (Screaming)', () {
      final waveform = List.generate(14, (i) => i >= 10 ? 0.95 : 0.2);
      final result = service.analyzeAudioFrame(decibel: 88.0, waveform: waveform);

      expect(result.category, YamnetSafetyCategory.screaming);
      expect(result.severity, 'CRITICAL');
      expect(result.isCritical, isTrue);
      expect(result.yamnetClass, contains('/m/03qc9r'));
    });

    test('Phân loại chính xác Va chạm tai nạn xe cộ / Ngã chấn thương (Vehicle Crash / Impact)', () {
      final waveform = List.generate(14, (_) => 0.88);
      final result = service.analyzeAudioFrame(decibel: 94.0, waveform: waveform);

      expect(result.category, YamnetSafetyCategory.vehicleCrash);
      expect(result.severity, 'CRITICAL');
      expect(result.isCritical, isTrue);
      expect(result.yamnetClass, contains('/m/07r04'));
    });

    test('Phân loại chính xác Kính vỡ / Đập phá đồ đạc (Glass Breaking)', () {
      // Năng lượng dải cao > 1.3 lần âm trung, decibel 80 dB
      final waveform = List.generate(14, (i) => i >= 10 ? 0.9 : 0.3);
      final result = service.analyzeAudioFrame(decibel: 80.0, waveform: waveform);

      expect(result.category, YamnetSafetyCategory.glassBreaking);
      expect(result.severity, 'WARNING');
      expect(result.isWarning, isTrue);
      expect(result.yamnetClass, contains('/m/07rwj37'));
    });

    test('Phân loại chính xác Tiếng quát tháo / Cãi vã / Bắt nạt (Shout / Yell)', () {
      // Âm trung cao hơn âm cao, decibel 78 dB
      final waveform = List.generate(14, (i) => (i >= 4 && i < 10) ? 0.8 : 0.2);
      final result = service.analyzeAudioFrame(decibel: 78.0, waveform: waveform);

      expect(result.category, YamnetSafetyCategory.shout);
      expect(result.severity, 'WARNING');
      expect(result.isWarning, isTrue);
      expect(result.yamnetClass, contains('/m/07plz5l'));
    });

    test('Phân loại chính xác Tiếng khóc lóc / Nức nở (Crying / Sobbing)', () {
      // Dao động ở ngưỡng 70 dB
      final waveform = List.generate(14, (i) => (i >= 4 && i < 10) ? 0.7 : 0.2);
      final result = service.analyzeAudioFrame(decibel: 72.0, waveform: waveform);

      expect(result.category, YamnetSafetyCategory.crying);
      expect(result.severity, 'WARNING');
      expect(result.isWarning, isTrue);
      expect(result.yamnetClass, contains('/m/07p6fty'));
    });

    test('Phân loại Môi trường yên tĩnh an toàn bình thường (Ambient Normal)', () {
      final waveform = List.generate(14, (_) => 0.1);
      final result = service.analyzeAudioFrame(decibel: 45.0, waveform: waveform);

      expect(result.category, YamnetSafetyCategory.safeNormal);
      expect(result.severity, 'SAFE');
      expect(result.isCritical, isFalse);
      expect(result.isWarning, isFalse);
    });

    test('Hỗ trợ lấy kịch bản giả lập mô phỏng YAMNet đầy đủ mọi phân lớp', () {
      for (final cat in YamnetSafetyCategory.values) {
        final sim = service.getSimulatedResult(cat);
        expect(sim.category, cat);
        expect(sim.labelVi.isNotEmpty, isTrue);
        expect(sim.adviceVi.isNotEmpty, isTrue);
      }
    });
  });
}
