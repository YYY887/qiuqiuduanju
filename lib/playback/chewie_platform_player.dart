import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:video_player/video_player.dart';

class ChewiePlatformPlayer extends PlatformPlayer {
  ChewiePlatformPlayer()
    : legacyPlayer = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 32 * 1024 * 1024,
          logLevel: MPVLogLevel.v,
        ),
      ),
      super(configuration: const PlayerConfiguration()) {
    completer.complete();
    for (final source in [
      legacyPlayer.stream.position,
      legacyPlayer.stream.duration,
      legacyPlayer.stream.buffer,
      legacyPlayer.stream.playing,
      legacyPlayer.stream.buffering,
      legacyPlayer.stream.rate,
      legacyPlayer.stream.volume,
      legacyPlayer.stream.completed,
      legacyPlayer.stream.videoParams,
    ]) {
      _legacySubscriptions.add(source.listen((_) => _syncLegacy()));
    }
    _legacySubscriptions.add(
      legacyPlayer.stream.error.listen((error) {
        if (_usingLegacy) errorController.add(error);
      }),
    );
  }

  final Player legacyPlayer;
  final List<StreamSubscription<dynamic>> _legacySubscriptions = [];
  VideoPlayerController? _controller;
  bool _usingLegacy = false;
  bool _initializingVideo = false;
  String? _lastError;

  VideoPlayerController? get videoController => _controller;
  bool get usingLegacy => _usingLegacy;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    if (playable is! Media) throw ArgumentError('需要单个媒体地址');
    await stop();
    final uri = Uri.parse(playable.uri);
    _usingLegacy =
        playable.extras?['decryptionKey'] is String &&
            (playable.extras!['decryptionKey'] as String).isNotEmpty ||
        !{'file', 'http', 'https'}.contains(uri.scheme);
    if (_usingLegacy) {
      await legacyPlayer.open(playable, play: play);
      _syncLegacy();
      return;
    }
    final controller = uri.scheme == 'file'
        ? VideoPlayerController.file(
            File.fromUri(uri),
            httpHeaders: playable.httpHeaders ?? const {},
          )
        : VideoPlayerController.networkUrl(
            uri,
            httpHeaders: playable.httpHeaders ?? const {},
          );
    _controller = controller;
    _initializingVideo = true;
    controller.addListener(_syncVideo);
    try {
      await controller.initialize();
      if (playable.start != null && playable.start! > Duration.zero) {
        await controller.seekTo(playable.start!);
      }
      await controller.setPlaybackSpeed(state.rate);
      await controller.setVolume(state.volume / 100);
      if (play) await controller.play();
      _initializingVideo = false;
      _syncVideo();
    } catch (_) {
      _initializingVideo = false;
      controller.removeListener(_syncVideo);
      _controller = null;
      await controller.dispose();
      _usingLegacy = true;
      await legacyPlayer.open(playable, play: play);
      _syncLegacy();
    }
  }

  void _syncLegacy() {
    if (!_usingLegacy) return;
    final previous = state;
    state = legacyPlayer.state;
    _publish(previous);
  }

  void _syncVideo() {
    final controller = _controller;
    if (controller == null || _usingLegacy) return;
    final value = controller.value;
    final previous = state;
    var buffered = Duration.zero;
    for (final range in value.buffered) {
      if (range.end > buffered) buffered = range.end;
    }
    final width = value.size.width.round();
    final height = value.size.height.round();
    state = state.copyWith(
      playing: value.isPlaying,
      completed: value.isCompleted,
      position: value.position,
      duration: value.duration,
      buffer: buffered,
      buffering: value.isBuffering,
      volume: value.volume * 100,
      rate: value.playbackSpeed,
      width: width > 0 ? width : null,
      height: height > 0 ? height : null,
      videoParams: width > 0 && height > 0
          ? VideoParams(
              w: width,
              h: height,
              dw: width,
              dh: height,
              aspect: value.aspectRatio,
            )
          : const VideoParams(),
    );
    _publish(previous);
    final error = value.errorDescription;
    if (!_initializingVideo &&
        error != null &&
        error.isNotEmpty &&
        error != _lastError) {
      _lastError = error;
      errorController.add(error);
    }
  }

  void _publish(PlayerState previous) {
    if (state.position != previous.position)
      positionController.add(state.position);
    if (state.duration != previous.duration)
      durationController.add(state.duration);
    if (state.buffer != previous.buffer) bufferController.add(state.buffer);
    if (state.playing != previous.playing) playingController.add(state.playing);
    if (state.buffering != previous.buffering)
      bufferingController.add(state.buffering);
    if (state.completed != previous.completed)
      completedController.add(state.completed);
    if (state.rate != previous.rate) rateController.add(state.rate);
    if (state.volume != previous.volume) volumeController.add(state.volume);
    if (state.videoParams != previous.videoParams)
      videoParamsController.add(state.videoParams);
  }

  @override
  Future<void> stop() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_syncVideo);
      await controller.dispose();
    }
    if (_usingLegacy) {
      await legacyPlayer.stop();
      _usingLegacy = false;
    }
    _lastError = null;
    final previous = state;
    state = const PlayerState();
    _publish(previous);
  }

  @override
  Future<void> play() async {
    if (_usingLegacy) return legacyPlayer.play();
    await _controller?.play();
    _syncVideo();
  }

  @override
  Future<void> pause() async {
    if (_usingLegacy) return legacyPlayer.pause();
    await _controller?.pause();
    _syncVideo();
  }

  @override
  Future<void> playOrPause() => state.playing ? pause() : play();

  @override
  Future<void> seek(Duration duration) async {
    if (_usingLegacy) return legacyPlayer.seek(duration);
    await _controller?.seekTo(duration);
    _syncVideo();
  }

  @override
  Future<void> setRate(double rate) async {
    if (_usingLegacy) return legacyPlayer.setRate(rate);
    if (_controller == null) {
      state = state.copyWith(rate: rate);
      rateController.add(rate);
      return;
    }
    await _controller!.setPlaybackSpeed(rate);
    _syncVideo();
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_usingLegacy) return legacyPlayer.setVolume(volume);
    if (_controller == null) {
      state = state.copyWith(volume: volume);
      volumeController.add(volume);
      return;
    }
    await _controller!.setVolume(volume / 100);
    _syncVideo();
  }

  @override
  Future<void> dispose() async {
    await stop();
    for (final subscription in _legacySubscriptions) {
      await subscription.cancel();
    }
    await legacyPlayer.dispose();
    await super.dispose();
  }
}
