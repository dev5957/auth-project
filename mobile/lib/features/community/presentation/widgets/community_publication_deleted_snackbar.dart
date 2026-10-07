import 'dart:async';

import 'package:flutter/material.dart';

const Duration kCommunityPublicationRestoreWindow = Duration(seconds: 20);

class _RestoreOnceGate {
  bool _started = false;

  bool tryStart() {
    if (_started) {
      return false;
    }
    _started = true;
    return true;
  }
}

void showCommunityPublicationDeletedSnackBar({
  required ScaffoldMessengerState messenger,
  required Future<void> Function() onRestore,
}) {
  final gate = _RestoreOnceGate();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: kCommunityPublicationRestoreWindow,
        persist: false,
        content: const CommunityPublicationDeletedCountdown(),
        action: SnackBarAction(
          key: const ValueKey('community-publication-restore-action'),
          label: 'Restaurer',
          onPressed: () {
            if (!gate.tryStart()) {
              return;
            }
            unawaited(() async {
              try {
                await onRestore();
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(content: Text('Publication restaurée')),
                  );
              } catch (_) {
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(content: Text('Impossible de restaurer')),
                  );
              }
            }());
          },
        ),
      ),
    );
}

class CommunityPublicationDeletedCountdown extends StatefulWidget {
  const CommunityPublicationDeletedCountdown({super.key});

  @override
  State<CommunityPublicationDeletedCountdown> createState() =>
      _CommunityPublicationDeletedCountdownState();
}

class _CommunityPublicationDeletedCountdownState
    extends State<CommunityPublicationDeletedCountdown> {
  Timer? _timer;
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = kCommunityPublicationRestoreWindow.inSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      final next = _remainingSeconds - 1;
      if (next <= 0) {
        _timer?.cancel();
        _timer = null;
        setState(() => _remainingSeconds = 0);
        return;
      }
      setState(() => _remainingSeconds = next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final countdown = _remainingSeconds > 0 ? '${_remainingSeconds}s' : '';
    return Row(
      children: [
        const Flexible(child: Text('Publication supprimée')),
        if (countdown.isNotEmpty) ...[
          const Text(' · '),
          Text(
            countdown,
            key: const ValueKey('community-publication-restore-countdown'),
          ),
        ],
      ],
    );
  }
}
