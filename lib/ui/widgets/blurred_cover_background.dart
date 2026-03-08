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
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    accent.withValues(alpha: topOpacity),
                    Colors.black.withValues(alpha: bottomOpacity),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
