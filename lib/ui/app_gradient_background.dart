import 'package:flutter/material.dart';

class AppGradientBackground extends StatelessWidget {
  const AppGradientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF624033), Color(0xFF382C2A), Color(0xFF17191C)]
              : const [Color(0xFFFFE4B8), Color(0xFFFFCFC0), Color(0xFFF8F5F0)],
          stops: const [0, .38, 1],
        ),
      ),
    );
  }
}
