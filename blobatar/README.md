# flutter_blobatar

> Unofficial community port for Flutter — not affiliated with or endorsed by
> [blobatar.dev](https://blobatar.dev/) / [Alain00/blobatar](https://github.com/Alain00/blobatar).
> The `blobatar` name on pub.dev belongs to the official SDK; this package is
> published as `flutter_blobatar` to avoid confusion. Static SVG rendering only.

Deterministic geometric avatars from any string — a native Dart/Flutter port
of [blobatar.dev](https://blobatar.dev/) ([source](https://github.com/Alain00/blobatar)).

Give it a username, email, id, or any string; get back the same friendly face
every time. No network, no assets, no storage — the avatar is a pure function
of the seed.

```dart
import 'package:flutter_blobatar/flutter_blobatar.dart';

Blobatar(seed: user.email, size: 48)
```

The Dart core emits **byte-identical SVG** to the original JS implementation
(`blobatar(name)`, gen-2 vocabulary: ten silhouettes). Parity is enforced by
`test/blobatar_test.dart`, which compares against reference vectors exported
from `blobatar@2` on npm.

## Install

```yaml
dependencies:
  flutter_blobatar: ^0.1.0
```

```sh
flutter pub add flutter_blobatar
```

## Use

### Widget

```dart
import 'package:flutter_blobatar/flutter_blobatar.dart';

// Same seed, same face — everywhere, forever (within gen-2).
Blobatar(seed: 'alain@example.com', size: 48)

// With a backdrop plate behind the figure.
Blobatar(
  seed: 'team-rocket',
  size: 64,
  background: BlobatarBackground.squircle, // none (default) | circle | square | squircle
)
```

All widget parameters:

| Parameter | Default | Notes |
| --- | --- | --- |
| `seed` | required | Any string: username, email, id, … |
| `size` | `48` | Logical width/height; also emitted as SVG `width`/`height` |
| `background` | `none` | `BlobatarBackground.square` / `.circle` / `.squircle` |
| `hue` | — | Locks hue in degrees; the seed then drives shape only |
| `tone` | — | Locks the swatch as a 0–1 position, pale to ink (`0.999` ≈ ink) |
| `traits` | — | Pins trait keys as 0–1 positions, e.g. `{'shape': 0.95}` |
| `palette` | — | Per-key hex overrides (`head`/`eye`/`bg`); bypasses contrast |
| `normalize` | `true` | NFC + trim + lowercase before hashing |
| `enforceContrast` | `true` | Enforce the contrast floors |
| `semanticLabel` | — | Accessibility label (adds SVG `<title>`) |
| `fit` | `contain` | `BoxFit` inside the box |

Locking a couple of traits is the useful middle ground: your brand stays
consistent while every user still gets their own creature.

```dart
// Always a sun with wide eyes — colour and everything else still per seed.
Blobatar(seed: user.email, traits: {'shape': 0.95, 'eye.ratio': 0})
```

### Pure-Dart core (no Flutter needed for the SVG string)

```dart
import 'package:flutter_blobatar/flutter_blobatar.dart';

final String svg = blobatarSvg('alain@example.com');
final String uri = blobatarUri(user.id); // data: URI for <img src> / CSS
```

`blobatarSvg` mirrors the JS `blobatar(name, opts)`: `size`, `background`,
`hue`, `tone`, `traits`, `palette`, `normalize`, `enforceContrast`, `title`.

## How it works

1. **Normalize** — NFC, trim, lowercase, so `Alain@x.com` and `alain@x.com`
   agree (astral-plane seeds hash over UTF-8 bytes, like the JS core).
2. **Hash** — the seed is hashed once (FNV-style feed + murmur3 finalizer);
   each trait key then streams one uniform float in `[0, 1)` from that state,
   so traits are independent and append-only.
3. **Layout** — the `shape` trait picks one of ten weighted silhouettes
   (`round`, `organic`, `boxy`, `capsule`, `nub`, `cloud`, `sun`, `triangle`,
   `hexagon`, `droplet`); body, eyes and decorations derive from the rest.
4. **Palette** — the seed picks hue + tone from an authored OKLCh ramp
   (eyes hold ≥ 4.5:1 against the body at every hue and tone).
5. **Serialize** — the layout is emitted as compact SVG path data with the
   same rounding as the JS core, so the strings match byte for byte.

The widget renders that string with `flutter_svg` (`SvgPicture.string`).

## Example

```sh
cd example
flutter run
```

Type any seed, switch backdrops, drag the size slider, or tap a preset face.

## Guarantees

- **Determinism** — same seed, same SVG, byte for byte.
- **Parity** — 20 reference vectors from the JS build assert the mapping
  seed → look, covering all ten silhouettes, backdrops, `title`, `size`,
  trait overrides, accented (`café`) and astral-plane (`🦊`) seeds, and
  normalization.
- **Contrast** — inherited from the ported ramp: dark eyes on light bodies,
  light eyes on dark ones.

Scope note: this package ports the **static idle** renderer. Animated idle
motion (`motion.css`) and expressions are web-CSS features of the original
and are out of scope for this port. For animated Canvas rendering see the
official `blobatar` package and the community `blobatar_flutter` package.

## License

MIT. The algorithm is a port of [blobatar](https://github.com/Alain00/blobatar)
by Alain (MIT); see `lib/src/blobatar_core.dart` for provenance notes and
`LICENSE` for the full text. Unofficial port, no endorsement implied.
