import 'package:flutter_blobatar/flutter_blobatar.dart';
import 'package:flutter/material.dart';

void main() => runApp(const BlobatarDemoApp());

/// Minimal demo for the `flutter_blobatar` package (unofficial port).
///
/// Type any string and watch the deterministic face it maps to — the same
/// seed always renders the same blobatar.
class BlobatarDemoApp extends StatelessWidget {
  const BlobatarDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blobatar demo',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const BlobatarDemoPage(),
    );
  }
}

class BlobatarDemoPage extends StatefulWidget {
  const BlobatarDemoPage({super.key});

  @override
  State<BlobatarDemoPage> createState() => _BlobatarDemoPageState();
}

class _BlobatarDemoPageState extends State<BlobatarDemoPage> {
  final _controller = TextEditingController(text: 'alain@example.com');
  BlobatarBackground _background = BlobatarBackground.none;
  double _size = 160;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seeds = [
      'alain@example.com',
      'tove@example.com',
      'kasper@example.com',
      'Team Rocket',
      'café',
      '🦊',
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Blobatar demo')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Blobatar(
                seed: _controller.text.isEmpty ? '?' : _controller.text,
                size: _size,
                background: _background,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Seed (name, email, id — any string)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          SegmentedButton<BlobatarBackground>(
            segments: const [
              ButtonSegment(
                  value: BlobatarBackground.none, label: Text('None')),
              ButtonSegment(
                  value: BlobatarBackground.squircle, label: Text('Squircle')),
              ButtonSegment(
                  value: BlobatarBackground.circle, label: Text('Circle')),
              ButtonSegment(
                  value: BlobatarBackground.square, label: Text('Square')),
            ],
            selected: {_background},
            onSelectionChanged: (s) => setState(() => _background = s.first),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Size'),
              Expanded(
                child: Slider(
                  value: _size,
                  min: 48,
                  max: 240,
                  divisions: 12,
                  label: _size.round().toString(),
                  onChanged: (v) => setState(() => _size = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Try a seed', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final seed in seeds)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _controller.text = seed),
                      child: Blobatar(seed: seed, size: 64),
                    ),
                    const SizedBox(height: 4),
                    Text(seed,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
