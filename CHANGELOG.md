## 0.1.0

- Initial release as `flutter_blobatar` (unofficial community port).
- Name chosen because `blobatar` on pub.dev is the official SDK.
- `blobatarSvg` / `blobatarUri` emit byte-identical SVG to the JS core (gen-2).
- `Blobatar` widget renders via `flutter_svg`.
- 28 tests, including 20 JS-exported reference vectors.
- Static idle renderer only; no animation/expressions.
