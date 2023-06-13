import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../connectycube_calls.dart';
import '../peer_connection.dart';

abstract class BaseSession<C, P extends PeerConnection>
    implements BaseCallSession, CubePeerConnectionStateCallback {
  static const String _TAG = "BaseSession";
  @override
  LocalStreamCallback? onLocalStreamReceived;
  @override
  RemoteStreamCallback<BaseSession>? onRemoteStreamReceived;
  @override
  RemoteStreamCallback<BaseSession>? onRemoteStreamRemoved;
  @override
  SessionClosedCallback<BaseSession>? onSessionClosed;
  @protected
  final C client;
  @protected
  MediaStream? localStream;
  @protected
  Map<int, P> channels = {};

  RTCSessionState? state;

  RTCSessionStateCallback? _connectionCallback;

  bool startScreenSharing = false;
  DesktopCapturerSource? desktopCapturerSource;
  bool useIOSBroadcasting = false;

  late StreamController<CubeStatsReport> _statsReportsStreamController =
      StreamController.broadcast();

  Stream<CubeStatsReport> get statsReports =>
      _statsReportsStreamController.stream;

  BaseSession(this.client,
      {this.startScreenSharing = false,
      this.desktopCapturerSource,
      this.useIOSBroadcasting = false});

  setSessionCallbacksListener(RTCSessionStateCallback callback) {
    _connectionCallback = callback;
  }

  removeSessionCallbacksListener() {
    _connectionCallback = null;
  }

  @protected
  void setState(RTCSessionState state) {
    if (this.state != state) {
      this.state = state;
    }
  }

  Future<MediaStream> initLocalMediaStream() async {
    return _createStream(startScreenSharing).then((mediaStream) {
      localStream = mediaStream;

      this.onLocalStreamReceived?.call(localStream!);

      return Future.value(localStream);
    });
  }

  Future<MediaStream> _createStream(bool isScreenSharing) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
    };

    if (CallType.VIDEO_CALL == callType) {
      RTCMediaConfig mediaConfig = RTCMediaConfig.instance;
      mediaConstraints['video'] = {
        'mandatory': {
          'minWidth': mediaConfig.minWidth,
          'minHeight': mediaConfig.minHeight,
          'minFrameRate': mediaConfig.minFrameRate,
        },
        'facingMode': 'user',
        'optional': [],
      };
    }

    return isScreenSharing
        ? navigator.mediaDevices.getDisplayMedia(<String, dynamic>{
            'audio': true,
            'video': desktopCapturerSource != null
                ? {
                    'deviceId': {'exact': desktopCapturerSource!.id},
                    'mandatory': {'frameRate': 30.0}
                  }
                : !kIsWeb && Platform.isIOS && useIOSBroadcasting
                    ? {'deviceId': 'broadcast'}
                    : true
          })
        : navigator.mediaDevices.getUserMedia(mediaConstraints);
  }

  @override
  Future<MediaStream?> getLocalMediaStream() {
    if (localStream != null) return Future.value(localStream);

    return initLocalMediaStream();
  }

  @override
  void onRemoteStreamReceive(int userId, MediaStream remoteMediaStream) {
    if (onRemoteStreamReceived != null) {
      onRemoteStreamReceived!(this, userId, remoteMediaStream);
    }
  }

  @override
  void onRemoteStreamRemove(int userId, MediaStream remoteMediaStream) {
    if (onRemoteStreamRemoved != null) {
      onRemoteStreamRemoved!(this, userId, remoteMediaStream);
    }
  }

  @override
  void onIceGatheringStateChanged(int userId, RTCIceGatheringState state) {
    log("onIceGatheringStateChanged state= $state for userId= $userId", _TAG);
  }

  @override
  void onStatsReceived(int userId, List<StatsReport> stats) {
    _statsReportsStreamController.add(CubeStatsReport(userId, stats));
  }

  /// For web implementation, make sure to pass the target deviceId
  @override
  Future<bool> switchCamera({String? deviceId}) {
    if (CallType.VIDEO_CALL != callType)
      return Future.error(IllegalStateException(
          "Can't perform operation [switchCamera] for AUDIO call"));

    try {
      if (localStream == null) {
        return Future.error(IllegalStateException(
            "Can't perform operation [switchCamera], cause 'localStream' not initialised"));
      } else {
        final videoTrack = localStream!
            .getVideoTracks()
            .firstWhere((track) => track.kind == 'video');
        return Helper.switchCamera(videoTrack, deviceId, localStream);
      }
    } catch (error) {
      return Future.error(error);
    }
  }

  @override
  Future<void> setTorchEnabled(bool enabled) {
    if (CallType.VIDEO_CALL != callType)
      return Future.error(IllegalStateException(
          "Can't perform operation [setTorchEnabled] for AUDIO call"));

    try {
      if (localStream == null) {
        return Future.error(IllegalStateException(
            "Can't perform operation [setTorchEnabled], cause 'localStream' not initialised"));
      } else {
        final videoTrack = localStream!
            .getVideoTracks()
            .firstWhere((track) => track.kind == 'video');
        return videoTrack.hasTorch().then((has) {
          if (has) {
            return videoTrack.setTorch(enabled);
          } else {
            return Future.error(IllegalStateException(
                "Can't perform operation  [setTorchEnabled], cause current camera does not support torch mode"));
          }
        });
      }
    } catch (error) {
      return Future.error(error);
    }
  }

  @override
  void setVideoEnabled(bool enabled) {
    if (CallType.VIDEO_CALL != callType) {
      log("Can't perform operation [setVideoEnabled] for AUDIO call");
      return;
    }

    if (localStream == null) {
      log("Can't perform operation [setVideoEnabled], cause 'localStream' not initialised");
      return;
    }

    final videoTrack = localStream!
        .getVideoTracks()
        .firstWhere((track) => track.kind == 'video');

    videoTrack.enabled = enabled;
  }

  @override
  void setMicrophoneMute(bool mute) {
    if (localStream == null) {
      log("Can't perform operation [setMicrophoneMute], cause 'localStream' not initialised");
      return;
    }

    final audioTrack = localStream!
        .getAudioTracks()
        .firstWhere((track) => track.kind == 'audio');

    Helper.setMicrophoneMute(mute, audioTrack);
  }

  @override
  void enableSpeakerphone(bool enable) {
    if (localStream == null) {
      log("Can't perform operation [enableSpeakerphone], cause 'localStream' not initialised");
      return;
    }

    final audioTrack = localStream!
        .getAudioTracks()
        .firstWhere((track) => track.kind == 'audio');

    audioTrack.enableSpeakerphone(enable);
  }

  /// Enables/disables the Screen Sharing feature.
  /// [enable] - `true` - for enabling Screen Sharing or `false` - for disabling.
  /// [desktopCapturerSource] - the desktop capturer source, if it is `null` the
  ///  default Window/Screen will be captured. Use only for desktop platforms.
  ///  Use [ScreenSelectDialog] to give the user a choice of the shared Window/Screen.
  /// [useIOSBroadcasting] - set `true` if the `Broadcast Upload Extension` was
  /// added to your iOS project for implementation Screen Sharing feature, otherwise
  /// set `false` and `in-app` Screen Sharing will be started. Used for iOS platform only.
  /// See our [step-by-step guide](https://developers.connectycube.com/flutter/videocalling?id=ios-screen-sharing-using-the-screen-broadcasting-feature)
  /// on how to integrate the Screen Broadcasting feature into your iOS app.
  @override
  Future<void> enableScreenSharing(bool enable,
      {DesktopCapturerSource? desktopCapturerSource,
      bool useIOSBroadcasting = false}) {
    this.desktopCapturerSource = desktopCapturerSource;
    this.useIOSBroadcasting = useIOSBroadcasting;

    return _createStream(enable).then((mediaStream) {
      return replaceMediaStream(mediaStream);
    });
  }

  @override
  Future<void> replaceMediaStream(MediaStream mediaStream) async {
    try {
      if (kIsWeb) {
        localStream?.getTracks().forEach((track) => track.stop());
      }

      await localStream?.dispose();
    } catch (error) {
      log("[replaceMediaStream] error: $error", _TAG);
    }

    localStream = mediaStream;

    channels.forEach((userId, peerConnection) async {
      await peerConnection.replaceMediaStream(localStream!);
    });

    this.onLocalStreamReceived?.call(localStream!);
  }

  /// Sets maximum bandwidth for the local media stream
  /// [bandwidth] - the bandwidth in kbps, set to 0 or null for disabling the limitation
  @override
  void setMaxBandwidth(int? bandwidth) {
    channels.forEach((userId, peerConnection) {
      peerConnection.setMaxBandwidth(bandwidth);
    });
  }

  Future<List<MediaDeviceInfo>> getCameras() {
    return Helper.cameras;
  }

  Future<List<MediaDeviceInfo>> getAudioOutputs() {
    return Helper.audiooutputs;
  }

  @override
  void onPeerConnectionStateChanged(int userId, PeerConnectionState state) {
    switch (state) {
      case PeerConnectionState.RTC_CONNECTION_CONNECTED:
        setState(RTCSessionState.RTC_SESSION_CONNECTED);
        _connectionCallback?.onConnectedToUser(this, userId);
        break;
      case PeerConnectionState.RTC_CONNECTION_DISCONNECTED:
        _connectionCallback?.onDisconnectedFromUser(this, userId);
        break;
      case PeerConnectionState.RTC_CONNECTION_CLOSED:
        closeConnectionForOpponent(userId, null);
        _connectionCallback?.onConnectionClosedForUser(this, userId);
        break;
      case PeerConnectionState.RTC_CONNECTION_FAILED:
        closeConnectionForOpponent(userId, null);
        break;
      default:
        break;
    }
  }

  void closeConnectionForOpponent(
    int opponentId,
    Function(int opponentId)? callback,
  ) {
    PeerConnection? peerConnection = channels[opponentId];
    if (peerConnection == null) return;

    peerConnection.close();
    channels.remove(opponentId);

    if (callback != null) {
      callback(opponentId);
    }

    log(
      "closeConnectionForOpponent, "
      "_channels.length = ${channels.length}",
      _TAG,
    );

    if (channels.length == 0) {
      closeCurrentSession();
    } else {
      log(
        "closeConnectionForOpponent, "
        "left channels = ${channels.keys.join(", ")}",
        _TAG,
      );
    }
  }

  Future<void> closeCurrentSession() async {
    log("closeCurrentSession", _TAG);
    setState(RTCSessionState.RTC_SESSION_CLOSED);
    if (localStream != null) {
      log("[closeCurrentSession] dispose localStream", _TAG);
      try {
        if (kIsWeb) {
          localStream?.getTracks().forEach((track) => track.stop());
        }

        await localStream?.dispose();
      } catch (error) {
        log('closeCurrentSession ERROR: $error');
      }

      localStream = null;
    }

    _statsReportsStreamController.close();

    notifySessionClosed();
  }

  void notifySessionClosed() {
    log("_notifySessionClosed", _TAG);
    if (onSessionClosed != null) {
      onSessionClosed!(this);
    }
  }
}
