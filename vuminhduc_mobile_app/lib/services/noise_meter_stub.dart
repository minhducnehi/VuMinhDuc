class NoiseMeterService {
  static final NoiseMeterService instance = NoiseMeterService._internal();
  NoiseMeterService._internal();

  bool isSupported() => false;
  bool isListening() => false;
  Future<bool> startListening({double sensitivity = 1.0}) async => false;
  void setSensitivity(double sensitivity) {}
  void stopListening() {}
  double getDecibel() => 0.0;
  List<double> getWaveform() => [];
}
