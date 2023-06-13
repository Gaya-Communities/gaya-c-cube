import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:platform_device_id/platform_device_id.dart';

import '../auth/models/cube_session.dart';
import '../utils/consts.dart';
import '../utils/string_utils.dart';

class CubeSettings {
  String _versionName = "2.4.1";
  String? applicationId;
  String? authorizationKey;
  String? accountKey;

  String? authorizationSecret;

  String chatDefaultResource = "";

  bool isDebugEnabled = true;
  bool isJoinEnabled = false;
  bool autoMarkDelivered = true;

  String apiEndpoint = "https://api.connectycube.com";
  String chatEndpoint = "chat.connectycube.com";
  String whiteboardUrl = "https://whiteboard.connectycube.com";

  static final CubeSettings _instance = CubeSettings._internal();

  Future<CubeSession> Function()? onSessionRestore;

  CubeSettings._internal();

  static CubeSettings get instance => _instance;

  String get versionName => _versionName;

  init(
      String applicationId, String authorizationKey, String authorizationSecret,
      {Future<CubeSession> Function()? onSessionRestore}) async {
    this.applicationId = applicationId;
    this.authorizationKey = authorizationKey;
    this.authorizationSecret = authorizationSecret;
    this.onSessionRestore = onSessionRestore;

    await _initDefaultParams();
  }

  setEndpoints(String apiEndpoint, String chatEndpoint) {
    if (isEmpty(apiEndpoint) || isEmpty(chatEndpoint)) {
      throw ArgumentError(
          "'apiEndpoint' and(or) 'chatEndpoint' can not be empty or null");
    }

    if (!apiEndpoint.startsWith("http")) {
      apiEndpoint = "https://" + apiEndpoint;
    }

    this.apiEndpoint = apiEndpoint;
    this.chatEndpoint = chatEndpoint;
  }

  Future<void> _initResourceId() async {
    var resourceId = await PlatformDeviceId.getDeviceId;
    if (kIsWeb) {
      resourceId = base64Encode(utf8.encode(resourceId ?? ''));
    }
    this.chatDefaultResource = "$PREFIX_CHAT_RESOURCE\_$resourceId";
  }

  Future<void> _initDefaultParams() async {
    await _initResourceId();
  }
}
