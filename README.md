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

For example `v1-k9.0`. This houses version one of this action and version `9.0` from KiCad.

The KiCad version can be set to the `major`, `minor` or `patch` version. For example:

- Use `v{action-version}-k9` to to get the latest version of KiCad `v9` (for example `v9.0.2`).
- Use `v{action-version}-k9.0` to to get the latest version of KiCad `v9.0` (for example `v9.0.2`).
- Use `v{action-version}-k9.0.1` to to get the specific requested version of KiCad.

Check the [releases](https://github.com/actions-for-kicad/kicad-actions/releases) to see all available versions.

# 🚀 Usage

See [action.yml](action.yml)

```yaml
steps:
  - name: Checkout Repository
    uses: actions/checkout@v4

  - name: Run KiCad actions
    uses: actions-for-kicad/kicad-actions@v1-k9.0
    with:
      schematic_file_name: ./file.kicad_sch
      symbol_libraries: "symbol-library=./symbol-library.kicad_sym"
      run_erc: true
      schematic_output_pdf: true

      pcb_file_name: ./file.kicad_pcb
      footprint_libraries: "footprint-library=./footprint-library.pretty"
      run_drc: true
      pcb_output_gerbers_and_drill: true

  - name: Upload schematic
    uses: actions/upload-artifact@v4
    with:
      name: Schematic
      path: ./schematic.pdf

  - name: Upload gerbers and drill file
    uses: actions/upload-artifact@v4
    with:
      name: Gerbers
      path: ./gerbers
```

# 📥 Inputs

## `schematic_file_name`

Required: `False`\
\
Description: Location of the .kicad_sch file.

## `symbol_libraries`

Required: `False`\
\
Description: Comma-separated list of symbol libraries in the format name=path. The path should be relative to the `.kicad_pro` file.

## `run_erc`

Required: `False`\
Default: `False`\
\
Description: Run the ERC (Electrical Rules Check) on the schematic.

## `erc_output_file_name`

Required: `False`\
Default: `erc.rpt`\
\
Description: Output file name of ERC report.

## `schematic_output_pdf`

Required: `False`\
Default: `False`\
\
Description: Run the PDF export of the schematic.

## `schematic_output_pdf_file_name`

Required: `False`\
Default: `schematic.pdf`\
\
Description: Output file name of PDF schematic.

## `schematic_output_black_white`

Required: `False`\
Default: `False`\
\
Description: Run the PDF, SVG, DXF, and PS schematic export in black and white.

## `schematic_output_svg`

Required: `False`\
Default: `False`\
\
Description: Run the SVG export of the schematic.

## `schematic_output_svg_folder_name`

Required: `False`\
Default: `schematics`\
\
Description: Output folder name of SVG schematic.

## `schematic_output_dxf`

Required: `False`\
Default: `False`\
\
Description: Run the DXF export of the schematic.

## `schematic_output_dxf_folder_name`

Required: `False`\
Default: `schematics`\
\
Description: Output folder name of DXF schematic.

## `schematic_output_hpgl`

Required: `False`\
Default: `False`\
\
Description: Run the HPGL export of the schematic.

## `schematic_output_hpgl_folder_name`

Required: `False`\
Default: `schematics`\
\
Description: Output folder name of HPGL schematic.

## `schematic_output_ps`

Required: `False`\
Default: `False`\
\
Description: Run the PS export of the schematic.

## `schematic_output_ps_folder_name`

Required: `False`\
Default: `schematics`\
\
Description: Output folder name of PS schematic.

## `schematic_output_bom`

Required: `False`\
Default: `False`\
\
Description: Run the BOM (Bill of Materials) export of the schematic.

## `schematic_output_bom_file_name`

Required: `False`\
Default: `bom.csv`\
\
Description: Output file name of the BOM.

## `schematic_output_bom_fields`

Required: `False`\
Default: `Reference,Value,Footprint,${QUANTITY},${DNP}`\
\
Description: Output fields in the BOM file. `*` includes all fields.

## `schematic_output_bom_labels`

Required: `False`\
Default: `Refs,Value,Footprint,Qty,DNP`\
\
Description: Output labels in the BOM file.

## `schematic_output_netlist`

Required: `False`\
Default: `False`\
\
Description: Run the netlist export of the schematic.

## `schematic_output_netlist_file_name`

Required: `False`\
Default: `netlist.net`\
\
Description: Output file name of the netlist.

## `pcb_file_name`

Required: `False`\
\
Description: Location of the .kicad_pcb file.

## `footprint_libraries`

Required: `False`\
\
Description: Comma-separated list of footprint libraries in the format name=path. The path should be relative to the `.kicad_pro` file.

## `run_drc`

Required: `False`\
Default: `False`\
\
Description: Run the DRC (Design Rules Check) on the PCB.

## `drc_output_file_name`

Required: `False`\
Default: `drc.rpt`\
\
Description: Output file name of DRC report.

## `pcb_output_drill`

Required: `False`\
Default: `False`\
\
Description: Run the drill export of the PCB.

## `pcb_output_drill_folder_name`

Required: `False`\
Default: `drill`\
\
Description: Output folder name of drill file.

## `pcb_output_drill_format`

Required: `False`\
Default: `excellon`\
\
Description: Format of the drill file. Options:

- `excellon`
- `gerber`

## `pcb_output_gerbers`

Required: `False`\
Default: `False`\
\
Description: Run the gerber export of the PCB.

## `pcb_output_gerbers_folder_name`

Required: `False`\
Default: `gerbers`\
\
Description: Output folder name of gerber files.

## `pcb_output_layers`

Required: `False`\
\
Description: Output layers of the PCB.

## `pcb_output_gerbers_and_drill`

Required: `False`\
Default: `False`\
\
Description: Run the gerber and drill export of the PCB.

## `pcb_output_gerbers_and_drill_folder_name`

Required: `False`\
Default: `gerbers`\
\
Description: Output folder name of gerber and drill files.

## `pcb_output_dxf`

Required: `False`\
Default: `False`\
\
Description: Run the DXF export of the PCB.

## `pcb_output_dxf_folder_name`

Required: `False`\
Default: `dxf`\
\
Description: Output folder name of DXF PCB.

## `pcb_output_pdf`

Required: `False`\
Default: `False`\
\
Description: Run the PDF export of the PCB.

## `pcb_output_pdf_file_name`

Required: `False`\
Default: `pcb.pdf`\
\
Description: Output file name of PDF PCB.

## `pcb_output_black_white`

Required: `False`\
Default: `False`\
\
Description: Run the PDF and SVG PCB export in black and white.

## `pcb_output_svg`

Required: `False`\
Default: `False`\
\
Description: Run the SVG export of the PCB.

## `pcb_output_svg_file_name`

Required: `False`\
Default: `pcb.svg`\
\
Description: Output file name of SVG PCB.

## `pcb_output_pos`

Required: `False`\
Default: `False`\
\
Description: Run the POS export of the PCB.

## `pcb_output_pos_file_name`

Required: `False`\
Default: `pcb.pos`\
\
Description: Output file name of POS PCB.

## `pcb_output_pos_format`

Required: `False`\
Default: `ascii`\
\
Description: Format of the POS file. Options:

- `ascii`
- `csv`
- `gerber`

## `pcb_output_pos_side`

Required: `False`\
Default: `both`\
\
Description: Side of the POS file. Options:

- `front`
- `back`
- `both`

> **Note:** both is not supported by gerber.

## `pcb_output_ipc2581`

Required: `False`\
Default: `False`\
\
Description: Run the IPC-2581 export of the PCB.

## `pcb_output_ipc2581_file_name`

Required: `False`\
Default: `pcb.xml`\
\
Description: Output file name of IPC-2581 PCB.

## `pcb_output_step`

Required: `False`\
Default: `False`\
\
Description: Run the STEP export of the PCB.

## `pcb_output_step_file_name`

Required: `False`\
Default: `pcb.step`\
\
Description: Output file name of STEP PCB.

# 📤 Outputs

This action exports multiple files based on the inputs that are given.

# 📄 License

The scripts and documentation in this project are released under the [MIT license](LICENSE).

# 🧑‍💻 Contributions

Contributions are welcome! Please help me expand and maintain this repository.
