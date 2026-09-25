import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../models/chronique.dart';

bool chroniqueMediaIsDisplayableVideo(ChroniqueMedia media) {
  if (media.kind != 'video') {
    return false;
  }
  if (media.status != 'ready') {
    return false;
  }
  final url = media.readUrl;
  return url != null && url.isNotEmpty;
}

List<ChroniqueMedia> displayableChroniqueVideos(Iterable<ChroniqueMedia> medias) {
  final videos = [
    for (final media in medias)
      if (chroniqueMediaIsDisplayableVideo(media)) media,
  ];
  videos.sort((a, b) {
    final order = (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0);
    if (order != 0) {
      return order;
    }
    return (a.id ?? 0).compareTo(b.id ?? 0);
  });
  return videos;
}

bool chroniqueVideoIsAtEnd(VideoPlayerValue value) {
  if (!value.isInitialized) {
    return false;
  }
  if (value.isCompleted) {
    return true;
  }
  final duration = value.duration;
  if (duration <= Duration.zero) {
    return false;
  }
  return value.position >= duration;
}

/// `true` → icône Pause ; `false` → icône Play.
bool chroniqueVideoShowsPauseIcon(VideoPlayerValue value) {
  if (!value.isInitialized || !value.isPlaying) {
    return false;
  }
  return !chroniqueVideoIsAtEnd(value);
}

String formatChroniqueVideoClock(Duration duration) {
  final total = duration.inSeconds.abs();
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:$mm:$ss';
  }
  return '$mm:$ss';
}

double chroniqueVideoSliderValue({
  required Duration position,
  required Duration duration,
  double? scrubMilliseconds,
}) {
  final maxMs = duration.inMilliseconds.toDouble();
  if (maxMs <= 0) {
    return 0;
  }
  final raw = scrubMilliseconds ?? position.inMilliseconds.toDouble();
  if (raw < 0) {
    return 0;
  }
  if (raw > maxMs) {
    return maxMs;
  }
  return raw;
}

Duration chroniqueVideoSeekTarget({
  required Duration duration,
  required double milliseconds,
}) {
  if (duration <= Duration.zero) {
    return Duration.zero;
  }
  final ms = milliseconds.round();
  if (ms <= 0) {
    return Duration.zero;
  }
  if (ms >= duration.inMilliseconds) {
    return duration;
  }
  return Duration(milliseconds: ms);
}

Future<void> toggleChroniqueVideoPlayback(VideoPlayerController controller) async {
  final value = controller.value;
  if (!value.isInitialized) {
    return;
  }
  if (chroniqueVideoShowsPauseIcon(value)) {
    await controller.pause();
    return;
  }
  if (chroniqueVideoIsAtEnd(value)) {
    await controller.seekTo(Duration.zero);
  }
  await controller.play();
}

/// Vidéos `ready` avec `read_url`. GET R2 signé, sans JWT.
class ChroniqueReadyVideoList extends StatelessWidget {
  const ChroniqueReadyVideoList({
    super.key,
    required this.medias,
  });

  final List<ChroniqueMedia> medias;

  @override
  Widget build(BuildContext context) {
    final videos = displayableChroniqueVideos(medias);
    if (videos.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < videos.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.lg),
          ChroniqueReadyVideoPlayer(
            key: ValueKey('chronique-ready-video-${videos[i].id ?? i}'),
            url: videos[i].readUrl!,
          ),
        ],
      ],
    );
  }
}

class ChroniqueReadyVideoPlayer extends StatefulWidget {
  const ChroniqueReadyVideoPlayer({
    super.key,
    required this.url,
  });

  final String url;

  @override
  State<ChroniqueReadyVideoPlayer> createState() => _ChroniqueReadyVideoPlayerState();
}

class _ChroniqueReadyVideoPlayerState extends State<ChroniqueReadyVideoPlayer> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _failed = false;
  bool _scrubbing = false;
  double? _scrubMilliseconds;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onControllerUpdate);
      setState(() {
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      await controller.dispose();
      if (!mounted) {
        return;
      }
      setState(() {
        _controller = null;
        _loading = false;
        _failed = true;
      });
    }
  }

  void _onControllerUpdate() {
    if (!mounted || _scrubbing) {
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    final controller = _controller;
    controller?.removeListener(_onControllerUpdate);
    controller?.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    await toggleChroniqueVideoPlayback(controller);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _seekTo(double milliseconds) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final target = chroniqueVideoSeekTarget(
      duration: controller.value.duration,
      milliseconds: milliseconds,
    );
    await controller.seekTo(target);
    if (!mounted) {
      return;
    }
    setState(() {
      _scrubbing = false;
      _scrubMilliseconds = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    if (_failed || _controller == null && !_loading) {
      return SizedBox(
        height: 72,
        child: Center(
          child: Text(
            'Vidéo indisponible',
            textAlign: TextAlign.center,
            style: AppTextTheme.labelSmall.copyWith(color: colors.danger),
          ),
        ),
      );
    }
    if (_loading || _controller == null || !_controller!.value.isInitialized) {
      return SizedBox(
        height: 180,
        child: Center(
          child: CircularProgressIndicator(
            color: colors.primary,
            strokeWidth: 2,
          ),
        ),
      );
    }

    final controller = _controller!;
    final value = controller.value;
    final size = value.size;
    final ratio = size.height == 0 ? 16 / 9 : size.width / size.height;
    final showPause = chroniqueVideoShowsPauseIcon(value);
    final duration = value.duration;
    final durationMs = duration.inMilliseconds.toDouble();
    final sliderValue = chroniqueVideoSliderValue(
      position: value.position,
      duration: duration,
      scrubMilliseconds: _scrubbing ? _scrubMilliseconds : null,
    );
    final displayPosition = _scrubbing && _scrubMilliseconds != null
        ? Duration(milliseconds: _scrubMilliseconds!.round())
        : value.position;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.lg),
          child: AspectRatio(
            aspectRatio: ratio <= 0 ? 16 / 9 : ratio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(controller),
                Material(
                  color: const Color(0x40000000),
                  child: IconButton(
                    key: const ValueKey('chronique-video-play-pause'),
                    tooltip: showPause ? 'Pause' : 'Lecture',
                    onPressed: _togglePlay,
                    icon: Icon(
                      showPause ? Icons.pause_circle : Icons.play_circle,
                      color: colors.textOnPrimary,
                      size: 48,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Text(
              formatChroniqueVideoClock(displayPosition),
              key: const ValueKey('chronique-video-position'),
              style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  key: const ValueKey('chronique-video-progress'),
                  min: 0,
                  max: durationMs > 0 ? durationMs : 1,
                  value: durationMs > 0 ? sliderValue : 0,
                  activeColor: colors.primary,
                  inactiveColor: colors.border,
                  onChanged: durationMs > 0
                      ? (next) {
                          setState(() {
                            _scrubbing = true;
                            _scrubMilliseconds = next;
                          });
                        }
                      : null,
                  onChangeEnd: durationMs > 0 ? _seekTo : null,
                ),
              ),
            ),
            Text(
              formatChroniqueVideoClock(duration),
              key: const ValueKey('chronique-video-duration'),
              style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ],
    );
  }
}
