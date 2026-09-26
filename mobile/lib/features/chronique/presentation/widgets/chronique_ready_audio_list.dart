import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../models/chronique.dart';
import 'chronique_ready_video_list.dart';

bool chroniqueMediaIsDisplayableAudio(ChroniqueMedia media) {
  if (media.kind != 'audio') {
    return false;
  }
  if (media.status != 'ready') {
    return false;
  }
  final url = media.readUrl;
  return url != null && url.isNotEmpty;
}

List<ChroniqueMedia> displayableChroniqueAudios(Iterable<ChroniqueMedia> medias) {
  final audios = [
    for (final media in medias)
      if (chroniqueMediaIsDisplayableAudio(media)) media,
  ];
  audios.sort((a, b) {
    final order = (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0);
    if (order != 0) {
      return order;
    }
    return (a.id ?? 0).compareTo(b.id ?? 0);
  });
  return audios;
}

String formatChroniqueAudioClock(Duration duration) => formatChroniqueVideoClock(duration);

bool chroniqueAudioIsAtEnd({
  required ProcessingState processingState,
  Duration? position,
  Duration? duration,
}) {
  if (processingState == ProcessingState.completed) {
    return true;
  }
  if (duration == null || duration <= Duration.zero) {
    return false;
  }
  if (position == null) {
    return false;
  }
  return position >= duration;
}

/// `true` → icône Pause ; `false` → icône Play. État réel du player, pas un booléen local isolé.
bool chroniqueAudioShowsPauseIcon({
  required bool playing,
  required ProcessingState processingState,
  Duration? position,
  Duration? duration,
}) {
  if (!playing) {
    return false;
  }
  return !chroniqueAudioIsAtEnd(
    processingState: processingState,
    position: position,
    duration: duration,
  );
}

Future<void> toggleChroniqueAudioPlayback({
  required AudioPlayer player,
  required bool playing,
  required ProcessingState processingState,
  Duration? position,
  Duration? duration,
}) async {
  if (chroniqueAudioShowsPauseIcon(
    playing: playing,
    processingState: processingState,
    position: position,
    duration: duration,
  )) {
    await player.pause();
    return;
  }
  if (chroniqueAudioIsAtEnd(
    processingState: processingState,
    position: position,
    duration: duration,
  )) {
    await player.seek(Duration.zero);
  }
  await player.play();
}

AudioPlayer? _exclusiveChroniqueAudioPlayer;

void claimChroniqueAudioPlayback(AudioPlayer player) {
  final previous = _exclusiveChroniqueAudioPlayer;
  _exclusiveChroniqueAudioPlayer = player;
  if (previous != null && !identical(previous, player)) {
    unawaited(previous.pause());
  }
}

void releaseChroniqueAudioPlayback(AudioPlayer player) {
  if (identical(_exclusiveChroniqueAudioPlayer, player)) {
    _exclusiveChroniqueAudioPlayer = null;
  }
}

/// Audios `ready` avec `read_url`. GET R2 signé, sans JWT.
class ChroniqueReadyAudioList extends StatelessWidget {
  const ChroniqueReadyAudioList({
    super.key,
    required this.medias,
  });

  final List<ChroniqueMedia> medias;

  @override
  Widget build(BuildContext context) {
    final audios = displayableChroniqueAudios(medias);
    if (audios.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < audios.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.lg),
          ChroniqueReadyAudioPlayer(
            key: ValueKey('chronique-ready-audio-${audios[i].id ?? i}'),
            url: audios[i].readUrl!,
          ),
        ],
      ],
    );
  }
}

class ChroniqueReadyAudioPlayer extends StatefulWidget {
  const ChroniqueReadyAudioPlayer({
    super.key,
    required this.url,
  });

  final String url;

  @override
  State<ChroniqueReadyAudioPlayer> createState() => _ChroniqueReadyAudioPlayerState();
}

class _ChroniqueReadyAudioPlayerState extends State<ChroniqueReadyAudioPlayer> {
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  bool _loading = true;
  bool _failed = false;
  bool _scrubbing = false;
  double? _scrubMilliseconds;
  Duration _position = Duration.zero;
  Duration? _duration;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final player = AudioPlayer();
    _player = player;
    try {
      await player.setUrl(widget.url);
      if (!mounted) {
        await player.dispose();
        return;
      }
      _stateSub = player.playerStateStream.listen((_) {
        if (mounted && !_scrubbing) {
          setState(() {});
        }
      });
      _positionSub = player.positionStream.listen((position) {
        if (!mounted || _scrubbing) {
          return;
        }
        setState(() => _position = position);
      });
      _durationSub = player.durationStream.listen((duration) {
        if (!mounted) {
          return;
        }
        setState(() => _duration = duration);
      });
      setState(() {
        _loading = false;
        _failed = false;
        _duration = player.duration;
        _position = player.position;
      });
    } catch (_) {
      await player.dispose();
      releaseChroniqueAudioPlayback(player);
      if (!mounted) {
        return;
      }
      setState(() {
        _player = null;
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  void dispose() {
    final player = _player;
    unawaited(_stateSub?.cancel());
    unawaited(_positionSub?.cancel());
    unawaited(_durationSub?.cancel());
    if (player != null) {
      releaseChroniqueAudioPlayback(player);
      unawaited(player.dispose());
    }
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final player = _player;
    if (player == null) {
      return;
    }
    final state = player.playerState;
    if (!chroniqueAudioShowsPauseIcon(
      playing: state.playing,
      processingState: state.processingState,
      position: _position,
      duration: _duration ?? player.duration,
    )) {
      claimChroniqueAudioPlayback(player);
    }
    await toggleChroniqueAudioPlayback(
      player: player,
      playing: state.playing,
      processingState: state.processingState,
      position: _position,
      duration: _duration ?? player.duration,
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _seekTo(double milliseconds) async {
    final player = _player;
    final duration = _duration ?? player?.duration;
    if (player == null || duration == null || duration <= Duration.zero) {
      if (mounted) {
        setState(() {
          _scrubbing = false;
          _scrubMilliseconds = null;
        });
      }
      return;
    }
    final target = chroniqueVideoSeekTarget(
      duration: duration,
      milliseconds: milliseconds,
    );
    await player.seek(target);
    if (!mounted) {
      return;
    }
    setState(() {
      _position = target;
      _scrubbing = false;
      _scrubMilliseconds = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    if (_failed || _player == null && !_loading) {
      return SizedBox(
        height: 72,
        child: Center(
          child: Text(
            'Audio indisponible',
            textAlign: TextAlign.center,
            style: AppTextTheme.labelSmall.copyWith(color: colors.danger),
          ),
        ),
      );
    }
    if (_loading || _player == null) {
      return SizedBox(
        height: 72,
        child: Center(
          child: CircularProgressIndicator(
            color: colors.primary,
            strokeWidth: 2,
          ),
        ),
      );
    }

    final player = _player!;
    final state = player.playerState;
    final duration = _duration ?? player.duration;
    final showPause = chroniqueAudioShowsPauseIcon(
      playing: state.playing,
      processingState: state.processingState,
      position: _position,
      duration: duration,
    );
    final durationOrZero = duration ?? Duration.zero;
    final durationMs = durationOrZero.inMilliseconds.toDouble();
    final sliderValue = chroniqueVideoSliderValue(
      position: _position,
      duration: durationOrZero,
      scrubMilliseconds: _scrubbing ? _scrubMilliseconds : null,
    );
    final displayPosition = _scrubbing && _scrubMilliseconds != null
        ? Duration(milliseconds: _scrubMilliseconds!.round())
        : _position;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgRaised,
        borderRadius: BorderRadius.circular(AppSpacing.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('chronique-audio-play-pause'),
              tooltip: showPause ? 'Pause' : 'Lecture',
              onPressed: _togglePlay,
              icon: Icon(
                showPause ? Icons.pause_circle : Icons.play_circle,
                color: colors.primary,
                size: 40,
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      key: const ValueKey('chronique-audio-progress'),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          formatChroniqueAudioClock(displayPosition),
                          key: const ValueKey('chronique-audio-position'),
                          style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                        ),
                        Text(
                          formatChroniqueAudioClock(durationOrZero),
                          key: const ValueKey('chronique-audio-duration'),
                          style: AppTextTheme.labelSmall.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
