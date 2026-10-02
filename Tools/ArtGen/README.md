# ArtGen — Copper Kit illustration generator

`ArtGen.swift` renders every raster illustration of the app (3 onboarding
backgrounds, 9 transparent sprites, the 1024 px app icon) with a small CPU
signed-distance-field ray-marcher: rounded boxes, round cones, tori and extruded
2D profiles, with soft shadows, ambient occlusion, glossy soft-box reflections
on metal and lacquer, and a velvet sheen for linings. No dependencies beyond the
macOS SDK (CoreGraphics / ImageIO / simd). The engine is adapted from
`PlotLantern/Tools/ArtGen` (itself from TileLoom).

Art direction: *a glossy volumetric workshop of warm metal and deep-blue velvet*.
Soft studio key from the upper left, soft contact shadows, glints only on metal,
original invented objects — no text, letters, numbers, logos, coins, cards or
tape measures anywhere.

## Re-run

```sh
Tools/ArtGen/run.sh                                            # everything into CopperKit/Assets.xcassets (~5 min on 10 cores)
Tools/ArtGen/run.sh --only ck04_home_case,AppIcon              # just some assets
Tools/ArtGen/run.sh --out /tmp/art --scale 0.3 --ss 1 --preview                         # fast low-res review, sprites flattened on the app background
Tools/ArtGen/run.sh --out /tmp/art --scale 0.4 --ss 2 --preview-bg 111E3D --only ck04_home_case   # check the hero on the deep-blue panel
```

`run.sh` compiles with `xcrun swiftc -Ounchecked` (it sets
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if unset; compiling
takes ~40 s) and passes arguments through. Options: `--only a,b`, `--out <dir>`
(write plain files instead of the catalog), `--scale <f>`, `--ss <n>`
(supersampling per axis; defaults 3 for backgrounds, 4 for sprites and the
icon), `--preview` (flatten sprites on the app background `#F8F3E9`),
`--preview-bg light|blue|RRGGBB`, `--list`, `--root <projectRoot>`,
`--debug 1|2` (disable shadows / AO while tuning).

Writes, per asset, `CopperKit/Assets.xcassets/<name>.imageset/<name>.{png,jpg}` +
`Contents.json` (universal, single file), and
`AppIcon.appiconset/AppIcon-1024.png` + its `Contents.json` (iOS universal 1024
entry carries the file; the dark and tinted entries are kept empty; no macOS
entries).

| Asset | Size | Format | Shown |
| --- | --- | --- | --- |
| `ck01_onboarding_catalogue` | 1290×2796 | JPEG q0.9, opaque | Onboarding 1 — open case, every tool in a fitted cut-out |
| `ck02_onboarding_prepare` | 1290×2796 | JPEG q0.9, opaque | Onboarding 2 — gathering a few tools into a canvas roll |
| `ck03_onboarding_return` | 1290×2796 | JPEG q0.9, opaque | Onboarding 3 — two empty cut-outs, drill beside with a service tag |
| `ck04_home_case` | 1232×1136 | PNG, alpha | Home hero at 154×142 pt on a `#111E3D` panel |
| `ck05_copper_hammer` | 1024×1024 | PNG, alpha | Empty catalogue / tool without photo |
| `ck06_tool_tag` | 800×1000 | PNG, alpha | Tool editor without photos |
| `ck07_blue_tray` | 1040×880 | PNG, alpha | Storage empty state / location header |
| `ck08_tool_roll` | 1120×800 | PNG, alpha | Kits empty state |
| `ck09_glove_clipboard` | 800×880 | PNG, alpha | Prepare Kit header |
| `ck10_handover_case` | 960×800 | PNG, alpha | Checkout Review header |
| `ck11_closed_case` | 1000×900 | PNG, alpha | Handovers empty state |
| `ck12_service_tray` | 1000×900 | PNG, alpha | Service empty state |
| `AppIcon` | 1024×1024 | PNG, opaque | App icon (iOS applies the mask) |

Onboarding backgrounds keep every subject in the upper ~55 %; below that the
image blends into a calm gradient `#162548 → #0C1630` (`onboardingShader`), dark
enough for cream `#FFF4D8` text (contrast > 12:1).

## Palette (`enum Pal`, sRGB hex → linear)

| Role | Hex | Used for |
| --- | --- | --- |
| Bright Gold | `#FFD24C` | polished brass highlights, grips, the embossed mark (metal base `#E3AD3F`) |
| Copper | `#B46A32` | latches, rims, hammer head, clamp frame, spanner (highlight `#DC905A`) |
| Amber | `#FF9B2F` | enamel accents: drill stripe, screwdriver rings, service tag, glove cuff |
| Deep Blue | `#111E3D` | world; case lacquer `#15254B`; gradient `#162548 → #0C1630` |
| Velvet | `#263C68` | foam inserts, linings, pocket panel (floor `#1B2D55`, sheen `#7E98CC`) |
| Cream | `#FFF4D8` | enamel handles, glove, tags, paper, canvas `#F4E6C4` |
| App background | `#F8F3E9` | sprite review background |
| Text / secondary | `#242D43` / `#657087` | contact shadows / blank "writing" lines |
| Service brown | `#965D28` | tag string, leather straps (sparingly) |

## Structure

Engine (math, SDF primitives, marching, shadows, AO, soft boxes, cameras,
render/save, `SpriteShader`, `BGShader`) sits at the top of the file. Then the
shared material ids (`enum Mat`) and looks (`stdSurf`: brass, copper, enamel,
lacquer, velvet, fabric), the tools (`Screwdriver`, `Hammer`, `Wrench`,
`TrySquare`, `CClamp`, `Caliper`, `Drill` — all lying flat, profile in the local
xz plane), the brand mark (`handleMark`: a rounded grip bar with three raised
ridges and ring ferrules, never a letter), the `CasePart` (base + hinged lid,
foam with fitted cut-outs generated from each tool's mid-plane outline, handle,
latches, lid mark) and the props (`Tag`, `Cord`, `Glove`, `Clipboard`,
`ToolRoll`, `Drawer`, `Tray`). Each scene's layout, camera and lights live in its
`render…` function; `assets` at the end is the registry.

Performance notes: parts return their bounding-box distance only beyond
`boundSkip` (0.3), otherwise the under-estimated box distance darkens nearby
ground through AO and soft shadows. Keep arrays out of parts and scenes (a
stored array makes every copy of a scene do atomic ARC traffic across the render
threads); `Cord` keeps its samples in a raw buffer for that reason.

Illustrator art (WebP/PNG/JPEG) can replace these renders later via
`Tools/convert_webp_art.sh <folder>`; per-asset briefs are in
`Docs/AssetPrompts.md`.
