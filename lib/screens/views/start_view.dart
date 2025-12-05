import 'package:flutter/material.dart';
import 'package:magicresolution/theme/app_theme.dart';

class StartView extends StatelessWidget {
  final VoidCallback onPickImage;

  const StartView({
    super.key,
    required this.onPickImage,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // App Icon
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryPink.withValues(alpha: 0.2),
                  blurRadius: 30,
                  spreadRadius: 5,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: ClipOval(
              child: Image.asset(
                'assets/icon.png',
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => Icon(
                  Icons.image_rounded,
                  size: 80,
                  color: AppTheme.primaryPink.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
          const Text(
            "Let's Enhance!",
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Pick a photo to up-size it with magic 🪄",
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              textStyle: const TextStyle(fontSize: 18),
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.primaryPink,
              elevation: 2,
              side: const BorderSide(color: AppTheme.primaryPink, width: 2),
            ),
            onPressed: onPickImage,
            icon: const Icon(Icons.add_photo_alternate_rounded),
            label: const Text("Choose Photo"),
          ),
        ],
      ),
    );
  }
}
