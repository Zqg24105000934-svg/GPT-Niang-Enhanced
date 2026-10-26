# Bring your own artwork

This source release intentionally has no artwork or sound files. The app builds without them and uses a system symbol as a placeholder. The placeholder does not simulate articulated character motion.

Place appropriately licensed assets in `local-assets/`, or point `GPT_NIANG_ASSETS` at a private directory before building. Only the following file names are copied into the application bundle:

| File | Purpose | Expected size |
| --- | --- | --- |
| `gpt-dragon-niang-bust.png` | Optional fallback illustration | Any sensible RGBA size |
| `gpt-dragon-niang-fullbody.png` | Optional chibi full-body illustration | Any sensible RGBA size |
| `gpt-dragon-niang-winged-v2.png` | Optional long-outfit illustration | Any sensible RGBA size |
| `pet-rig-chibi-v1.png` | Chibi cutout atlas | Exactly 1448 × 1086 |
| `pet-rig-winged-v1.png` | Winged cutout atlas | Exactly 1448 × 1086 |
| `pet-rig-chibi-dress-v1.png` | Chibi replacement dress | Exactly 1320 × 1192 |
| `press.wav`, `release.wav` | Optional interaction sounds | Valid WAV |

The historical file names are compatibility identifiers, not supplied content or a license to any character.

The atlas layout is explicitly defined in `macos/Sources/GPTNiangMac/PetRigView.swift`: `PetRigAssets.rects` controls the crop rectangles, and `drawChibi` / `drawWinged` control placement, order and anchors. These coordinates were designed for two specific private layouts, so a random full-body image cannot become a matching atlas merely by changing its name. Adapt the coordinates and anchors when creating a new design.

The eyes, closed-eye pair and smile are separate sprites. Both arms are independent whole-arm cutouts; there are no separate elbow or finger bones. Q-style legs are separate parts; the long-outfit layout keeps legs in the body image.

Invalid or missing atlases fall back to a complete illustration, then to the system symbol. No network asset fetch is performed. Chibi articulation requires both the chibi atlas and replacement-dress image. Winged articulation requires the winged atlas.

Before publishing an asset-enabled fork, verify the rights for every supplied image, reference, font and sound, and use a separate asset license where necessary. Do not remove these exclusions merely because an image was generated with AI.
