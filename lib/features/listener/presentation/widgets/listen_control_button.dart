import 'package:flutter/material.dart';

import '../../../../core/widgets/sonic_button.dart';

/// The primary session action for the listener screen. While a session is live
/// it leaves the session; once the session has [ended] it becomes a
/// "back to sessions" affordance. Both close signaling and dispose the peer
/// connection via [onLeave].
class ListenControlButton extends StatelessWidget {
  const ListenControlButton({
    required this.ended,
    required this.onLeave,
    super.key,
  });

  final bool ended;
  final Future<void> Function() onLeave;

  @override
  Widget build(BuildContext context) {
    return SonicButton(
      label: ended ? 'Back to sessions' : 'Leave session',
      icon: ended ? Icons.arrow_back_rounded : Icons.logout_rounded,
      isSecondary: !ended,
      onPressed: onLeave,
    );
  }
}
