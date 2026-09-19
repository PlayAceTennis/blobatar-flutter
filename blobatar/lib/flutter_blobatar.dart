/// flutter_blobatar — deterministic geometric avatars from any string.
///
/// Unofficial Flutter port of [blobatar.dev](https://blobatar.dev/).
/// Not affiliated with or endorsed by the original author (Alain).
///
/// ```dart
/// import 'package:flutter_blobatar/flutter_blobatar.dart';
///
/// Blobatar(seed: user.email, size: 48)
/// ```
library;

export 'src/blobatar_core.dart'
    show
        BlobatarBackground,
        TraitOverrides,
        Palette,
        Oklch,
        blobatarSvg,
        blobatar,
        blobatarUri,
        normalizeSeed,
        seedState,
        stream,
        imul,
        toInt32,
        layoutForTraits,
        Layout;
export 'src/blobatar_widget.dart' show Blobatar;
