// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/rendering.dart' show RenderBox;
import 'package:flutter/widgets.dart' show BuildContext;

/// Where the share sheet is anchored when nothing better is known.
///
/// A 1x1 rectangle in the top-left corner: small, but never empty.
const Rect kFallbackShareAnchor = Rect.fromLTWH(0, 0, 1, 1);

/// The rectangle to pass as `sharePositionOrigin` for a widget whose top-left
/// corner is [topLeft] (in global coordinates) and whose size is [size].
///
/// iOS 26 and later (and every iPad) refuse to present the share sheet without a
/// rectangle that has both a width and a height. So the result is never empty:
/// a missing, zero-sized, negative or non-finite geometry yields
/// [kFallbackShareAnchor].
Rect shareAnchorFromGeometry({Offset? topLeft, Size? size}) {
  if (topLeft == null || size == null) return kFallbackShareAnchor;
  final usable = topLeft.dx.isFinite &&
      topLeft.dy.isFinite &&
      size.width.isFinite &&
      size.height.isFinite &&
      size.width > 0 &&
      size.height > 0;
  return usable ? topLeft & size : kFallbackShareAnchor;
}

/// [shareAnchorFromGeometry] for a laid-out [box] (null, not attached to the
/// render tree or not yet laid out: the fallback).
Rect shareAnchorOf(RenderBox? box) {
  if (box == null || !box.attached || !box.hasSize) return kFallbackShareAnchor;
  return shareAnchorFromGeometry(
      topLeft: box.localToGlobal(Offset.zero), size: box.size);
}

/// The anchor for the widget that owns [context] (the tapped row, for a share
/// action started from it). Call it only while [context] is mounted.
Rect shareAnchorForContext(BuildContext context) {
  final object = context.findRenderObject();
  return shareAnchorOf(object is RenderBox ? object : null);
}
