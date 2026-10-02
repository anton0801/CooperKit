# Copper Kit — asset prompts

Briefs for regenerating every raster asset with an illustrator or an image model.
The shipped placeholders are rendered procedurally by `Tools/ArtGen` (see its
README); drop replacements (WebP, PNG or JPEG named exactly like the asset) into
a folder and run `Tools/convert_webp_art.sh <folder>` to resize, validate and
install them into `CopperKit/Assets.xcassets`.

## Shared style (prepend to every prompt)

> Glossy volumetric 3D illustration, a workshop of warm metal and deep-blue
> velvet. Premium, soft studio lighting from the upper left, soft contact
> shadows, polished brass (#FFD24C highlights) and copper (#B46A32) metal parts,
> amber (#FF9B2F) enamel accents, cream (#FFF4D8) enamel handles, deep-blue
> (#111E3D) lacquered case shells, velvet (#263C68) foam linings with a soft
> sheen. Specular highlights and glints only on metal. Original, invented
> objects, clean and friendly, no brand shapes.

**Negative prompt / never include:** text, letters, numbers, logos, brand marks,
labels with writing, rulers or scale graduations, tape measures, coins, money,
banknotes, playing cards, chips, trophies, prizes, jackpots, treasure chests,
jewellery, gems, green or red accents, people's faces.

**Brand mark:** where a case shows an emblem, it is an abstract tool-handle
geometry embossed in raised gold on the deep-blue shell: a horizontal rounded
grip bar, fuller in the middle, with three raised ridges across its centre, a
ring ferrule toward each end and small domed end caps. Symmetrical, never a
letter or a monogram.

Sprites: transparent background, generous 6–8 % margins, nothing cropped, a
soft contact shadow is fine, silhouettes must read at the listed point sizes.

## Onboarding backgrounds

All three: 1290×2796 px, opaque JPEG. Perspective camera, deep-blue velvet
world. **All subjects in the upper ~55 %; the bottom 40 % is a calm, empty
deep-blue gradient (≈ #162548 at 60 % height → #0C1630 at the bottom)** — cream
#FFF4D8 UI text sits there and must stay legible.

### `ck01_onboarding_catalogue` — "Give Every Tool a Place"
> An open deep-blue lacquered tool case seen at three-quarters from above on
> deep-blue velvet, lid open behind it. Copper rim bands around the lid and
> base, two copper latches, a brass carry handle with a gold three-ridge grip.
> Inside, velvet foam with a fitted cut-out for every tool: a compact cordless
> drill (deep-blue body with an amber stripe, cream grip, copper chuck, brass
> bit), a copper C-clamp with a brass screw, a cream-handled screwdriver, a
> copper open-end spanner; in the lid lining a golden try-square (L-shape with a
> copper stock), a golden sliding caliper without any graduations and a small
> copper-headed hammer. A small blank cream tag on a blue cord tied to the
> handle rests on the velvet. Warm spotlight pool around the case, calm and
> organised, a place for each tool.

### `ck02_onboarding_prepare` — "Build the Kit Before You Begin"
> On deep-blue velvet, seen from above at about 55°: an unrolled cream canvas
> tool roll with a velvet-blue pocket panel, cream stitching and two leather
> straps with copper buckles. Only a few chosen tools are tucked in — a
> cream-handled screwdriver and a copper spanner — two pockets are still free.
> A copper-headed hammer with a cream handle lies beside it, about to be packed,
> and a clean clipboard (deep-blue board, brass clip, cream sheet with three
> blank grey lines, no writing) sits at the upper left. Relaxed, a small
> selection, not a complete repair set.

### `ck03_onboarding_return` — "Know What Still Needs to Come Back"
> The same open deep-blue case on velvet, most fitted cut-outs filled (spanner,
> C-clamp, try-square, caliper, hammer) but two cut-outs empty — the drill-shaped
> one and the screwdriver-shaped one — so their outlines are clearly visible in
> the foam. The drill rests on the velvet beside the case, a small blank amber
> service tag tied to its grip with a brown string. Calm and informative, no
> sadness.

## Sprites (transparent PNG)

### `ck04_home_case` — 1232×1136 px, shown at 154×142 pt on a #111E3D panel
> The open deep-blue case with its kit (drill, screwdriver, C-clamp, spanner in
> the base foam; try-square and caliper in the lid), three-quarter view from the
> front left. It must read on a dark blue panel: strong warm gold/copper rim
> light along every edge, copper rims glowing, the velvet interior lit in warm
> cream light, a soft dark-blue contact shadow.

### `ck05_copper_hammer` — 1024×1024 px, shown at 96–112 pt on #F8F3E9
> A single claw hammer lying diagonally (head top right): polished copper head
> with a round striking face and a curved claw, cream enamel handle with a
> copper collar and a small gold end cap. Soft shadow, generous margins.

### `ck06_tool_tag` — 800×1000 px, shown at 64×80 pt
> A blank luggage-style tool tag lying almost flat, portrait: cream face framed
> by a thin polished brass rim, clipped top corners, a copper eyelet near the
> top and a short blue cord looping above it with a small knot. Nothing written
> on it.

### `ck07_blue_tray` — 1040×880 px, shown at 104×88 pt
> A deep-blue lacquered pull-out drawer seen from the front left and above: a
> taller front panel with a thin copper frame and a brass D-shaped pull on
> copper roses, copper side runners, a velvet-lined floor with one
> cream-handled screwdriver inside.

### `ck08_tool_roll` — 1120×800 px, shown at 112×80 pt
> An unrolled canvas tool roll seen from above: cream canvas with a velvet-blue
> binding, a velvet-blue pocket panel with cream stitching, four pockets holding
> two cream-handled screwdrivers, a copper spanner (open end up) and a
> copper-headed hammer (head up); the right end loosely rolled with two leather
> straps and copper buckles.

### `ck09_glove_clipboard` — 800×880 px, shown at 80×88 pt
> A chunky, friendly cream work glove with an amber gauntlet cuff (cream rolled
> rim, small copper snap) resting on a clean clipboard: deep-blue board, brass
> clip with a gold wire lever, cream sheet with three blank rounded grey lines —
> no text, no checkmarks.

### `ck10_handover_case` — 960×800 px, shown at 96×80 pt
> Hand-over: a small deep-blue case standing upright (raised gold handle-mark
> on its face, copper latches on the top edge) held by its brass carry handle
> by two stylised chunky mitten-like gloved hands side by side, cream gloves
> with amber cuffs rising up and out to the left and right. Simple, readable at
> 96 pt, the case hangs just above a soft shadow.

### `ck11_closed_case` — 1000×900 px
> A small closed deep-blue lacquered case, three-quarter view from the front:
> copper rim at the seam, two copper latches, brass handle with a gold
> three-ridge grip, the raised gold handle-mark embossed on the lid, a small
> blank cream tag on a blue cord hanging from the handle.

### `ck12_service_tray` — 1000×900 px
> A shallow deep-blue tray with a copper rim bead and a velvet-lined floor,
> seen from above at about 45°: a copper open-end spanner with a blank amber
> service tag tied to its ring end by a brown string, and a screwdriver with a
> cream handle.

## App icon

### `AppIcon` — 1024×1024 px, opaque PNG (no rounded mask, iOS applies it)
> Close-up of a deep-blue lacquered case standing upright on a deep-blue velvet
> ground, seen almost from the front with a slight three-quarter turn. In the
> centre of its face the raised golden handle-mark (horizontal grip bar, three
> ridges, ring ferrules). Two copper latches and a brass handle with a gold
> ridged grip on the top edge, copper rim along the seam, soft gold rim light on
> the edges, glossy soft reflections kept away from the mark. No text.
