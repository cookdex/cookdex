import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// Confirmations are brief; destructive outcomes and errors need longer to read.
enum FeedbackKind { confirmation, destructive, error }

/// Floating list controls yield to feedback, including its exit animation.
class _FeedbackVisibility extends ValueNotifier<bool> {
  _FeedbackVisibility() : super(false);
  int generation = 0;
}

final _feedbackVisibility = Expando<_FeedbackVisibility>();
_FeedbackVisibility _visibility(ScaffoldMessengerState messenger) =>
    _feedbackVisibility[messenger] ??= _FeedbackVisibility();

ValueListenable<bool> feedbackVisibilityOf(BuildContext context) =>
    _visibility(ScaffoldMessenger.of(context));

/// Show feedback only when the outcome needs a message beyond its visible UI.
void showFeedback(
  BuildContext context,
  String message, {
  FeedbackKind kind = FeedbackKind.confirmation,
  VoidCallback? onUndo,
}) => showFeedbackWithMessenger(
  ScaffoldMessenger.of(context),
  message,
  kind: kind,
  onUndo: onUndo,
);

/// The explicit host keeps shopping feedback above its pinned input field.
void showFeedbackWithMessenger(
  ScaffoldMessengerState messenger,
  String message, {
  FeedbackKind kind = FeedbackKind.confirmation,
  VoidCallback? onUndo,
  Duration? duration,
}) {
  // Clear queued messages before removing the visible one. Removing immediately
  // also cancels its timer, so the newest message receives its own full duration.
  messenger.clearSnackBars();
  messenger.removeCurrentSnackBar();
  final visibility = _visibility(messenger);
  final generation = ++visibility.generation;
  final shown = messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration:
          duration ??
          Duration(
            seconds: onUndo != null || kind != FeedbackKind.confirmation
                ? 4
                : 2,
          ),
      persist: false,
      action: onUndo == null
          ? null
          : SnackBarAction(label: 'Undo', onPressed: onUndo),
    ),
  );
  visibility.value = true;
  shown.closed.then((_) {
    if (generation == visibility.generation) visibility.value = false;
  });
}
