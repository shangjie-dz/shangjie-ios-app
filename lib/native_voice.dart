import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 讯飞语音（听写 + 播报），协议参数严格对齐现有安卓版 VoiceIat / VoiceTts。
///
/// 安全：应用密钥不下发客户端，鉴权地址（authUrl）由云端函数 xfyun_auth 签发，
/// 网页通过 voiceSigned / speakSigned 传入，本模块只负责录音上行 / 音频下行播放。
///
/// 录音采用 16k 单声道 PCM，通过 iOS 原生（MethodChannel）实现，
/// 因为 Flutter 直接用 dart 录音需要额外插件；为控制复杂度，录音走原生桥。
class NativeVoice {
  static const MethodChannel _channel = MethodChannel('psc/voice');

  /// 语音听写（说话转文字）
  /// 返回 {ok:true, text:...} 或 {ok:false, reason/message}
  static Future<Map<String, dynamic>> listen({
    required String? authUrl,
    required String? appId,
  }) async {
    if (authUrl == null || authUrl.trim().isEmpty) {
      return {'ok': false, 'reason': 'error', 'message': '语音鉴权失败：请检查网络后重试'};
    }

    try {
      // 1. 原生开始录音（16k 单声道 PCM，返回句柄）
      try {
        await _channel.invokeMethod('startRecord');
      } catch (e) {
        return {'ok': false, 'reason': 'error', 'message': '麦克风初始化失败'};
      }

      // 2. 连讯飞 wss，逐帧上行
      final channel = WebSocketChannel.connect(Uri.parse(authUrl));
      final textBuf = StringBuffer();
      final completer = Completer<String?>();
      String? serverErr;

      channel.stream.listen((data) {
        try {
          final o = jsonDecode(data as String) as Map<String, dynamic>;
          if (o['code'] != null && o['code'] != 0) {
            serverErr = '讯飞返回错误 ${o['code']}：${o['message']}';
            if (!completer.isCompleted) completer.complete(null);
            return;
          }
          final d = o['data'] as Map<String, dynamic>?;
          if (d == null) return;
          final result = d['result'] as Map<String, dynamic>?;
          if (result != null) {
            final wsArr = result['ws'] as List?;
            if (wsArr != null) {
              for (final w in wsArr) {
                final cw = (w as Map)['cw'] as List?;
                if (cw == null) continue;
                for (final c in cw) {
                  textBuf.write((c as Map)['w'] ?? '');
                }
              }
            }
          }
          if (d['status'] == 2) {
            if (!completer.isCompleted) completer.complete(textBuf.toString());
          }
        } catch (_) {}
      }, onError: (e) {
        serverErr = '语音服务连不上：$e';
        if (!completer.isCompleted) completer.complete(null);
      }, onDone: () {
        if (!completer.isCompleted) completer.complete(textBuf.toString());
      });

      // 3. 逐帧上行录音（40ms 一帧，最长 8 秒）
      final stopwatch = Stopwatch()..start();
      bool first = true;
      const maxMs = 8000;
      // 每帧 1280 字节 = 40ms @16k 16bit mono

      try {
        while (stopwatch.elapsedMilliseconds < maxMs && !completer.isCompleted) {
          final frame = await _channel.invokeMethod<Uint8List>('readFrame');
          if (frame == null || frame.isEmpty) {
            await Future.delayed(const Duration(milliseconds: 40));
            continue;
          }
          final audio = base64Encode(frame);
          final dataObj = {
            'status': first ? 0 : 1,
            'format': 'audio/L16;rate=16000',
            'encoding': 'raw',
            'audio': audio,
          };
          final frameObj = <String, dynamic>{};
          if (first) {
            frameObj['common'] = {'app_id': appId ?? ''};
            frameObj['business'] = {
              'language': 'zh_cn',
              'domain': 'iat',
              'accent': 'mandarin',
              'vad_eos': 2000,
              'ptt': 0,
            };
          }
          frameObj['data'] = dataObj;
          channel.sink.add(jsonEncode(frameObj));
          first = false;
        }

        // 结束帧
        channel.sink.add(jsonEncode({
          'data': {
            'status': 2,
            'format': 'audio/L16;rate=16000',
            'encoding': 'raw',
            'audio': '',
          },
        }));
      } catch (e) {
        serverErr = '语音识别出错：$e';
        if (!completer.isCompleted) completer.complete(null);
      }

      // 4. 等服务端最终结果（最多再等 5 秒）
      final text = await completer.future.timeout(const Duration(seconds: 5), onTimeout: () => textBuf.toString());

      // 5. 停录音
      await _channel.invokeMethod('stopRecord');
      await channel.sink.close();

      if (serverErr != null) {
        return {'ok': false, 'reason': 'error', 'message': serverErr};
      }
      if (text == null || text.isEmpty) {
        return {'ok': false, 'reason': 'error', 'message': '没听清，请靠近麦克风再说一次'};
      }
      return {'ok': true, 'text': text};
    } catch (e) {
      return {'ok': false, 'reason': 'error', 'message': '语音识别出错：$e'};
    }
  }

  /// 语音播报（文字念出来）
  /// 返回 void（出声），失败静默
  static Future<void> speak({
    required String? text,
    required String? authUrl,
    required String? appId,
  }) async {
    if (text == null || text.trim().isEmpty) return;
    if (authUrl == null || authUrl.trim().isEmpty) return;

    try {
      final channel = WebSocketChannel.connect(Uri.parse(authUrl));

      final common = {'app_id': appId ?? ''};
      final business = {
        'aue': 'lame', // MP3
        'sfl': 1, // 流式
        'auf': 'audio/L16;rate=16000',
        'vcn': 'xiaorong', // 小蓉（温婉女声）
        'speed': 50,
        'volume': 60,
        'pitch': 50,
        'tte': 'UTF8',
      };
      final data = {
        'status': 2, // 一次性整句
        'text': base64Encode(utf8.encode(text)),
      };

      channel.sink.add(jsonEncode({
        'common': common,
        'business': business,
        'data': data,
      }));

      // 收集 MP3 帧，交给原生播放
      final frames = <Uint8List>[];
      final completer = Completer<void>();

      channel.stream.listen((d) {
        try {
          final o = jsonDecode(d as String) as Map<String, dynamic>;
          if (o['code'] != null && o['code'] != 0) {
            if (!completer.isCompleted) completer.complete();
            return;
          }
          final dd = o['data'] as Map<String, dynamic>?;
          if (dd != null) {
            final b64 = dd['audio'] as String?;
            if (b64 != null && b64.isNotEmpty) {
              frames.add(base64Decode(b64));
            }
            if (dd['status'] == 2) {
              if (!completer.isCompleted) completer.complete();
            }
          }
        } catch (_) {}
      }, onError: (_) {
        if (!completer.isCompleted) completer.complete();
      }, onDone: () {
        if (!completer.isCompleted) completer.complete();
      });

      await completer.future.timeout(const Duration(seconds: 8));
      await channel.sink.close();

      // 把 MP3 帧交给原生播放
      if (frames.isNotEmpty) {
        await _channel.invokeMethod('playMp3', {
          'frames': frames.map((f) => base64Encode(f)).toList(),
        });
      }
    } catch (_) {
      // 播报失败静默，不影响业务
    }
  }
}
