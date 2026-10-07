import 'package:flutter/material.dart';

class LabDialog extends StatefulWidget {
  const LabDialog({
    super.key,
    required this.kind,
    required this.onNested,
    required this.onChange,
    required this.onHover,
    required this.onScroll,
  });
  final String kind;
  final VoidCallback onNested;
  final void Function(String, double) onChange;
  final VoidCallback onHover;
  final ValueChanged<double> onScroll;
  @override
  State<LabDialog> createState() => _LabDialogState();
}

class _LabDialogState extends State<LabDialog> {
  final controller = TextEditingController(text: 'https://modal.example');
  double slider = .4;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onHover: (_) => widget.onHover(),
    child: AlertDialog(
      title: Text('${widget.kind} popup'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        height: 340,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            widget.onScroll(notification.metrics.pixels);
            return false;
          },
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('modal-field'),
                  controller: controller,
                  autofocus: true,
                  onChanged: (text) => widget.onChange(text, slider),
                  decoration: const InputDecoration(
                    labelText: 'URL / editable Flutter field',
                  ),
                ),
                const SizedBox(height: 20),
                Text('Flutter slider: ${slider.toStringAsFixed(2)}'),
                Slider(
                  key: const ValueKey('modal-slider'),
                  value: slider,
                  onChanged: (value) {
                    setState(() => slider = value);
                    widget.onChange(controller.text, slider);
                  },
                ),
                for (var i = 0; i < 24; i++)
                  Text('Popup scrolling stays inside Flutter. Line ${i + 1}'),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onNested,
          child: const Text('Nested dialog'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop('closed'),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
