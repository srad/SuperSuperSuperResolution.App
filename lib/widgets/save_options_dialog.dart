import 'package:flutter/material.dart';
import 'package:magicresolution/theme/app_theme.dart';

enum ImageFormat { png, jpg }

class SaveOptions {
  final ImageFormat format;
  final int quality; // 1-100, only used for JPG

  SaveOptions({required this.format, this.quality = 90});
}

class SaveOptionsDialog extends StatefulWidget {
  const SaveOptionsDialog({super.key});

  @override
  State<SaveOptionsDialog> createState() => _SaveOptionsDialogState();
}

class _SaveOptionsDialogState extends State<SaveOptionsDialog> {
  ImageFormat _selectedFormat = ImageFormat.jpg;
  double _jpgQuality = 90;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Save Image'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Format',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentedButton<ImageFormat>(
            segments: const [
              ButtonSegment<ImageFormat>(
                value: ImageFormat.png,
                label: Text('PNG'),
                icon: Icon(Icons.image_outlined),
              ),
              ButtonSegment<ImageFormat>(
                value: ImageFormat.jpg,
                label: Text('JPG'),
                icon: Icon(Icons.photo_outlined),
              ),
            ],
            selected: {_selectedFormat},
            onSelectionChanged: (selection) {
              setState(() {
                _selectedFormat = selection.first;
              });
            },
          ),
          const SizedBox(height: 16),
          // Format description
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedFormat == ImageFormat.png
                        ? 'Lossless quality, larger file size'
                        : 'Smaller file size, adjustable quality',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          // Quality slider for JPG
          if (_selectedFormat == ImageFormat.jpg) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Quality',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryPink.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_jpgQuality.round()}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryPink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: _jpgQuality,
              min: 10,
              max: 100,
              divisions: 18,
              label: '${_jpgQuality.round()}%',
              onChanged: (value) {
                setState(() {
                  _jpgQuality = value;
                });
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Smaller',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                Text(
                  'Better',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop(
              SaveOptions(
                format: _selectedFormat,
                quality: _jpgQuality.round(),
              ),
            );
          },
          icon: const Icon(Icons.save_alt_rounded),
          label: const Text('Save'),
        ),
      ],
    );
  }
}
