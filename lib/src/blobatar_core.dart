/// Deterministic blobatar core: Dart port of the `blobatar` JS engine.
///
/// Ports `packages/blobatar/src/{hash,traits,color,shape,render}.ts` and
/// `packages/blobatar/src/styles/{blob,compose,shapes}.ts` at blobatar 2.x
/// (gen-2 vocabulary: ten silhouettes).
///
/// The same seed always produces the same SVG string within the frozen gen-2
/// contract. Numeric ranges, shape thresholds and the tone set are part of
/// that contract.
///
/// Algorithm notes (where Dart differs from JS):
/// * 32-bit hash arithmetic uses [imul]/[toInt32] to reproduce
///   `Math.imul`, `<<`, `>>>` exactly (including when compiled to the web,
///   where Dart ints are doubles — hence the 16-bit decomposition).
/// * Number formatting uses [r2str], which reproduces JS
///   `String(Math.round(v * 100) / 100)` including the `-0` -> `"0"` rule.
/// * Seed normalization is NFC + trim + lowercase via `unorm_dart`, with the
///   JS `toLowerCase` edge cases (U+0130, final sigma) handled explicitly.
///
/// MIT-licensed original by Alain (https://github.com/Alain00/blobatar).
/// This port keeps the mapping seed -> look identical; see
/// `test/blobatar_test.dart` for reference vectors exported from the JS
/// implementation.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:unorm_dart/unorm_dart.dart';

// ---------------------------------------------------------------------------
// Hashing (port of hash.ts)
// ---------------------------------------------------------------------------

const int _sep = 0xff;

/// JavaScript `Math.imul` — 32-bit integer multiplication.
///
/// 16-bit decomposition so the result is exact both on the VM (64-bit ints)
/// and on the web (doubles).
int imul(int a, int b) {
  final int x = a & 0xFFFFFFFF;
  final int y = b & 0xFFFFFFFF;
  final int xl = x & 0xFFFF;
  final int xh = x >> 16;
  final int yl = y & 0xFFFF;
  final int yh = y >> 16;
  final int low =
      (xl * yl + (((xl * yh + xh * yl) & 0xFFFF) << 16)) & 0xFFFFFFFF;
  return low >= 0x80000000 ? low - 0x100000000 : low;
}

/// JavaScript's `| 0` view of an int: the low 32 bits, signed.
int toInt32(int v) {
  final int low = v & 0xFFFFFFFF;
  return low >= 0x80000000 ? low - 0x100000000 : low;
}

/// JS `h >>> n` — logical shift of the 32-bit pattern, zero-filling.
int _shr32(int h, int n) => (h & 0xFFFFFFFF) >>> n;

int _feed(int h, List<int> bytes) {
  for (final int byte in bytes) {
    h = imul(h ^ byte, 3432918353);
    h = toInt32((h << 13) | _shr32(h, 19));
  }
  return h;
}

/// murmur3 fmix32 — a bijection on uint32 with full avalanche.
int _finalize(int h) {
  h = imul(h ^ _shr32(h, 16), 2246822507);
  h = imul(h ^ _shr32(h, 13), 3266489909);
  return (h ^ _shr32(h, 16)) & 0xFFFFFFFF;
}

/// NFC + trim + lowercase, matching JS `seed.normalize("NFC")`.
String normalizeSeed(String seed) => _jsToLower(nfc(seed).trim());

String _jsToLower(String s) {
  var needsWork = false;
  for (final int u in s.codeUnits) {
    if (u == 0x0130 || u == 0x03A3) {
      needsWork = true;
      break;
    }
  }
  if (!needsWork) return s.toLowerCase();
  final units = s.codeUnits;
  final out = StringBuffer();
  for (var i = 0; i < units.length; i++) {
    final int u = units[i];
    if (u == 0x0130) {
      out.write('i\u0307');
    } else if (u == 0x03A3 &&
        _precededByCased(units, i) &&
        !_followedByCased(units, i)) {
      out.write('\u03C2');
    } else {
      out.writeCharCode(u);
    }
  }
  return out.toString().toLowerCase();
}

bool _precededByCased(List<int> units, int i) {
  for (var j = i - 1; j >= 0; j--) {
    final int u = units[j];
    if (_isCased(u)) return true;
    if (!_isCaseIgnorable(u)) return false;
  }
  return false;
}

bool _followedByCased(List<int> units, int i) {
  for (var j = i + 1; j < units.length; j++) {
    final int u = units[j];
    if (_isCased(u)) return true;
    if (!_isCaseIgnorable(u)) return false;
  }
  return false;
}

bool _isCaseIgnorable(int u) =>
    (u >= 0x0300 && u <= 0x036F) || u == 0x00AD || u == 0x200B;

bool _isCased(int u) =>
    (u >= 0x41 && u <= 0x5A) ||
    (u >= 0x61 && u <= 0x7A) ||
    (u >= 0xC0 && u <= 0x24F && u != 0xD7 && u != 0xF7) ||
    (u >= 0x370 && u <= 0x3FF) ||
    (u >= 0x400 && u <= 0x4FF) ||
    (u >= 0x1E00 && u <= 0x1FFF);

/// Hashes the seed once into a reusable state (UTF-8 bytes; `length` is
/// UTF-16 code units, matching JS `s.length`).
int seedState(String seed, {bool normalize = true}) {
  final String s = normalize ? normalizeSeed(seed) : seed;
  return _feed(1779033703 ^ s.length, utf8.encode(s));
}

/// One uniform float in [0, 1) for [key], independent of every other key.
double stream(int state, String key) =>
    _finalize(_feed(_feed(state, [_sep]), utf8.encode(key))) / 4294967296;

// ---------------------------------------------------------------------------
// Traits (port of traits.ts)
// ---------------------------------------------------------------------------

/// Fixed values for individual traits, keyed exactly as the layout reads
/// them — `{"eye.gap": 0.82}`. A `List<double>` means "any of these", with
/// the key's own hash choosing among them.
typedef TraitOverrides = Map<String, Object>;

/// A trait reader over one hashed seed.
class Traits {
  final int state;
  final Map<String, Object>? _overrides;

  Traits(this.state, [Map<String, Object>? overrides])
      : _overrides = overrides;

  /// Uniform float in [0, 1).
  double call(String key) {
    final Object? v = _overrides?[key];
    double? o;
    if (v is List) {
      if (v.isNotEmpty) {
        final int index = (stream(state, key) * v.length).floor();
        final Object? chosen = v[index];
        if (chosen != null) o = (chosen as num).toDouble();
      }
    } else if (v is num) {
      o = v.toDouble();
    }
    if (o == null) return stream(state, key);
    if (o.isNaN) return 0.0;
    if (o > 0) return o < 1 ? o : 0.999999;
    return 0.0;
  }

  /// Uniform float in [min, max).
  double numIn(String key, double min, double max) =>
      min + call(key) * (max - min);

  /// Uniform integer in [min, max], inclusive.
  int intIn(String key, int min, int max) =>
      min + (call(key) * (max - min + 1)).floor();

  /// Uniform choice. Contents frozen per major.
  T pick<T>(String key, List<T> options) =>
      options[(call(key) * options.length).floor()];

  /// True with probability [p].
  bool boolIn(String key, [double p = 0.5]) => call(key) < p;

  /// Symmetric jitter in [-amount, amount).
  double jitter(String key, double amount) => (call(key) * 2 - 1) * amount;
}

Traits traitsFor(String seed,
        {bool normalize = true, Map<String, Object>? overrides}) =>
    Traits(seedState(seed, normalize: normalize), overrides);

// ---------------------------------------------------------------------------
// Color (port of color.ts)
// ---------------------------------------------------------------------------

/// A color in OKLCh.
class Oklch {
  final double l;
  final double c;
  final double h;
  const Oklch(this.l, this.c, this.h);
}

/// Resolved palette, keyed by `'bg'` / `'head'` / `'eye'`.
typedef Palette = Map<String, String>;

/// JS `Math.round` — half toward +infinity, not half away from zero.
double jsRound(double v) => (v + 0.5).floorToDouble();

(double, double, double) _toLinear(Oklch color) {
  final double r = color.h * math.pi / 180;
  final double a = color.c * math.cos(r);
  final double b = color.c * math.sin(r);
  final double l_ = color.l + 0.3963377774 * a + 0.2158037573 * b;
  final double m_ = color.l - 0.1055613458 * a - 0.0638541728 * b;
  final double s_ = color.l - 0.0894841775 * a - 1.291485548 * b;
  final double l = l_ * l_ * l_;
  final double m = m_ * m_ * m_;
  final double s = s_ * s_ * s_;
  return (
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  );
}

bool _inGamut((double, double, double) rgb) =>
    rgb.$1 >= -1e-4 &&
    rgb.$1 <= 1 + 1e-4 &&
    rgb.$2 >= -1e-4 &&
    rgb.$2 <= 1 + 1e-4 &&
    rgb.$3 >= -1e-4 &&
    rgb.$3 <= 1 + 1e-4;

(double, double, double) _resolve(Oklch color) {
  var rgb = _toLinear(color);
  if (!_inGamut(rgb)) {
    double lo = 0;
    double hi = color.c;
    for (var i = 0; i < 12; i++) {
      final double mid = (lo + hi) / 2;
      if (_inGamut(_toLinear(Oklch(color.l, mid, color.h)))) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    rgb = _toLinear(Oklch(color.l, lo, color.h));
  }
  return (
    rgb.$1.clamp(0.0, 1.0),
    rgb.$2.clamp(0.0, 1.0),
    rgb.$3.clamp(0.0, 1.0),
  );
}

double _luminance(Oklch color) {
  final rgb = _resolve(color);
  return 0.2126 * rgb.$1 + 0.7152 * rgb.$2 + 0.0722 * rgb.$3;
}

double contrastOf(Oklch a, Oklch b) {
  final double x = _luminance(a);
  final double y = _luminance(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

Oklch ensureContrast(Oklch fg, Oklch bg, double min) {
  if (contrastOf(fg, bg) >= min) return fg;
  final double lean = fg.l >= bg.l ? 1 : -1;
  for (final double dir in [lean, -lean]) {
    double l = fg.l;
    for (var i = 0; i < 60; i++) {
      l = math.min(1.0, math.max(0.0, l + dir * 0.02));
      final Oklch probe = Oklch(l, fg.c, fg.h);
      if (contrastOf(probe, bg) >= min) return probe;
      if (l == 0 || l == 1) break;
    }
  }
  final Oklch black = Oklch(0, 0, fg.h);
  final Oklch white = Oklch(1, 0, fg.h);
  return contrastOf(black, bg) >= contrastOf(white, bg) ? black : white;
}

String _hex2(int v) => v < 16 ? '0${v.toRadixString(16)}' : v.toRadixString(16);

String toHex(Oklch color) {
  final rgb = _resolve(color);
  final out = StringBuffer('#');
  for (final double v in [rgb.$1, rgb.$2, rgb.$3]) {
    final double s =
        v <= 0.0031308 ? 12.92 * v : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
    out.write(_hex2(jsRound(s * 255).toInt()));
  }
  return out.toString();
}

class _Tone {
  final double edge;
  final double l;
  final double c;
  const _Tone(this.edge, this.l, this.c);
}

const List<_Tone> _tones = [
  _Tone(0.2, 0.86, 0.085), // pastel
  _Tone(0.36, 0.9, 0.028), // pale neutral
  _Tone(0.62, 0.73, 0.135), // mid
  _Tone(0.8, 0.62, 0.165), // deep
  _Tone(0.93, 0.87, 0.16), // bright
  _Tone(1.0, 0.34, 0.035), // ink
];

_Tone _toneAt(double v) =>
    _tones.firstWhere((t) => v < t.edge, orElse: () => _tones.first);

const Oklch darkSurface = Oklch(0.145, 0, 0);
const double surfaceFloor = 1.5;

Map<String, Oklch> _ramp(double hue, double tone) {
  final _Tone t = _toneAt(tone);
  final Oklch head =
      ensureContrast(Oklch(t.l, t.c, hue), darkSurface, surfaceFloor);
  return {
    'bg': Oklch(0.965, 0.01, hue),
    'head': head,
    'eye': head.l >= 0.5 ? Oklch(0.17, 0.02, hue) : Oklch(0.97, 0.012, hue),
  };
}

const List<(String, String, double)> floors = [
  ('head', 'bg', 1.25),
  ('eye', 'head', 4.5),
];

Map<String, Oklch> ramp(double hue, [bool enforce = true, double tone = 0]) {
  final Map<String, Oklch> r = _ramp(hue, tone);
  if (enforce) {
    for (final (String fg, String bg, double min) in floors) {
      r[fg] = ensureContrast(r[fg]!, r[bg]!, min);
    }
  }
  return r;
}

Palette palette(double hue, [bool enforce = true, double tone = 0]) {
  final Map<String, Oklch> r = ramp(hue, enforce, tone);
  return {for (final e in r.entries) e.key: toHex(e.value)};
}

// ---------------------------------------------------------------------------
// Path primitives (port of shape.ts) — emitted as strings, byte-identical
// ---------------------------------------------------------------------------

/// `r2`: two decimals, `-0` -> `"0"`, no trailing `.0` — matches
/// JS `String(Math.round(v * 100) / 100)`.
String r2str(double v) {
  final double s = jsRound(v * 100) / 100;
  if (s == 0) return '0';
  if (s.truncateToDouble() == s) return s.truncate().toString();
  return s.toString();
}

String superellipseStr({
  required double cx,
  required double cy,
  required double rx,
  required double ry,
  double n = 4,
  double rot = 0,
}) {
  final double k = math.min(1.0, (8 * math.pow(2, -1 / n) - 4) / 3);
  final double a = rx;
  final double b = ry;
  final double ak = a * k;
  final double bk = b * k;
  final pts = <List<double>>[
    [a, 0],
    [a, bk],
    [ak, b],
    [0, b],
    [-ak, b],
    [-a, bk],
    [-a, 0],
    [-a, -bk],
    [-ak, -b],
    [0, -b],
    [ak, -b],
    [a, -bk],
    [a, 0],
  ];
  final double t = rot * math.pi / 180;
  final double cos = math.cos(t);
  final double sin = math.sin(t);
  String at(int i) {
    final double x = pts[i][0];
    final double y = pts[i][1];
    return '${r2str(cx + x * cos - y * sin)} ${r2str(cy + x * sin + y * cos)}';
  }

  var d = 'M${at(0)}';
  for (var i = 1; i < 13; i += 3) {
    d += 'C${at(i)} ${at(i + 1)} ${at(i + 2)}';
  }
  return '${d}Z';
}

String blobPathStr(double cx, double cy, double rx, double ry,
    List<double> radii, [double rot = 0]) {
  final int n = radii.length;
  final double t0 = rot * math.pi / 180;
  final p = <List<double>>[
    for (var i = 0; i < n; i++)
      [
        cx + rx * radii[i] * math.cos(t0 + 2 * math.pi * i / n),
        cy + ry * radii[i] * math.sin(t0 + 2 * math.pi * i / n),
      ],
  ];
  List<double> at(int i) => p[((i % n) + n) % n];
  var d = 'M${r2str(at(0)[0])} ${r2str(at(0)[1])}';
  for (var i = 0; i < n; i++) {
    final x0 = at(i - 1)[0], y0 = at(i - 1)[1];
    final x1 = at(i)[0], y1 = at(i)[1];
    final x2 = at(i + 1)[0], y2 = at(i + 1)[1];
    final x3 = at(i + 2)[0], y3 = at(i + 2)[1];
    d += 'C${r2str(x1 + (x2 - x0) / 6)} ${r2str(y1 + (y2 - y0) / 6)}'
        ' ${r2str(x2 - (x3 - x1) / 6)} ${r2str(y2 - (y3 - y1) / 6)}'
        ' ${r2str(x2)} ${r2str(y2)}';
  }
  return '${d}Z';
}

String polygonStr({
  required double cx,
  required double cy,
  required double rx,
  required double ry,
  required int sides,
  double round = 0.3,
  double rot = 0,
}) {
  final double k = round > 0 ? (round < 1 ? round / 2 : 0.5) : 0;
  final double t0 = rot * math.pi / 180 - math.pi / 2;
  final v = <List<double>>[
    for (var i = 0; i < sides; i++)
      [
        cx + rx * math.cos(t0 + 2 * math.pi * i / sides),
        cy + ry * math.sin(t0 + 2 * math.pi * i / sides),
      ],
  ];
  List<double> at(int i) => v[((i % sides) + sides) % sides];
  String cut(int i, int j) {
    final a = at(i), b = at(j);
    return '${r2str(a[0] + (b[0] - a[0]) * k)} '
        '${r2str(a[1] + (b[1] - a[1]) * k)}';
  }

  var d = 'M${cut(0, -1)}';
  for (var i = 0; i < sides; i++) {
    final vv = at(i);
    d += 'Q${r2str(vv[0])} ${r2str(vv[1])} ${cut(i, i + 1)}';
    if (k < 0.5) d += 'L${cut(i + 1, i)}';
  }
  return '${d}Z';
}

String boxStr(double cx, double cy, double rx, double ry) {
  final String l = r2str(cx - rx);
  final String r = r2str(cx + rx);
  return 'M$l ${r2str(cy - ry)}H$r'
      'V${r2str(cy + ry)}H$l'
      'Z';
}

String taperStr(double cx, double cy, double rx, double ry, double tip) {
  final double t = math.max(1.05, tip);
  final double tx = rx * math.sqrt(1 - 1 / (t * t));
  final double ty = cy - ry / t;
  final double apex = cy - t * ry;
  final double px = tx * 0.14;
  final double py = ty + 0.86 * (apex - ty);
  return 'M${r2str(cx - tx)} ${r2str(ty)}'
      'L${r2str(cx - px)} ${r2str(py)}'
      'Q${r2str(cx)} ${r2str(apex)} ${r2str(cx + px)} ${r2str(py)}'
      'L${r2str(cx + tx)} ${r2str(ty)}Z';
}

// ---------------------------------------------------------------------------
// Silhouettes (port of styles/shapes.ts)
// ---------------------------------------------------------------------------

class Body {
  double cx, cy, rx, ry, n, rot;
  List<double> radii;
  int? sides;
  double? round;
  Body({
    required this.cx,
    required this.cy,
    required this.rx,
    required this.ry,
    required this.n,
    required this.rot,
    required this.radii,
    this.sides,
    this.round,
  });
}

class Ellipse {
  double cx, cy, rx, ry;
  Ellipse(this.cx, this.cy, this.rx, this.ry);
}

class Petal {
  final double cx, cy, r;
  const Petal(this.cx, this.cy, this.r);
}

class Deco {
  final List<Petal> petals = [];
  final List<String> extra = [];
}

abstract class ShapeDef {
  final String name;
  final double core;
  const ShapeDef(this.name, this.core);
  void patchBody(Traits t, Body b) {}
  Ellipse? face(Body b) => null;
  void decorate(Traits t, Body b, Deco out) {}

  /// Whether this shape traces its core with a custom primitive instead of
  /// the default superellipse. Stored separately from [path] because a
  /// method tear-off is never null, while JS `shape.path` is undefined for
  /// shapes without one.
  bool get hasCustomPath => false;
  String? path(Body b) => null;
}

String _polyOf(Body b) => polygonStr(
      cx: b.cx,
      cy: b.cy,
      rx: b.rx,
      ry: b.ry,
      sides: b.sides!,
      round: b.round!,
      rot: b.rot,
    );

String _splineOf(Body b) => blobPathStr(b.cx, b.cy, b.rx, b.ry, b.radii, b.rot);

Ellipse _shrunk(Body b, double k) => Ellipse(b.cx, b.cy, b.rx * k, b.ry * k);

Ellipse _splineFace(Body b) {
  var min = b.radii[0];
  for (final r in b.radii) {
    if (r < min) min = r;
  }
  return _shrunk(b, min * 0.95);
}

class _Round extends ShapeDef {
  const _Round() : super('round', 1);
}

class _Organic extends ShapeDef {
  @override
  bool get hasCustomPath => true;
  const _Organic() : super('organic', 0.98);
  @override
  String? path(Body b) => _splineOf(b);
  @override
  Ellipse? face(Body b) => _splineFace(b);
}

class _Boxy extends ShapeDef {
  const _Boxy() : super('boxy', 0.86);
  @override
  void patchBody(Traits t, Body b) {
    b.n = t.numIn('body.n', 3.4, 6);
    b.rot = t.numIn('body.rot', -20, 20);
  }
}

class _Capsule extends ShapeDef {
  @override
  bool get hasCustomPath => true;
  const _Capsule() : super('capsule', 1.02);
  @override
  void patchBody(Traits t, Body b) {
    b.ry *= t.numIn('capsule.squat', 0.55, 0.68);
  }

  @override
  Ellipse? face(Body b) => _shrunk(b, 0.94);
  @override
  void decorate(Traits t, Body b, Deco out) {
    for (final s in [-1, 1]) {
      out.petals.add(Petal(b.cx + s * (b.rx - b.ry), b.cy, b.ry));
    }
  }

  @override
  String? path(Body b) => boxStr(b.cx, b.cy, b.rx - b.ry, b.ry);
}

class _Nub extends ShapeDef {
  const _Nub() : super('nub', 0.88);
  @override
  void decorate(Traits t, Body b, Deco out) {
    final int count = t.intIn('nub.n', 1, 2);
    for (var i = 0; i < count; i++) {
      final double a = t.numIn('nub.a$i', 0, 2 * math.pi);
      out.petals.add(Petal(
        b.cx + math.cos(a) * b.rx * 0.88,
        b.cy + math.sin(a) * b.rx * 0.88,
        b.rx * t.numIn('nub.r$i', 0.24, 0.4),
      ));
    }
  }
}

class _Cloud extends ShapeDef {
  @override
  bool get hasCustomPath => true;
  const _Cloud() : super('cloud', 0.78);
  @override
  String? path(Body b) => _splineOf(b);
  @override
  Ellipse? face(Body b) => _splineFace(b);
  @override
  void decorate(Traits t, Body b, Deco out) {
    final int count = t.intIn('cloud.n', 4, 6);
    for (var i = 0; i < count; i++) {
      final double a = math.pi + (math.pi * (i + 0.5)) / count;
      out.petals.add(Petal(
        b.cx + math.cos(a) * b.rx * 0.8,
        b.cy + math.sin(a) * b.rx * 0.5,
        b.rx * t.numIn('cloud.r$i', 0.44, 0.62),
      ));
    }
  }
}

class _Droplet extends ShapeDef {
  const _Droplet() : super('droplet', 0.78);
  @override
  void patchBody(Traits t, Body b) {
    b.cy += 0.22 * b.ry;
    b.n = 2;
  }

  @override
  Ellipse? face(Body b) =>
      Ellipse(b.cx, b.cy + b.ry * 0.05, b.rx * 0.88, b.ry * 0.88);
  @override
  void decorate(Traits t, Body b, Deco out) {
    out.extra.add(
        taperStr(b.cx, b.cy, b.rx, b.ry, t.numIn('droplet.tip', 1.4, 1.65)));
  }
}

class _Hexagon extends ShapeDef {
  @override
  bool get hasCustomPath => true;
  const _Hexagon() : super('hexagon', 1.05);
  @override
  String? path(Body b) => _polyOf(b);
  @override
  Ellipse? face(Body b) => _shrunk(b, 0.84);
  @override
  void patchBody(Traits t, Body b) {
    b.sides = 6;
    b.rot = t.numIn('body.rot', -12, 12);
    b.round = t.numIn('poly.round', 0.24, 0.5);
  }
}

class _Sun extends ShapeDef {
  const _Sun() : super('sun', 0.7);
  @override
  void decorate(Traits t, Body b, Deco out) {
    final int count = t.intIn('sun.n', 6, 9);
    final double dist = b.rx * t.numIn('sun.dist', 1.0, 1.08);
    final double pr = b.rx * t.numIn('sun.r', 0.2, 0.26);
    final double off = t.numIn('sun.rot', 0, 2 * math.pi);
    for (var i = 0; i < count; i++) {
      final double a = off + (2 * math.pi * i) / count;
      out.petals.add(
          Petal(b.cx + math.cos(a) * dist, b.cy + math.sin(a) * dist, pr));
    }
  }
}

class _Triangle extends ShapeDef {
  @override
  bool get hasCustomPath => true;
  const _Triangle() : super('triangle', 1.15);
  @override
  String? path(Body b) => _polyOf(b);
  @override
  void patchBody(Traits t, Body b) {
    b.sides = 3;
    b.rot = t.numIn('body.rot', -5, 5);
    b.round = t.numIn('poly.round', 0.24, 0.5);
  }

  @override
  Ellipse? face(Body b) =>
      Ellipse(b.cx, b.cy + b.ry * 0.1, b.rx * 0.54, b.ry * 0.36);
}

const _Round _round = _Round();
const _Organic _organic = _Organic();
const _Boxy _boxy = _Boxy();
const _Capsule _capsule = _Capsule();
const _Nub _nub = _Nub();
const _Cloud _cloud = _Cloud();
const _Droplet _droplet = _Droplet();
const _Hexagon _hexagon = _Hexagon();
const _Sun _sun = _Sun();
const _Triangle _triangle = _Triangle();

/// Band table: `[shape, upper edge)` in order. Frozen per major.
const List<(ShapeDef, double)> bands = [
  (_round, 0.22),
  (_organic, 0.48),
  (_boxy, 0.6),
  (_capsule, 0.7),
  (_nub, 0.79),
  (_cloud, 0.86),
  (_droplet, 0.915),
  (_hexagon, 0.95),
  (_sun, 0.98),
  (_triangle, 1.0),
];

// ---------------------------------------------------------------------------
// Layout (port of styles/compose.ts)
// ---------------------------------------------------------------------------

class Eye {
  double cx, cy, rx, ry, n, rot;
  Eye(this.cx, this.cy, this.rx, this.ry, this.n, this.rot);
}

class Layout {
  final String shape;
  final Body body;
  final Ellipse face;
  final List<Eye> eyes;
  final List<Petal> petals;
  final List<String> extra;
  final String? Function(Body)? draw;
  Layout({
    required this.shape,
    required this.body,
    required this.face,
    required this.eyes,
    required this.petals,
    required this.extra,
    required this.draw,
  });
}

double _hypot2(double x, double y) => math.sqrt(x * x + y * y);

List<Eye> faceFit(Traits t, Body b, Ellipse face) {
  final double rx = b.rx;
  final double er0 = t.numIn('eye.rx', 0.075, 0.105) * rx;
  final double ratio = t.numIn('eye.ratio', 1.9, 3.2);
  final double scale = t.numIn('eye.scale', 0.78, 1.24);
  final double stretch = t.numIn('eye.stretch', 0.85, 1.18);
  final double clearance = t.numIn('eye.gap', 0.1, 0.24) * rx;
  final double wide = er0 * math.max(1, scale);
  final double tall = er0 * ratio * math.max(1, scale * stretch);
  final double gap0 = wide + rx * 0.03 + clearance;

  final double gx = t.jitter('gaze.x', 0.09) * face.rx;
  final double gy = t.numIn('gaze.y', -0.2, 0.08) * face.ry;
  final double dy = t.jitter('eye.dy', 0.04) * face.ry;
  final double reach = _hypot2(wide, tall);
  final double need = _hypot2(
    (gx.abs() + gap0 + reach) / face.rx,
    (gy.abs() + dy.abs() + reach) / face.ry,
  );
  final double fit = need > 0.9 ? 0.9 / need : 1;

  final double er = er0 * fit;
  final double eyeRy = er * ratio;
  final double gap = gap0 * fit;
  final double room = math.max(0, math.min(1, clearance / tall));
  final double bound = math.min(12, math.asin(room) * 180 / math.pi);
  final double lean = t.numIn('eye.lean', -1, 1) * bound;
  final double lean2 =
      math.max(-12.0, math.min(12.0, lean + t.jitter('eye.lean2', 3.5)));

  final double cx = face.cx + gx * fit;
  final double cy = face.cy + gy * fit;
  return [
    Eye(cx - gap, cy, er, eyeRy, t.numIn('eye.n', 3.5, 6), lean),
    Eye(cx + gap, cy + dy * fit, er * scale, eyeRy * scale * stretch,
        t.numIn('eye.n', 3.5, 6), lean2),
  ];
}

ShapeDef _pickShape(double v) {
  for (final (ShapeDef shape, double upTo) in bands) {
    if (v < upTo) return shape;
  }
  return bands.last.$1;
}

Layout layoutForTraits(Traits t) {
  final ShapeDef shape = _pickShape(t('shape'));
  final double r = t.numIn('body.r', 31, 38) * shape.core;
  final Body body = Body(
    cx: 50 + t.jitter('body.x', 1.5),
    cy: 50 + t.jitter('body.y', 1.5),
    rx: r,
    ry: r * t.numIn('body.ratio', 0.92, 1.08),
    n: t.numIn('body.n', 1.9, 2.5),
    rot: 0,
    radii: [
      for (var i = 0, len = t.intIn('body.pts', 6, 8); i < len; i++)
        1 + t.jitter('body.r$i', 0.16),
    ],
  );
  shape.patchBody(t, body);
  final Ellipse face =
      shape.face(body) ?? Ellipse(body.cx, body.cy, body.rx, body.ry);
  final Deco deco = Deco();
  shape.decorate(t, body, deco);
  return Layout(
    shape: shape.name,
    body: body,
    face: face,
    eyes: faceFit(t, body, face),
    petals: deco.petals,
    extra: deco.extra,
    draw: shape.hasCustomPath ? shape.path : null,
  );
}

// ---------------------------------------------------------------------------
// Rendering (port of render.ts + styles/compose.ts render + blobatar.ts)
// ---------------------------------------------------------------------------

/// Backdrop plate behind the figure.
enum BlobatarBackground { none, square, circle, squircle }

String _escapeXml(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _renderLayout(Layout l, Palette p) {
  final StringBuffer body = StringBuffer('<g fill="${p['head']}">');
  for (final Petal d in l.petals) {
    body.write(
        '<circle cx="${r2str(d.cx)}" cy="${r2str(d.cy)}" r="${r2str(d.r)}"/>');
  }
  for (final String d in l.extra) {
    body.write('<path d="$d"/>');
  }
  final String core = l.draw != null
      ? l.draw!(l.body)!
      : superellipseStr(
          cx: l.body.cx,
          cy: l.body.cy,
          rx: l.body.rx,
          ry: l.body.ry,
          n: l.body.n,
          rot: l.body.rot,
        );
  body.write('<path d="$core"/>');
  body.write('</g>');
  body.write('<g fill="${p['eye']}">');
  for (final Eye e in l.eyes) {
    body.write(
        '<path d="${superellipseStr(cx: e.cx, cy: e.cy, rx: e.rx, ry: e.ry, n: e.n, rot: e.rot)}"/>');
  }
  body.write('</g>');
  return body.toString();
}

String? _backdropD(BlobatarBackground bg) {
  switch (bg) {
    case BlobatarBackground.none:
      return null;
    case BlobatarBackground.square:
      return 'M0 0H100V100H0Z';
    case BlobatarBackground.circle:
      return superellipseStr(cx: 50, cy: 50, rx: 50, ry: 50, n: 2);
    case BlobatarBackground.squircle:
      return superellipseStr(cx: 50, cy: 50, rx: 50, ry: 50, n: 6);
  }
}

/// Renders a deterministic blobatar as an SVG string.
///
/// Mirrors `blobatar(name, opts)` from the JS library (static idle pose):
/// the same [seed] always yields the same string.
///
/// - [size]: emits `width`/`height` attributes. Omit to let the parent size it
///   (the `viewBox` always scales).
/// - [background]: plate behind the figure (default none).
/// - [hue]: locks hue in degrees; the seed then drives shape only.
/// - [tone]: locks the swatch as a 0–1 position, pale to ink.
/// - [traits]: pins individual trait keys as 0–1 positions (or lists to
///   choose among). Clamped to [0, 1).
/// - [palette]: per-key hex overrides (`head`/`eye`/`bg`); bypasses contrast.
/// - [normalize]: NFC + trim + lowercase (default true).
/// - [enforceContrast]: enforce the contrast floors (default true).
/// - [title]: adds a `<title>` for screen readers (XML-escaped).
String blobatarSvg(
  String seed, {
  double? size,
  BlobatarBackground background = BlobatarBackground.none,
  double? hue,
  double? tone,
  TraitOverrides? traits,
  Map<String, String>? palette,
  bool normalize = true,
  bool enforceContrast = true,
  String? title,
}) {
  final Traits t =
      traitsFor(seed, normalize: normalize, overrides: traits);
  final Palette p = paletteFn(
    hue ?? t.numIn('hue', 0, 360),
    enforceContrast,
    tone ?? t('tone'),
  );
  if (palette != null) p.addAll(palette);
  final Layout l = layoutForTraits(t);

  final String dim = size != null
      ? ' width="${r2str(size)}" height="${r2str(size)}"'
      : '';
  final String label =
      title != null ? '<title>${_escapeXml(title)}</title>' : '';
  final String? bd = _backdropD(background);
  final String plate =
      bd != null ? '<path d="$bd" fill="${p['bg']}"/>' : '';
  return '<svg xmlns="http://www.w3.org/2000/svg" '
      'viewBox="0 0 100 100"$dim>$label$plate${_renderLayout(l, p)}</svg>';
}

/// Alias kept close to the JS export name.
String blobatar(String seed,
        {double? size,
        BlobatarBackground background = BlobatarBackground.none,
        double? hue,
        double? tone,
        TraitOverrides? traits,
        Map<String, String>? palette,
        bool normalize = true,
        bool enforceContrast = true,
        String? title}) =>
    blobatarSvg(seed,
        size: size,
        background: background,
        hue: hue,
        tone: tone,
        traits: traits,
        palette: palette,
        normalize: normalize,
        enforceContrast: enforceContrast,
        title: title);

Palette paletteFn(double hue, [bool enforce = true, double tone = 0]) =>
    palette(hue, enforce, tone);

/// `data:image/svg+xml` URI for `<img src>` / CSS backgrounds.
String blobatarUri(String seed,
    {double? size,
    BlobatarBackground background = BlobatarBackground.none,
    double? hue,
    double? tone,
    TraitOverrides? traits,
    Map<String, String>? palette,
    bool normalize = true,
    bool enforceContrast = true,
    String? title}) {
  final String svg = blobatarSvg(seed,
      size: size,
      background: background,
      hue: hue,
      tone: tone,
      traits: traits,
      palette: palette,
      normalize: normalize,
      enforceContrast: enforceContrast,
      title: title);
  return 'data:image/svg+xml,${Uri.encodeComponent(svg)}';
}
