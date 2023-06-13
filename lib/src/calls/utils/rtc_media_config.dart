class RTCMediaConfig {
  static final RTCMediaConfig _instance = RTCMediaConfig._internal();

  RTCMediaConfig._internal();

  static RTCMediaConfig get instance => _instance;

  int minWidth = 480;
  int minHeight = 320;
  int minFrameRate = 25;

  // the initial maximum bandwidth in kbps, set to 0 or null for disabling the limitation
  // change it during the call via `callSession.setMaxBandwidth(512)`
  int? maxBandwidth = 0;
}
