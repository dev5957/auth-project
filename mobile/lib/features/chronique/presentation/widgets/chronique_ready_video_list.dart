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

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) {
      setState(() {});
    }
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
    final size = controller.value.size;
    final ratio = size.height == 0 ? 16 / 9 : size.width / size.height;
    return ClipRRect(
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
                tooltip: controller.value.isPlaying ? 'Pause' : 'Lecture',
                onPressed: _togglePlay,
                icon: Icon(
                  controller.value.isPlaying ? Icons.pause_circle : Icons.play_circle,
                  color: colors.textOnPrimary,
                  size: 48,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
