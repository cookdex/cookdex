import 'package:flutter/material.dart';

/// Confirmations are brief; destructive outcomes and errors need longer to read.
enum FeedbackKind { confirmation, destructive, error }

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
}) {
  // Clear queued messages before removing the visible one. Removing immediately
  // also cancels its timer, so the newest message receives its own full duration.
  messenger.clearSnackBars();
  messenger.removeCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: Duration(
        seconds: onUndo != null || kind != FeedbackKind.confirmation ? 4 : 2,
      ),
      persist: false,
      action: onUndo == null
          ? null
          : SnackBarAction(label: 'Undo', onPressed: onUndo),
    ),
  );
}
