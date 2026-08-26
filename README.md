![Count of Action Users](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/actions-for-kicad/kicad-actions/refs/heads/gh-pages/docs/kicad-actions.json)
![Release](https://img.shields.io/github/v/release/actions-for-kicad/kicad-actions)
![License](https://img.shields.io/github/license/actions-for-kicad/kicad-actions)
![Workflow Status](https://img.shields.io/github/actions/workflow/status/actions-for-kicad/kicad-actions/tests.yml?branch=main&label=tests)
![Open Issues](https://img.shields.io/github/issues/actions-for-kicad/kicad-actions)

# KiCad actions

This GitHub Action provides a way to run [KiCad](https://www.kicad.org/) in your CI pipelines.

# 🧾 Versioning

Every release of this action is tagged with two version numbers:

- 📦 **Action version** — Version of this GitHub Action
- ⚙️ **KiCad version** — Version of KiCad used inside the action

The releases are formatted as follows:

```
v{action-version}-k{KiCad-version}
```

For example `v2-k10.0`. This houses version `2` of this action and version `10.0` from KiCad.

The KiCad version can be set to the `minor` or `patch` version. For example:

- Use `v{action-version}-k10.0` to to get the latest version of KiCad `v10.0` (for example `v10.0.2`).
- Use `v{action-version}-k10.0.0` to to get the specific requested version of KiCad.

Check the [releases](https://github.com/actions-for-kicad/kicad-actions/releases) to see all available versions.

# 🚀 Usage

See [action.yml](action.yml)

```yaml
steps:
  - name: Checkout Repository
    uses: actions/checkout@v6

  - name: Run KiCad actions
    uses: actions-for-kicad/kicad-actions@v2-k10.0
    with:
      schematic_file_name: ./file.kicad_sch
      symbol_libraries: "symbol-library=./symbol-library.kicad_sym"
      run_erc: true
      schematic_output_pdf: true

      pcb_file_name: ./file.kicad_pcb
      footprint_libraries: "footprint-library=./footprint-library.pretty"
      run_drc: true
      pcb_output_gerbers_and_drill: true
      pcb_output_image: true

  - name: Upload schematic
    uses: actions/upload-artifact@v7
    with:
      path: ./schematic.pdf
      archive: false

  - name: Upload gerbers and drill file
    uses: actions/upload-artifact@v7
    with:
      name: Gerbers
      path: ./gerbers

  - name: Upload image render
    uses: actions/upload-artifact@v7
    with:
      path: ./pcb.png
      archive: false
```

# 📥 Inputs

## `project_file_name`

Required: `false`\
\
Description: The project file, used for running a jobset. Not required if there
is a single `.kicad_pro` file in the working directory.

## `schematic_file_name`

Required: `false`\
\
Description: Location of the `.kicad_sch` file.

## `symbol_libraries`

Required: `false`\
\
Description: Comma-separated list of symbol libraries in the format name=path. The path should be relative to the `.kicad_pro` file.

## `run_erc`

Required: `false`\
Default: `false`\
\
Description: Run the ERC (Electrical Rules Check) on the schematic.

## `erc_output_file_name`

Required: `false`\
Default: `erc.rpt`\
\
Description: Output file name of ERC report.

## `schematic_output_pdf`

Required: `false`\
Default: `false`\
\
Description: Run the PDF export of the schematic.

## `schematic_output_pdf_file_name`

Required: `false`\
Default: `schematic.pdf`\
\
Description: Output file name of PDF schematic.

## `schematic_output_pages`

Required: `false`\
\
Description: Comma-separated list of schematic pages to include in exports.

## `schematic_output_black_white`

Required: `false`\
Default: `false`\
\
Description: Run the PDF, SVG, DXF, and PS schematic export in black and white.

## `schematic_output_svg`

Required: `false`\
Default: `false`\
\
Description: Run the SVG export of the schematic.

## `schematic_output_svg_folder_name`

Required: `false`\
Default: `schematics`\
\
Description: Output folder name of SVG schematic.

## `schematic_output_dxf`

Required: `false`\
Default: `false`\
\
Description: Run the DXF export of the schematic.

## `schematic_output_dxf_folder_name`

Required: `false`\
Default: `schematics`\
\
Description: Output folder name of DXF schematic.

## `schematic_output_ps`

Required: `false`\
Default: `false`\
\
Description: Run the PS export of the schematic.

## `schematic_output_ps_folder_name`

Required: `false`\
Default: `schematics`\
\
Description: Output folder name of PS schematic.

## `schematic_output_bom`

Required: `false`\
Default: `false`\
\
Description: Run the BOM (Bill of Materials) export of the schematic.

## `schematic_output_bom_file_name`

Required: `false`\
Default: `bom.csv`\
\
Description: Output file name of the BOM.

## `schematic_output_bom_fields`

Required: `false`\
Default: `Reference,Value,Footprint,${QUANTITY},${DNP}`\
\
Description: Output fields in the BOM file. `*` includes all fields.

## `schematic_output_bom_labels`

Required: `false`\
Default: `Refs,Value,Footprint,Qty,DNP`\
\
Description: Output labels in the BOM file.

## `schematic_output_netlist`

Required: `false`\
Default: `false`\
\
Description: Run the netlist export of the schematic.

## `schematic_output_netlist_file_name`

Required: `false`\
Default: `netlist.net`\
\
Description: Output file name of the netlist.

## `schematic_output_xml_netlist`

Required: `false`\
Default: `false`\
\
Description: Run the netlist export of the schematic, in XML format for further
processing.

## `schematic_output_xml_netlist_file_name`

Required: `false`\
Default: `netlist.xml`\
\
Description: Output file name of the XML netlist.

## `pcb_file_name`

Required: `false`\
\
Description: Location of the `.kicad_pcb` file.

## `footprint_libraries`

Required: `false`\
\
Description: Comma-separated list of footprint libraries in the format name=path. The path should be relative to the `.kicad_pro` file.

## `run_drc`

Required: `false`\
Default: `false`\
\
Description: Run the DRC (Design Rules Check) on the PCB.

## `drc_output_file_name`

Required: `false`\
Default: `drc.rpt`\
\
Description: Output file name of DRC report.

## `pcb_output_drill`

Required: `false`\
Default: `false`\
\
Description: Run the drill export of the PCB.

## `pcb_output_drill_folder_name`

Required: `false`\
Default: `drill`\
\
Description: Output folder name of drill file.

## `pcb_output_drill_format`

Required: `false`\
Default: `excellon`\
\
Description: Format of the drill file. Options:

- `excellon`
- `gerber`

## `pcb_output_drill_split`

Required: `false`\
Default: `false`\
\
Description: Only used for `excellon` drill format. When `true` tells
`kicad-cli` to split plated and non-plated holes into dedicated filed.

## `pcb_output_gerbers`

Required: `false`\
Default: `false`\
\
Description: Run the gerber export of the PCB.

## `pcb_output_gerbers_folder_name`

Required: `false`\
Default: `gerbers`\
\
Description: Output folder name of gerber files.

## `pcb_output_layers`

Required: `false`\
\
Description: Output layers of the PCB.

## `pcb_output_gerbers_and_drill`

Required: `false`\
Default: `false`\
\
Description: Run the gerber and drill export of the PCB.

## `pcb_output_gerbers_and_drill_folder_name`

Required: `false`\
Default: `gerbers`\
\
Description: Output folder name of gerber and drill files.

## `pcb_output_dxf`

Required: `false`\
Default: `false`\
\
Description: Run the DXF export of the PCB.

## `pcb_output_dxf_folder_name`

Required: `false`\
Default: `dxf`\
\
Description: Output folder name of DXF PCB.

## `pcb_output_pdf`

Required: `false`\
Default: `false`\
\
Description: Run the PDF export of the PCB.

## `pcb_output_pdf_file_name`

Required: `false`\
Default: `pcb.pdf`\
\
Description: Output file name of PDF PCB.

## `pcb_output_black_white`

Required: `false`\
Default: `false`\
\
Description: Run the PDF and SVG PCB export in black and white.

## `pcb_output_svg`

Required: `false`\
Default: `false`\
\
Description: Run the SVG export of the PCB.

## `pcb_output_svg_file_name`

Required: `false`\
Default: `pcb.svg`\
\
Description: Output file name of SVG PCB.

## `pcb_output_pos`

Required: `false`\
Default: `false`\
\
Description: Run the POS export of the PCB.

## `pcb_output_pos_file_name`

Required: `false`\
Default: `pcb.pos`\
\
Description: Output file name of POS PCB.

## `pcb_output_pos_format`

Required: `false`\
Default: `ascii`\
\
Description: Format of the POS file. Options:

- `ascii`
- `csv`
- `gerber`

## `pcb_output_pos_side`

Required: `false`\
Default: `both`\
\
Description: Side of the POS file. Options:

- `front`
- `back`
- `both`

> **Note:** both is not supported by gerber.

## `pcb_output_ipc2581`

Required: `false`\
Default: `false`\
\
Description: Run the IPC-2581 export of the PCB.

## `pcb_output_ipc2581_file_name`

Required: `false`\
Default: `pcb.xml`\
\
Description: Output file name of IPC-2581 PCB.

## `pcb_output_step`

Required: `false`\
Default: `false`\
\
Description: Run the STEP export of the PCB.

## `pcb_output_step_file_name`

Required: `false`\
Default: `pcb.step`\
\
Description: Output file name of STEP PCB.

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

## `pcb_output_glb_keep_transparency`

Required: `false`\
Default: `false`\
\
Description: Keep the board, soldermask and silkscreen as blended transparent
materials, the way KiCad exports them. These sort badly in real-time
renderers, so this is off by default.

## `pcb_output_image`

Required: `false`\
Default: `false`\
\
Description: Run the image export of the PCB.

## `pcb_output_image_file_name`

Required: `false`\
Default: `pcb.png`\
\
Description: Output file name of image PCB. Must end in '.png', '.jpg', '.jpeg'.

## `pcb_output_image_side`

Required: `false`\
Default: `top`\
\
Description: Side of the image PCB. Options:

- `top`
- `bottom`
- `left`
- `right`
- `front`
- `back`

## `pcb_output_image_background`

Required: `false`\
Default: `default`\
\
Description: Background of the image PCB. Options:

- `default`
- `transparent`
- `opaque`

For PNG files, default is transparent. For JPG files, default is opaque.

## `pcb_output_image_width`

Required: `false`\
Default: `1600`\
\
Description: Width of the image PCB in pixels.

## `pcb_output_image_height`

Required: `false`\
Default: `900`\
\
Description: Height of the image PCB in pixels.

## `pcb_output_image_floor`

Required: `false`\
Default: `false`\
\
Description: Enables floor, shadows and post-processing.

## `pcb_output_image_perspective`

Required: `false`\
Default: `false`\
\
Description: Enables perspective view.

## `pcb_output_image_quality`

Required: `false`\
Default: `default`\
\
Description: Quality of the image PCB. Options:

- `basic`
- `high`
- `user`

## `pcb_output_image_zoom`

Required: `false`\
Default: `1.0`\
\
Description: Zoom factor of the image PCB.

## `pcb_output_image_rotate`

Required: `false`\
Default: `0,0,0`\
\
Description: "Rotation of the image PCB. Format: 'x,y,z'."

## `jobset_file_name`

Required: `false`\
\
Description: Run a predefined KiCad jobset file.

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

If you want the see-through look where the routing is visible under a
translucent mask, turn on `pcb_output_glb_tracks` and
`pcb_output_glb_zones` together with `pcb_output_glb_keep_transparency`.

## What the post-processing does

`kicad-cli` produces its GLB through OpenCASCADE, which targets CAD viewers.
Several of its choices look wrong in a real-time renderer, so
`pcb_output_glb_optimize` (on by default) rewrites the glTF metadata. Geometry
is never touched, so the pass is lossless.

| Issue | What KiCad emits | What the renderer does with it | Fix |
| --- | --- | --- | --- |
| Component materials | `baseColorFactor` only, no `metallicFactor` or `roughnessFactor` | glTF defaults both to `1.0`, so every part is fully metallic and fully rough — dark and muddy under image-based lighting | Fill in plausible PBR values, detecting bare metal by colour |
| Transparency | board, soldermask and silkscreen are all `alphaMode: BLEND` | Transparent meshes are depth-sorted per object, so the stacked layers z-fight and pop while orbiting | Make them opaque |
| Backface culling | `doubleSided: true` on everything | Culling is disabled, doubling fragment cost | Turn it off, having verified triangle winding matches the vertex normals |
| Naming | nodes are OpenCASCADE label paths (`=>[0:1:1:4]`), materials are `mat_0`…`mat_n` | Nothing in the scene can be addressed from engine script | Name them `Board`, `SolderMask_Front`, `Silkscreen_Front`, `Pads`, `Copper`, and components after their reference designator |
| Origin | the board sits offset from the origin, in metres | The model orbits around a pivot outside itself | Recentre on the board bounding box |

The resulting scene graph looks like this, and every name is stable:

```
PCB
├── Board
├── SolderMask_Front
├── SolderMask_Back
├── Silkscreen_Front
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

# 📤 Outputs

This action exports multiple files based on the inputs that are given.

# 📄 License

The scripts and documentation in this project are released under the [MIT license](LICENSE).

# 🧑‍💻 Contributions

Contributions are welcome! Please help me expand and maintain this repository.
