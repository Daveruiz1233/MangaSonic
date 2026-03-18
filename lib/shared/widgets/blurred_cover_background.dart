import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class BlurredCoverBackground extends StatelessWidget {
  final String imageUrl;
  final Color? dominantColor;
  final double blurSigma;
  final double topOpacity;
  final double bottomOpacity;

  const BlurredCoverBackground({
    super.key,
    required this.imageUrl,
    this.dominantColor,
    this.blurSigma = 12.0,
    this.topOpacity = 0.4,
    this.bottomOpacity = 0.9,
  });

  @override
  Widget build(BuildContext context) {
    final accent = dominantColor ?? Colors.black;

    return Stack(
      children: [
        Positioned.fill(
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
          ),
        ),
        // Vertical gradient overlay: black → dynamic tint → black
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  // Top: Strong black
                  Colors.black,
                  Colors.black,
                  Colors.black.withValues(alpha: 0.85),
                  // Upper: Black fading quickly
                  Colors.black.withValues(alpha: 0.8),
                  Colors.black.withValues(alpha: 0.4),
                  // Upper-middle: Dynamic tint emerging
                  accent.withValues(alpha: 0.25),
                  // Middle: Dynamic tint (reduced brightness)
                  accent.withValues(alpha: 0.7),
                  accent.withValues(alpha: 0.7),
                  // Lower-middle: Dynamic tint fading
                  accent.withValues(alpha: 0.25),
                  // Lower: Black fading quickly
                  Colors.black.withValues(alpha: 0.4),
                  Colors.black.withValues(alpha: 0.8),
                  // Bottom: Strong black
                  Colors.black.withValues(alpha: 0.85),
                  Colors.black,
                  Colors.black,
                ],
                stops: const [0.0, 0.15, 0.3, 0.45, 0.55, 0.7, 0.85, 1.0],
              ),
            ),
          ),
        ),
        // Horizontal gradient overlay: black on left side
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  // Left: Strong black
                  Colors.black.withValues(alpha: 0.85),
                  // Center-left: Fading out
                  Colors.black.withValues(alpha: 0.5),
                  // Center: Lighter
                  Colors.black.withValues(alpha: 0.2),
                  // Right: Transparent
                  Colors.transparent,
                ],
                stops: const [0.0, 0.25, 0.45, 0.7],
              ),
            ),
          ),
        ),
        // Horizontal gradient overlay: black on right side
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [
                  // Right: Strong black
                  Colors.black.withValues(alpha: 0.85),
                  // Center-right: Fading out
                  Colors.black.withValues(alpha: 0.5),
                  // Center: Lighter
                  Colors.black.withValues(alpha: 0.2),
                  // Left: Transparent
                  Colors.transparent,
                ],
                stops: const [0.0, 0.25, 0.45, 0.7],
              ),
            ),
          ),
        ),
        // Subtle blur on middle section
        Positioned(
          left: 0,
          right: 0,
          top: MediaQuery.of(context).size.height * 0.2,
          bottom: MediaQuery.of(context).size.height * 0.2,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0),
            child: Container(
              color: Colors.transparent,
            ),
          ),
        ),
      ],
    );
  }
}
