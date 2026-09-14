# 🧊 GLB export

`pcb_output_glb` exports the board as a binary glTF file ready to drop into a
web renderer such as PlayCanvas, three.js or Babylon.

```yaml
- name: Export board as GLB
  uses: actions-for-kicad/kicad-actions@v2-k10.0
  with:
    pcb_file_name: ./board.kicad_pcb
    pcb_output_glb: true
    pcb_output_glb_file_name: board.glb

- name: Upload GLB
  uses: actions/upload-artifact@v7
  with:
    path: ./board.glb
    archive: false
```

## Which copper gets exported

`kicad-cli` can export tracks, zones, pads and inner copper layers, and by
default this action exports **only pads**.

Once the soldermask is opaque — which is what the post-processing makes it, and
what a real board looks like — tracks, zones and inner layers are completely
hidden. Exporting them adds geometry that is never visible: on a small test
board, turning tracks and zones on roughly doubles the triangle count for no
change to the render. Pads stay on because they are the copper that shows
through the mask openings.

If you want the routing visible, the way it is on a real board where the mask
is a thin translucent coat over the copper, turn on `pcb_output_glb_tracks` and
`pcb_output_glb_zones` and set `pcb_output_glb_mask_opacity` to `0.83`, KiCad's
own value. Only the mask stays blended; the board body and silkscreen remain
opaque, so tracks and tented vias read as tinted relief rather than as bare
copper. See [`pcb_output_glb_mask_opacity`](#pcb_output_glb_mask_opacity).

## What the post-processing does

`kicad-cli` produces its GLB through OpenCASCADE, which targets CAD viewers.
Several of its choices look wrong in a real-time renderer, so
`pcb_output_glb_optimize` (on by default) rewrites the glTF metadata. Geometry
is never touched, so the pass is lossless.

| Issue | What KiCad emits | What the renderer does with it | Fix |
| --- | --- | --- | --- |
| Component materials | `baseColorFactor` only, no `metallicFactor` or `roughnessFactor` | glTF defaults both to `1.0`, so every part is fully metallic and fully rough — dark and muddy under image-based lighting | Fill in plausible PBR values, detecting bare metal by colour |
| Transparency | board, soldermask and silkscreen are all `alphaMode: BLEND` | Transparent meshes are depth-sorted per object, so the stacked layers z-fight and pop while orbiting | Make them opaque. With `pcb_output_glb_mask_opacity` below 1 the mask alone stays blended, which a single layer above opaque geometry survives |
| Backface culling | `doubleSided: true` on everything | Culling is disabled, doubling fragment cost | Turn it off, having verified triangle winding matches the vertex normals |
| Naming | nodes are OpenCASCADE label paths (`=>[0:1:1:4]`), materials are `mat_0`…`mat_n` | Nothing in the scene can be addressed from engine script | Name them `Board`, `SolderMask_Front`, `Silkscreen_Front`, `Pads`, `Copper_Front`, and components after their reference designator |
| Origin | the board sits offset from the origin, in metres | The model orbits around a pivot outside itself | Recentre on the board bounding box |

The resulting scene graph looks like this, and every name is stable:

```
PCB
├── Board
├── SolderMask_Front
├── SolderMask_Back
├── Silkscreen_Front
├── Copper_Front
├── Copper_Back
├── Pads
├── D101
│   └── D101_Model
└── J3                      # multi-solid STEP model
    └── J3_Assembly
        ├── J3_Model
        └── J3_Model_2
```

A component whose 3D model contains several solids gets an extra assembly
level, because that is how OpenCASCADE structures it. Those intermediate nodes
are named after the part they belong to rather than left as label paths.

Two-sided layers are split by geometry, not by mesh order: the layers are
ranked by the height of their bounding-box centre, so `Copper_Front` is the
copper that is actually on top and stays that name across exports. With
`pcb_output_glb_inner_copper: true` the layers in between come out as
`Copper_1`, `Copper_2` and so on, front to back. If a board somehow yields
several copper meshes at the same height there is nothing to rank them by, and
they fall back to `Copper` and `Copper_2` in mesh order.

Set `pcb_output_glb_optimize: false` to get `kicad-cli`'s output untouched.

## Component materials

Board layers get materials named after themselves — `Board`, `SolderMask_Front`
and so on. Component materials are named after their colour instead, for
example `Component_EDBE51`. That is deliberate: a running index would shift
whenever the board gains or loses a part, silently retargeting any material
override written against it. A colour-derived name stays put.

Because `kicad-cli` emits no `metallicFactor` for model-derived materials, the
metal-versus-plastic call has to be guessed from colour, and
`pcb_output_glb_detect_metals` does that by treating unsaturated mid-grey as
bare metal. It reliably catches tinned leads and shielding cans, and reliably
rejects black IC bodies and ceramic capacitors.

It cannot catch everything, and this is a limitation of the input rather than
of the rule:

- **Coloured metals** — gold plating and copper are saturated, so they fall
  outside an unsaturated-grey test.
- **Shared materials** — one material can serve both a white plastic housing
  and a nickel-plated connector shell. There is a single colour for both
  surfaces, so no colour test can separate them.

Rather than guess harder, use `pcb_output_glb_metal_colors` to name the
offenders once. Run the export, look at the material list, and list the
colours that should be metal:

```yaml
pcb_output_glb_metal_colors: "EDBE51,97A3DA,FFFFFF"
```

Colours are matched against component materials only, so a colour that also
appears on a board layer — `FFFFFF` is both a connector shell and the
silkscreen — affects only the components. Entries that match nothing are
reported as a warning, which catches typos.

## Component 3D models

The `kicad/kicad` base image ships footprints and symbols but **no 3D model
libraries**, so components referencing the standard KiCad libraries are
silently dropped and you get a bare board. To get components in your GLB,
commit the models alongside your project and point the footprints at them with
a relative path or a project variable.

The action also aliases the legacy `KICAD6_3DMODEL_DIR` through
`KICAD11_3DMODEL_DIR` variables to the current version's model directory.
KiCad only defines the variable for its own major version, so a board authored
in KiCad 8 that refers to `${KICAD8_3DMODEL_DIR}` would otherwise lose every
component when exported by KiCad 10 — the GUI migrates those references, but
`kicad-cli` does not.

## Notes for PlayCanvas

- glTF units are metres, so a 100 mm board arrives as 0.1 units. Either scale
  the entity in PlayCanvas or export with `pcb_output_glb_scale: 1000`.
- The model has no UV channels, because KiCad emits none. Materials are flat
  colours, which is enough for a board but means image textures cannot be
  applied without generating UVs first.
- The mesh is not Draco or meshopt compressed. If you need that, run
  `gltf-transform` on the artifact in a later workflow step.

# 📥 GLB inputs

## `pcb_output_glb`

Required: `false`\
Default: `false`\
\
Description: Run the GLB (binary glTF) export of the PCB. See
[GLB export](#-glb-export) for what the defaults do and why.

## `pcb_output_glb_file_name`

Required: `false`\
Default: `pcb.glb`\
\
Description: Output file name of GLB PCB. Must end in `.glb`.

## `pcb_output_glb_soldermask`

Required: `false`\
Default: `true`\
\
Description: Export the soldermask layers. Without this KiCad flat-colours the
board body instead of producing a real mask surface.

## `pcb_output_glb_silkscreen`

Required: `false`\
Default: `true`\
\
Description: Export the silkscreen graphics as flat faces.

## `pcb_output_glb_pads`

Required: `false`\
Default: `true`\
\
Description: Export pads. This is the copper you actually see, through the
soldermask openings.

## `pcb_output_glb_tracks`

Required: `false`\
Default: `false`\
\
Description: Export tracks and vias. These sit under an opaque soldermask and
contribute nothing to the visible result, so they are off by default.

## `pcb_output_glb_zones`

Required: `false`\
Default: `false`\
\
Description: Export copper zones. Hidden under the soldermask, as with tracks.

## `pcb_output_glb_inner_copper`

Required: `false`\
Default: `false`\
\
Description: Export inner copper layers. These are never visible from outside
the board.

## `pcb_output_glb_components`

Required: `false`\
Default: `true`\
\
Description: Include component 3D models. See
[Component 3D models](#component-3d-models) — the base image ships none, so
the models have to come from your repository.

## `pcb_output_glb_board_only`

Required: `false`\
Default: `false`\
\
Description: Export only the bare board, with no components.

## `pcb_output_glb_component_filter`

Required: `false`\
\
Description: Only include component 3D models matching this comma-separated
list of reference designators. Wildcards supported, for example `U*,J1`.

## `pcb_output_glb_net_filter`

Required: `false`\
\
Description: Only include copper items belonging to nets matching this
wildcard.

## `pcb_output_glb_no_dnp`

Required: `false`\
Default: `false`\
\
Description: Exclude 3D models for components marked 'Do not populate'.

## `pcb_output_glb_no_unspecified`

Required: `false`\
Default: `false`\
\
Description: Exclude 3D models for components with an 'Unspecified' footprint
type.

## `pcb_output_glb_subst_models`

Required: `false`\
Default: `false`\
\
Description: Substitute STEP or IGS models for VRML models with the same name.

## `pcb_output_glb_fuse_shapes`

Required: `false`\
Default: `false`\
\
Description: Fuse overlapping geometry together. Slower, but removes coincident
surfaces.

## `pcb_output_glb_min_distance`

Required: `false`\
Default: `0.01mm`\
\
Description: Minimum distance between points to treat them as separate ones.

## `pcb_output_glb_origin`

Required: `false`\
Default: `board`\
\
Description: Origin of the exported model. Options: `board`, `grid`, `drill`,
or an explicit offset such as `25.4x25.4mm`.

The three named origins are matched exactly, in lower case; anything else is
treated as an explicit offset and must look like `<x>x<y>mm` or `<x>x<y>in`
(negatives allowed). A malformed value fails the export with an error naming
it, rather than being passed to `kicad-cli` — which rejects it with an exit
code the export deliberately treats as success, so it would otherwise surface
only as a missing output file.

## `pcb_output_glb_optimize`

Required: `false`\
Default: `true`\
\
Description: Post-process the GLB for real-time renderers such as PlayCanvas,
three.js or Babylon. Set to `false` to get exactly what `kicad-cli` produces.
See [What the post-processing does](#what-the-post-processing-does).

## `pcb_output_glb_center`

Required: `false`\
Default: `true`\
\
Description: Recentre the model on the board bounding box so it orbits around
itself instead of a point off to one side. Requires `pcb_output_glb_optimize`.

## `pcb_output_glb_scale`

Required: `false`\
Default: `1.0`\
\
Description: Uniform scale applied to the exported model. glTF units are
metres, so a 100 mm board is 0.1 units at the default scale. Use `1000` if you
want the model to arrive in millimetres.

Must be a positive number; `0` is rejected rather than written out as a scale
that would collapse the model to a point. Combines correctly with
`pcb_output_glb_center` — the recentre is applied in the scaled space, so the
board stays on the pivot at any scale.

## `pcb_output_glb_detect_metals`

Required: `false`\
Default: `true`\
\
Description: Treat unsaturated mid-grey component colours as bare metal, so
leads and shielding cans render metallic rather than as grey plastic. See
[Component materials](#component-materials) for what this can and cannot get
right.

## `pcb_output_glb_metal_colors`

Required: `false`\
\
Description: Comma-separated hex colours whose component materials are forced
metallic, for example `EDBE51,97A3DA`. Overrides the colour heuristic. Board
layers are never affected, so listing `FFFFFF` cannot make the silkscreen
metallic. See [Component materials](#component-materials).

## `pcb_output_glb_mask_opacity`

Required: `false`\
Default: `1.0`\
\
Description: Opacity of the soldermask, above 0 and up to 1. At `1.0` the mask
is opaque and hides every copper item under it, which is why only pads are
exported by default. Below 1 the mask keeps `alphaMode: BLEND` at this alpha
while the board body and silkscreen stay opaque. Copper under the mask then
shows through tinted, the way tracks and tented vias look on a real board.
`0.83` is what KiCad itself uses. Pair it with `pcb_output_glb_tracks` and
`pcb_output_glb_zones`, or there is nothing under the mask to see; the action
warns when that happens. A single blended layer above opaque geometry sorts
correctly in real-time renderers. It is the full stack of blended layers that
`pcb_output_glb_keep_transparency` restores which does not.

## `pcb_output_glb_keep_transparency`

Required: `false`\
Default: `false`\
\
Description: Keep the board, soldermask and silkscreen as blended transparent
materials, the way KiCad exports them. These sort badly in real-time
renderers, so this is off by default.
