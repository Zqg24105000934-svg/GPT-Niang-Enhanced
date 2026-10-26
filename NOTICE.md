# Source provenance

## Upstream software

- Project: https://github.com/T7moris/GPT-Niang
- Baseline: v1.3.5, commit `b6f5eb8972d1802821006b7208d20a834fa6a08b`
- Copyright: 2026 T7moris and GPT-Niang contributors
- Source-code and documentation license: MIT; full notices are retained in `LICENSE` and `gpt-niang-usage/LICENSE`.

This public source snapshot includes local enhancements to the macOS companion and selected upstream runtime and test code. It is not an official upstream release. The enhanced build does not install upstream updates automatically.

## Enhanced implementation

The source adds bounded interaction sessions, articulated pose sampling, blinking, independent arm movement, cutout-atlas rendering, pointer reactions, drag/landing behavior and cadence controls. Enhancement source and the new public documentation are distributed under the repository's MIT license.

## Character artwork: separate terms

The repository now includes two generated full-body illustrations and three cutout texture atlases. These five PNG files are excluded from MIT and are subject to `gpt-niang-usage/assets/ASSET-LICENSE.md` and the retained upstream `CHARACTER-NOTICE.txt`. Permission is limited to the rights the maintainers can grant; third-party reference, character and trademark rights are not granted by the code license.

The original supplied reference photograph, upstream bust image, screenshots, icons, sound and video files are not included. Generated artwork based on a reference does not by itself establish third-party rights. No commercial or standalone asset-pack permission is granted. See `gpt-niang-usage/assets/GENERATED-ASSETS.md` for provenance.

## Quotation text

The upstream quotation set is retained with its attribution and MIT notice for the seven attributed lines. See `gpt-niang-usage/assets/quotes-LICENSE.txt`.

## Animation reference

https://github.com/MerZlin/dsh-pet-indesktop was studied for animation-state separation, bounded transitions, intentional idle pauses and resource throttling. No source implementation, character art, video, audio or font from that repository is included here.
