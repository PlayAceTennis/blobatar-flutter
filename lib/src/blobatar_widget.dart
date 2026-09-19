import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'blobatar_core.dart';

export 'blobatar_core.dart'
    show BlobatarBackground, TraitOverrides, Palette, Oklch;

/// A deterministic geometric blobatar rendered from any string.
///
/// The same [seed] always renders the same face: the seed is normalized
/// (NFC + trim + lowercase), hashed once, and every trait (silhouette, eyes,
/// hue, tone) is derived from that hash — matching `blobatar(seed)` from
/// https://blobatar.dev/ byte for byte.
///
/// ```dart
/// Blobatar(seed: user.email, size: 48)
/// ```
class Blobatar extends StatelessWidget {
  /// The value the face is generated from: a username, email, id, or any
  /// string. Never empty-normalized handling is the core's business.
  final String seed;

  /// Logical width/height. Emitted as SVG `width`/`height` and used as the
  /// widget box size.
  final double size;

  /// Plate behind the figure. Defaults to transparent ([BlobatarBackground.none]).
  final BlobatarBackground background;

  /// Locks hue in degrees; the seed then drives shape only.
  final double? hue;

  /// Locks the swatch as a 0–1 position, pale to ink.
  final double? tone;

  /// Pins individual trait keys as 0–1 positions, e.g. `{'shape': 0.95}`.
  final TraitOverrides? traits;

  /// Per-key hex overrides (`head`/`eye`/`bg`). Bypasses contrast.
  final Map<String, String>? palette;

  /// NFC + trim + lowercase before hashing. Defaults to true so
  /// `Alain@x.com` and `alain@x.com` agree.
  final bool normalize;

  /// Enforce the contrast floors. Defaults to true.
  final bool enforceContrast;

  /// Accessibility label; adds a `<title>` to the SVG.
  final String? semanticLabel;

  /// How the picture should fit inside [size].
  final BoxFit fit;

  const Blobatar({
    super.key,
    required this.seed,
    this.size = 48,
    this.background = BlobatarBackground.none,
    this.hue,
    this.tone,
    this.traits,
    this.palette,
    this.normalize = true,
    this.enforceContrast = true,
    this.semanticLabel,
    this.fit = BoxFit.contain,
  });

  /// The raw SVG string for this configuration.
  String toSvg() => blobatarSvg(
        seed,
        size: size,
        background: background,
        hue: hue,
        tone: tone,
        traits: traits,
        palette: palette,
        normalize: normalize,
        enforceContrast: enforceContrast,
        title: semanticLabel,
      );

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      toSvg(),
      width: size,
      height: size,
      fit: fit,
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}
