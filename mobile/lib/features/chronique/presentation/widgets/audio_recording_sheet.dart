import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../media/chronique_local_media_picker.dart';
import '../../media/chronique_microphone_recorder.dart';

enum _AudioRecordUiState { ready, recording, stopped }

/// Enregistrement micro : prêt → enregistrement → confirmation.
Future<MediaPickResult> showChroniqueAudioRecordingSheet(
  BuildContext context, {
  required ChroniqueMicrophoneRecorder recorder,
}) async {
  final result = await showModalBottomSheet<MediaPickResult>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    isDismissible: false,
    builder: (context) {
      return _AudioRecordingSheet(recorder: recorder);
    },
  );
  return result ?? const MediaPickCancelled();
}

class _AudioRecordingSheet extends StatefulWidget {
  const _AudioRecordingSheet({required this.recorder});

  final ChroniqueMicrophoneRecorder recorder;

  @override
  State<_AudioRecordingSheet> createState() => _AudioRecordingSheetState();
}

class _AudioRecordingSheetState extends State<_AudioRecordingSheet> {
  _AudioRecordUiState _ui = _AudioRecordUiState.ready;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  MediaPickSelected? _capture;
  bool _busy = false;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    _elapsed = Duration.zero;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  String _clock() {
    final minutes = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _onRecord() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final allowed = await widget.recorder.hasPermission();
      if (!allowed) {
        _pop(const MediaPickFailed(kMicrophoneAccessDeniedMessage));
        return;
      }
      await widget.recorder.start();
      if (!mounted) {
        return;
      }
      _startTicker();
      setState(() {
        _ui = _AudioRecordUiState.recording;
        _capture = null;
      });
    } on Exception {
      _pop(const MediaPickFailed(kMediaInaccessibleMessage));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _onStop() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    _stopTicker();
    try {
      final result = await widget.recorder.stop();
      if (!mounted) {
        return;
      }
      switch (result) {
        case MediaPickCancelled():
          _pop(const MediaPickCancelled());
        case MediaPickFailed():
          _pop(result);
        case MediaPickSelected():
          setState(() {
            _ui = _AudioRecordUiState.stopped;
            _capture = result;
          });
        case MediaPickMany(:final items):
          if (items.length == 1) {
            setState(() {
              _ui = _AudioRecordUiState.stopped;
              _capture = items.single;
            });
          } else {
            _pop(const MediaPickFailed(kMediaInaccessibleMessage));
          }
      }
    } on Exception {
      _pop(const MediaPickFailed(kMediaInaccessibleMessage));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _onCancel() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    _stopTicker();
    try {
      await widget.recorder.discard();
    } on Exception {
      // Annulation : on ferme quand même.
    }
    _pop(const MediaPickCancelled());
  }

  void _onConfirm() {
    final capture = _capture;
    if (capture == null) {
      return;
    }
    widget.recorder.keep();
    _pop(capture);
  }

  void _pop(MediaPickResult result) {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final title = switch (_ui) {
      _AudioRecordUiState.ready => '🎙️ Prêt à enregistrer',
      _AudioRecordUiState.recording => '🔴 Enregistrement',
      _AudioRecordUiState.stopped => '🎙️ Enregistrement prêt',
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: AppTextTheme.titleMedium.copyWith(color: colors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _clock(),
              key: const ValueKey('audio-record-elapsed'),
              style: AppTextTheme.titleLarge.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_ui == _AudioRecordUiState.ready)
              AppButton(
                key: const ValueKey('audio-record-start'),
                label: 'Enregistrer',
                onPressed: _busy ? null : _onRecord,
              ),
            if (_ui == _AudioRecordUiState.recording) ...[
              AppButton(
                key: const ValueKey('audio-record-stop'),
                label: 'Arrêter',
                onPressed: _busy ? null : _onStop,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                key: const ValueKey('audio-record-cancel'),
                label: 'Annuler',
                variant: AppButtonVariant.secondary,
                onPressed: _busy ? null : _onCancel,
              ),
            ],
            if (_ui == _AudioRecordUiState.stopped) ...[
              AppButton(
                key: const ValueKey('audio-record-confirm'),
                label: 'Ajouter',
                onPressed: _busy ? null : _onConfirm,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                key: const ValueKey('audio-record-cancel'),
                label: 'Annuler',
                variant: AppButtonVariant.secondary,
                onPressed: _busy ? null : _onCancel,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
