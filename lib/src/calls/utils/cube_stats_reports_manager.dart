import 'dart:async';

import 'package:connectycube_sdk/connectycube_calls.dart';
import 'package:connectycube_sdk/src/calls/models/call_base_session.dart';
import 'package:flutter/foundation.dart';

const MEDIA_TYPE_AUDIO = 'audio';
const MEDIA_TYPE_VIDEO = 'video';
const MIC_CORRECTION_COEFICIENT = 32767; //the maximum reproduced value

class CubeStatsReportsManager {
  final TAG = 'CubeStatsReportsManager';
  late BaseSession callSession;

  final StreamController<CubeMicLevelEvent> _micLevelStreamController =
      StreamController.broadcast();

  /// provides the opponents’ mic level from 0 to 1
  /// the feature is useful for detecting the talker and marking it on the UI
  Stream<CubeMicLevelEvent> get micLevelStream =>
      _micLevelStreamController.stream;

  final StreamController<CubeVideoBitrateEvent> _videoBitrateStreamController =
      StreamController.broadcast();

  /// provides the bitrate of the opponents’ video
  /// the feature is useful for detecting the connection quality and showing it on the UI
  Stream<CubeVideoBitrateEvent> get videoBitrateStream =>
      _videoBitrateStreamController.stream;

  Map<int, int?> _lastUserTimeStamps = {};
  Map<int, int?> _lastUserBytesReceived = {};

  init(BaseSession callSession) {
    callSession.statsReports.listen((statsReport) {
      var userId = statsReport.userId;
      var micLevel = getMicLevel(statsReport);
      var videoBitrate = getVideoBitrate(statsReport);

      _micLevelStreamController.add(CubeMicLevelEvent(userId, micLevel));
      _videoBitrateStreamController
          .add(CubeVideoBitrateEvent(userId, videoBitrate));
    });
  }

  dispose() {
    _micLevelStreamController.close();
    _videoBitrateStreamController.close();

    _lastUserTimeStamps.clear();
    _lastUserBytesReceived.clear();
  }

  double getMicLevel(CubeStatsReport report) {
    var micLevel;

    report.stats.forEach((statsReport) {
      if (statsReport.type == 'inbound-rtp') {
        if (MEDIA_TYPE_AUDIO == statsReport.values['mediaType'] ||
            MEDIA_TYPE_AUDIO == statsReport.values['kind']) {
          var volume = statsReport.values['audioLevel'];

          micLevel = volume;
        }
      } else if (statsReport.type == 'ssrc') {
        if (MEDIA_TYPE_AUDIO == statsReport.values['mediaType']) {
          var volume = statsReport.values['audioOutputLevel'];

          if (micLevel == null && volume != null) {
            micLevel = int.parse(volume) / MIC_CORRECTION_COEFICIENT;
          }
        }
      } else if (statsReport.type == 'media-source') {
        if (MEDIA_TYPE_AUDIO == statsReport.values['kind']) {
          var volume = statsReport.values['audioLevel'];

          if (micLevel == null && volume != null) {
            micLevel = double.parse(volume.toString());
          }
        }
      } else if (statsReport.type == 'track') {}
    });

    // log('REMOTE AUDIO MIC_LEVEL: $micLevel', TAG);

    return micLevel ?? 0.0;
  }

  int getVideoBitrate(CubeStatsReport report) {
    var timeStamp;
    var finalBytesReceived;

    report.stats.forEach((statsReport) {
      if (statsReport.type == 'inbound-rtp') {
        if (MEDIA_TYPE_VIDEO == statsReport.values['mediaType'] ||
            MEDIA_TYPE_VIDEO == statsReport.values['kind']) {
          var bytesReceived = statsReport.values['bytesReceived'];
          // var frameHeight = statsReport.values['frameHeight'];
          // var frameWidth = statsReport.values['frameWidth'];

          // log('REMOTE VIDEO resolution: $frameHeight x $frameWidth', TAG);

          finalBytesReceived = int.parse(bytesReceived.toString());
          timeStamp = statsReport.timestamp.floor();
        }
      } else if (statsReport.type == 'ssrc') {
        if (MEDIA_TYPE_VIDEO == statsReport.values['mediaType']) {
          var bytesReceived = statsReport.values['bytesReceived'];
          // var frameHeight = statsReport.values['googFrameHeightReceived'];
          // var frameWidth = statsReport.values['googFrameWidthReceived'];

          // log('REMOTE VIDEO resolution: $frameHeight x $frameWidth', TAG);

          if (finalBytesReceived == null && bytesReceived != null) {
            finalBytesReceived = int.parse(bytesReceived.toString());
            timeStamp = statsReport.timestamp.floor();
          }
        }
      } else if (statsReport.type == 'media-source') {
        if (MEDIA_TYPE_VIDEO == statsReport.values['kind']) {
          var bytesReceived = statsReport.values['bytesReceived'] ?? 0;
          // var frameHeight = statsReport.values['height'];
          // var frameWidth = statsReport.values['width'];

          // log('REMOTE VIDEO resolution: $frameHeight x $frameWidth', TAG);

          if (finalBytesReceived == null && bytesReceived != null) {
            finalBytesReceived = int.parse(bytesReceived.toString());
            timeStamp = statsReport.timestamp.floor();
          }
        }
      } else if (statsReport.type == 'track') {}
    });

    var previousTimestamp = _lastUserTimeStamps[report.userId];
    var previousBytesReceived = _lastUserBytesReceived[report.userId];

    if (!kIsWeb) {
      timeStamp = timeStamp ~/ 1000;
    }

    if (previousTimestamp == null || previousBytesReceived == null) {
      _lastUserTimeStamps[report.userId] = timeStamp;
      _lastUserBytesReceived[report.userId] = finalBytesReceived;
      return 0;
    }

    var timePassed = timeStamp - previousTimestamp;

    var bitRate;

    try {
      bitRate =
          (((finalBytesReceived - previousBytesReceived) * 8) / timePassed)
              .floor();
    } catch (e) {
      log('ERROR during calculate bitrate: $e ', TAG);
    }

    _lastUserTimeStamps[report.userId] = timeStamp;
    _lastUserBytesReceived[report.userId] = finalBytesReceived;

    // log('REMOTE VIDEO BIT_RATE: $bitRate ', TAG);

    return bitRate ?? 0;
  }
}

class CubeMicLevelEvent {
  final int userId;
  final double micLevel;

  CubeMicLevelEvent(this.userId, this.micLevel);
}

class CubeVideoBitrateEvent {
  final int userId;
  final int bitRate;

  CubeVideoBitrateEvent(this.userId, this.bitRate);
}
