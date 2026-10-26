# Included artwork and replacement assets

This repository includes two full-body illustrations and three animation-atlas PNG files under separate non-commercial terms, not MIT. It has no sound files, original reference photographs or upstream bust image. Read [ASSET-LICENSE.md](../gpt-niang-usage/assets/ASSET-LICENSE.md) and [GENERATED-ASSETS.md](../gpt-niang-usage/assets/GENERATED-ASSETS.md) before reuse.

The build uses `gpt-niang-usage/assets/` by default. To replace the artwork, point `GPT_NIANG_ASSETS` at your own appropriately licensed assets directory. Point it at an empty directory for a no-art build: the app then uses a system symbol that does not simulate articulated character motion. Only the following file names are copied into the application bundle:

| File | Purpose | Expected size |
| --- | --- | --- |
| `gpt-dragon-niang-bust.png` | Optional fallback illustration | Any sensible RGBA size |
| `gpt-dragon-niang-fullbody.png` | Included chibi full-body illustration | 1024 × 1536 |
| `gpt-dragon-niang-winged-v2.png` | Included long-outfit illustration | 1024 × 1536 |
| `pet-rig-chibi-v1.png` | Chibi cutout atlas | Exactly 1448 × 1086 |
| `pet-rig-winged-v1.png` | Winged cutout atlas | Exactly 1448 × 1086 |
| `pet-rig-chibi-dress-v1.png` | Chibi replacement dress | Exactly 1320 × 1192 |
| `press.wav`, `release.wav` | Optional interaction sounds | Valid WAV |

The historical file names are compatibility identifiers; they do not grant rights beyond the separate asset notice.

The atlas layout is explicitly defined in `macos/Sources/GPTNiangMac/PetRigView.swift`: `PetRigAssets.rects` controls the crop rectangles, and `drawChibi` / `drawWinged` control placement, order and anchors. These coordinates match the included layouts, so a random full-body image cannot become a matching atlas merely by changing its name. Adapt the coordinates and anchors when creating a new design.

The eyes, closed-eye pair and smile are separate sprites. Both arms are independent whole-arm cutouts; there are no separate elbow or finger bones. Q-style legs are separate parts; the long-outfit layout keeps legs in the body image.

Invalid or missing atlases fall back to a complete illustration, then to the system symbol. No network asset fetch is performed. Chibi articulation requires both the chibi atlas and replacement-dress image. Winged articulation requires the winged atlas.

Before publishing an asset-enabled fork, verify the rights for every supplied image, reference, font and sound, and use a separate asset license where necessary. Do not remove these exclusions merely because an image was generated with AI.
