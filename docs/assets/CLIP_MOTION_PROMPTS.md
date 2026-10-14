# Clip poses and flexible paper

Generated with the built-in imagegen tool. Transparent originals are saved under `Sources/ClampEverything/Resources/Generated/`. Each pose preserves the existing metal clip identity. Runtime animation blends the poses; paper deformation is implemented in SwiftUI.

## clip-silver-open

Reference/edit target: `clip-silver.png`.

Use case: precise-object-edit. Asset type: transparent macOS skeuomorphic clip animation sprite. Edit target: the referenced silver bulldog clip. Show the SAME clip in its fully opened mechanical pose: the spring hinge is squeezed and the two jaws at the RIGHT edge separate with a clearly visible narrow 15-degree mouth gap, the wire handles tilt slightly toward one another. Keep its exact horizontal orientation, silver brushed metal, width, jaw position at right, wire loop at left, frontal camera, soft studio highlights and canvas framing identical. Real physically plausible spring clip mechanics. No paper, no hands, no extra objects, no text, no background. Genuine transparent alpha. This must be an OPEN JAW pose rather than merely rotating the entire closed clip.

## clip-silver-half

Reference/edit target: `clip-silver.png`.

Use case: precise-object-edit. Asset type: transparent macOS skeuomorphic clip animation sprite. Edit target: the referenced silver bulldog clip. Show the SAME clip half closing: the two jaws at the RIGHT edge leave a small clearly readable 6-degree mouth gap, spring hinge and wire handle have an intermediate squeezed position. Keep exact horizontal orientation, silver brushed metal, width, jaw position right, wire loop left, frontal camera, soft studio highlights and canvas framing identical. Real physically plausible spring mechanics. No paper, no hands, no extra objects, no text, no background. Genuine transparent alpha. Change the jaw opening, not the rotation of the whole clip.

## clip-brass-open

Reference/edit target: `clip-brass.png`.

Use case: precise-object-edit. Asset type: transparent macOS skeuomorphic receiving clip animation sprite. Edit target: the referenced brass PLUS bulldog clip. Show the SAME clip in its fully opened mechanical pose: squeezed spring hinge and the two jaws at the RIGHT edge separate with a clearly visible 15-degree mouth gap, wire handle slightly squeezed. Keep the embossed plus sign, brass face, silver wire loop left, jaw right, horizontal orientation, exact width and camera framing, light and brushed texture. Physically plausible office clip mechanism. No paper, hands or extra objects. Genuine transparent alpha background.

## paper-soft-curl

Use case: product-mockup. Asset type: transparent paper material for a lightweight macOS desktop clipping app. One blank warm ivory sheet of thin cotton writing paper, full sheet straight-on front view, portrait rectangular aspect ratio roughly 3:4. Delicate genuine fibre texture, gently irregular deckled perimeter. A silver clip will later hold the upper right corner but do NOT render any clip. Make the upper right 2cm of paper subtly compressed with two short tension creases radiating inward, a very gentle gravity bow down the sheet, the lower left edge curling toward the viewer by just a few millimetres. Thin flexible paper, calm restrained realism, mostly flat blank usable surface for text. Soft neutral top-left light, very faint self-shadow inside the curl, clean genuine transparent alpha around the entire silhouette. No printed words, no ruler, no hands, no desk, no objects, no heavy wrinkles, no dark vignette.

## paper-soft-wave

Use case: product-mockup. Asset type: transparent paper material variant for a lightweight macOS desktop clipping app. One blank warm ivory sheet of thin cotton writing paper, full sheet straight-on front view, portrait rectangular aspect ratio roughly 3:4. Very fine real fibres and gently uneven handmade edges. The upper right corner will later be held by a clip but do NOT render any clip. Delicate diagonal tension fold close to that corner, the free bottom edge makes a shallow organic wave and bottom right corner turns forward slightly; use thin soft writing paper rather than stiff cardboard. The main writing area is calm and almost flat. Soft neutral top-left light and very subtle self shadows reveal flexibility. Genuine transparent alpha outside the entire paper perimeter. No printed words, no desk, no hands, no objects, no large crumpling or dramatic wrinkles.

## cursor-clip-motion-v2

2026-10-14: Replaced the cursor-only atlas after checking user photographs IMG_6757–IMG_6760. Silver brushed stainless finish; oblique side profile; mouth left and two wire handles right. Three equal cells: open, half, closed. Complete rectangular leaves separate; handles converge as the mouth opens. The old split-face atlas is retained only as a historical asset. Runtime uses single-frame selection, common scale and measured mouth-centre alignment; it does not crossfade poses. The accepted source is `exec-aaa3e8d2-ae4b-45e3-ae32-9fa9d0fe9498.png`, copied into the project's resources. This is a visual approximation, not an engineering kinematics model.

### User-selected loop repair

User selected the horizontal three-pose atlas and marked the missing lower wire-loop handles in the first two cells. Edited only the requested loops using the annotated image; preserved the selected composition and silver material. Accepted generated source: `exec-9bda71b2-ab75-42a8-be7f-92678a61a419.png`, installed as `cursor-clip-motion-v2.png`. The diagonal angle study remains a separate unused design study.
