#!/bin/bash

set -e

mkdir -p $HOME/.config
cp -r /home/kicad/.config/kicad $HOME/.config/

erc_violation=0 # ERC exit code
drc_violation=0 # DRC exit code

# Check if the current version is the latest version
current_ref="${GITHUB_ACTION_REF:-unknown}"
current_version="${current_ref##*/}"  # remove refs/heads or refs/tags prefix

# Get latest tag from GitHub API
latest_tag=$(curl -s "https://api.github.com/repos/${GITHUB_ACTION_REPOSITORY}/releases/latest" | jq -r '.tag_name')

# Strip leading v and ignore suffix after '-'
strip_version() {
  echo "$1" | sed -E 's/^v//; s/-.*$//'
}

# Check if the latest tag is not empty
if [[ -n "$latest_tag" ]]; then
  latest_clean=$(strip_version "$latest_tag")
  current_clean=$(strip_version "$current_version")

  # Extract major.minor
  latest_major="${latest_clean%%.*}"
  latest_minor="${latest_clean#*.}"
  latest_minor="${latest_minor%%.*}"

  current_major="${current_clean%%.*}"
  current_minor="${current_clean#*.}"
  current_minor="${current_minor%%.*}"

  # Determine if current is floating major (like 'v1')
  is_floating_major=false
  if [[ "$current_version" =~ ^v[0-9]+$ ]]; then
    is_floating_major=true
  fi

  if $is_floating_major; then
    if [ "$current_major" != "$latest_major" ]; then
      echo "::warning::You are using version '$current_version', but the latest version is '$latest_major'. Consider updating."
    fi
  else
    if [ "$current_major" != "$latest_major" ] || [ "$current_minor" != "$latest_minor" ]; then
      echo "::warning::You are using version '$current_version', but the latest version is '$latest_tag'. Consider updating."
    fi
  fi
else
  echo "::warning::Could not fetch the latest version from GitHub API. It is unknown if the version that is currently used is the latest version."
fi

# Check if KiCad is installed
if ! command -v kicad-cli &> /dev/null; then
    echo "::error::KiCad is not installed."
    exit 1
fi

# Check if KiCad version is 8.0 or higher
kicad_version=$(kicad-cli --version | grep -oP '\d+\.\d+')
required_version="8.0"
config_dir="$HOME/.config/kicad/$kicad_version"
symbol_lib_path="$config_dir/sym-lib-table"
footprint_lib_path="$config_dir/fp-lib-table"

if [ "$(printf '%s\n' "$required_version" "$kicad_version" | sort -V | head -n1)" != "$required_version" ]; then
    echo "::error::KiCad version 8.0 or higher is required."
    exit 1
fi

# Define functions for input libraries
# Function to add symbol library
add_symbol_lib() {
  local name="$1"
  local path="$2"
  local entry="  (lib (name \"$name\")(type \"KiCad\")(uri \"$GITHUB_WORKSPACE/$path\")(options \"\")(descr \"\"))"

  # Create file if it doesn't exist
  if [ ! -f "$symbol_lib_path" ]; then
    echo -e "(sym_lib_table\n)" > "$symbol_lib_path"
    echo "Created new sym-lib-table at $symbol_lib_path"
  fi

  # Check if the library already exists
  if grep -q "(name \"$name\")" "$symbol_lib_path"; then
    echo "Symbol library '$name' already exists in sym-lib-table."
  else
    # Insert the new entry before the last line (closing parenthesis)
    sed -i.bak "\$ i\\
$entry
" "$symbol_lib_path"
    echo "Symbol library '$name' added to sym-lib-table."
  fi
}

# Function to add footprint library
add_footprint_lib() {
  local name="$1"
  local path="$2"
  local entry="  (lib (name \"$name\")(type \"KiCad\")(uri \"$GITHUB_WORKSPACE/$path\")(options \"\")(descr \"\"))"

  # Create file if it doesn't exist
  if [ ! -f "$footprint_lib_path" ]; then
    echo -e "(fp_lib_table\n)" > "$footprint_lib_path"
    echo "Created new fp-lib-table at $footprint_lib_path"
  fi

  # Check if the library already exists
  if grep -q "(name $name)" "$footprint_lib_path"; then
    echo "Footprint library '$name' already exists in fp-lib-table."
  else
    # Insert the new entry before the last line (closing parenthesis)
    sed -i.bak "\$ i\\
$entry
" "$footprint_lib_path"
    echo "Symbol library '$name' added to fp-lib-table."
  fi
}

# Check if any schematic output/erc are selected without the file being present
if [[ -z $INPUT_SCHEMATIC_FILE_NAME && (
    $INPUT_RUN_ERC == "true" || 
    $INPUT_SCHEMATIC_OUTPUT_PDF == "true" || 
    $INPUT_SCHEMATIC_OUTPUT_SVG == "true" || 
    $INPUT_SCHEMATIC_OUTPUT_BOM == "true" || 
    $INPUT_SCHEMATIC_OUTPUT_NETLIST == "true" )
]]; then
    echo "::error::Schematic output/ERC options selected without a schematic file."
    exit 1
fi

# Check if any PCB output/drc are selected without the file being present
if [[ -z $INPUT_PCB_FILE_NAME && (
    $INPUT_PCB_OUTPUT_DRILL == "true" )
]]; then
    echo "::error::PCB output/DRC options selected without a PCB file."
    exit 1
fi

# Check if footprint library is set
if [[ -n $INPUT_SYMBOL_LIBRARIES ]]; then
    # Parse symbol libraries
    declare -A symbol_libraries
    IFS=',' read -ra symbol_pairs <<< "$INPUT_SYMBOL_LIBRARIES"
    for pair in "${symbol_pairs[@]}"; do
      name="${pair%%=*}"
      path="${pair#*=}"
      symbol_libraries["$name"]="$path"
    done

    # Loop through and add all symbol libraries
    for name in "${!symbol_libraries[@]}"; do
      add_symbol_lib "$name" "${symbol_libraries[$name]}"
    done
fi

# Check if footprint library is set
if [[ -n $INPUT_FOOTPRINT_LIBRARIES ]]; then
    # Parse footprint libraries
    declare -A footprint_libraries
    IFS=',' read -ra footprint_pairs <<< "$INPUT_FOOTPRINT_LIBRARIES"
    for pair in "${footprint_pairs[@]}"; do
      name="${pair%%=*}"
      path="${pair#*=}"
      footprint_libraries["$name"]="$path"
    done

    # Loop through and add all footprint libraries
    for name in "${!footprint_libraries[@]}"; do
      add_footprint_lib "$name" "${footprint_libraries[$name]}"
    done
fi

# Run schematic outputs
if [[ -n $INPUT_SCHEMATIC_FILE_NAME ]]; then

  # Run ERC
  if [[ $INPUT_RUN_ERC == "true" ]]; then
    kicad-cli sch erc \
      --output "$INPUT_ERC_OUTPUT_FILE_NAME" \
      --exit-code-violations \
      "$INPUT_SCHEMATIC_FILE_NAME"
    erc_violation=$?
  fi

  # Export schematic to PDF
  if [[ $INPUT_SCHEMATIC_OUTPUT_PDF == "true" ]]; then
    cmd=(kicad-cli sch export pdf --output "$INPUT_SCHEMATIC_OUTPUT_PDF_FILE_NAME")
    [[ $INPUT_SCHEMATIC_OUTPUT_BLACK_WHITE == "true" ]] && cmd+=(--black-and-white)
    "${cmd[@]}" "$INPUT_SCHEMATIC_FILE_NAME"
  fi

  # Export schematic to SVG
  if [[ $INPUT_SCHEMATIC_OUTPUT_SVG == "true" ]]; then
    cmd=(kicad-cli sch export svg --output "$INPUT_SCHEMATIC_OUTPUT_SVG_FOLDER_NAME")
    [[ $INPUT_SCHEMATIC_OUTPUT_BLACK_WHITE == "true" ]] && cmd+=(--black-and-white)
    "${cmd[@]}" "$INPUT_SCHEMATIC_FILE_NAME"
  fi

  # Export schematic to DXF
  if [[ $INPUT_SCHEMATIC_OUTPUT_DXF == "true" ]]; then
    cmd=(kicad-cli sch export dxf --output "$INPUT_SCHEMATIC_OUTPUT_DXF_FOLDER_NAME")
    [[ $INPUT_SCHEMATIC_OUTPUT_BLACK_WHITE == "true" ]] && cmd+=(--black-and-white)
    "${cmd[@]}" "$INPUT_SCHEMATIC_FILE_NAME"
  fi

  # Export schematic to HPGL
  if [[ $INPUT_SCHEMATIC_OUTPUT_HPGL == "true" ]]; then
    cmd=(kicad-cli sch export hpgl --output "$INPUT_SCHEMATIC_OUTPUT_HPGL_FOLDER_NAME")
    [[ $INPUT_SCHEMATIC_OUTPUT_BLACK_WHITE == "true" ]] && cmd+=(--black-and-white)
    "${cmd[@]}" "$INPUT_SCHEMATIC_FILE_NAME"
  fi

  # Export schematic to PS
  if [[ $INPUT_SCHEMATIC_OUTPUT_PS == "true" ]]; then
    cmd=(kicad-cli sch export ps --output "$INPUT_SCHEMATIC_OUTPUT_PS_FOLDER_NAME")
    [[ $INPUT_SCHEMATIC_OUTPUT_BLACK_WHITE == "true" ]] && cmd+=(--black-and-white)
    "${cmd[@]}" "$INPUT_SCHEMATIC_FILE_NAME"
  fi

  # Export schematic BOM
  if [[ $INPUT_SCHEMATIC_OUTPUT_BOM == "true" ]]; then
    kicad-cli sch export bom \
      --output "$INPUT_SCHEMATIC_OUTPUT_BOM_FILE_NAME" \
      --fields "$INPUT_SCHEMATIC_OUTPUT_BOM_FIELDS" \
      --labels "$INPUT_SCHEMATIC_OUTPUT_BOM_LABELS" \
      "$INPUT_SCHEMATIC_FILE_NAME"
  fi

  # Export schematic netlist
  if [[ $INPUT_SCHEMATIC_OUTPUT_NETLIST == "true" ]]; then
    kicad-cli sch export netlist \
      --output "$INPUT_SCHEMATIC_OUTPUT_NETLIST_FILE_NAME" \
      "$INPUT_SCHEMATIC_FILE_NAME"
  fi
fi

# Run PCB outputs
if [[ -n $INPUT_PCB_FILE_NAME ]]; then

  # Run DRC
  if [[ $INPUT_RUN_DRC == "true" ]]; then
    kicad-cli pcb drc \
      --output "$INPUT_DRC_OUTPUT_FILE_NAME" \
      --exit-code-violations \
      "$INPUT_PCB_FILE_NAME"
    drc_violation=$?
  fi

  # Export PCB drill
  if [[ $INPUT_PCB_OUTPUT_DRILL == "true" ]]; then
    if [[ $INPUT_PCB_OUTPUT_DRILL_FORMAT != "excellon" && $INPUT_PCB_OUTPUT_DRILL_FORMAT != "gerber" ]]; then
      echo "::error::Invalid drill format. Supported formats are 'excellon' and 'gerber'."
      exit 1
    fi

    kicad-cli pcb export drill \
      --output "$INPUT_PCB_OUTPUT_DRILL_FOLDER_NAME" \
      --format "$INPUT_PCB_OUTPUT_DRILL_FORMAT" \
      "$INPUT_PCB_FILE_NAME"
  fi

  # Export PCB gerbers
  if [[ $INPUT_PCB_OUTPUT_GERBERS == "true" ]]; then
    cmd=(kicad-cli pcb export gerbers --output "$INPUT_PCB_OUTPUT_GERBERS_FOLDER_NAME")
    [[ -n $INPUT_PCB_OUTPUT_LAYERS ]] && cmd+=(--layers "$INPUT_PCB_OUTPUT_LAYERS")
    "${cmd[@]}" "$INPUT_PCB_FILE_NAME"
  fi

  # Export PCB gerbers and drill
  if [[ $INPUT_PCB_OUTPUT_GERBERS_AND_DRILL == "true" ]]; then
    cmd=(kicad-cli pcb export gerbers --output "$INPUT_PCB_OUTPUT_GERBERS_AND_DRILL_FOLDER_NAME")
    [[ -n $INPUT_PCB_OUTPUT_LAYERS ]] && cmd+=(--layers "$INPUT_PCB_OUTPUT_LAYERS")
    "${cmd[@]}" "$INPUT_PCB_FILE_NAME"

    kicad-cli pcb export drill \
      --output "$INPUT_PCB_OUTPUT_GERBERS_AND_DRILL_FOLDER_NAME" \
      --format "$INPUT_PCB_OUTPUT_DRILL_FORMAT" \
      "$INPUT_PCB_FILE_NAME"
  fi

  # Export PCB DXF
  if [[ $INPUT_PCB_OUTPUT_DXF == "true" ]]; then
    if [[ -z $INPUT_PCB_OUTPUT_LAYERS ]]; then
      echo "::error::No layers set for PCB DXF output."
      exit 1
    fi

    kicad-cli pcb export dxf \
      --output "$INPUT_PCB_OUTPUT_DXF_FOLDER_NAME" \
      --layers "$INPUT_PCB_OUTPUT_LAYERS" \
      "$INPUT_PCB_FILE_NAME"
  fi

  # Export PCB PDF
  if [[ $INPUT_PCB_OUTPUT_PDF == "true" ]]; then
    if [[ -z $INPUT_PCB_OUTPUT_LAYERS ]]; then
      echo "::error::No layers set for PCB PDF output."
      exit 1
    fi

    cmd=(kicad-cli pcb export pdf --output "$INPUT_PCB_OUTPUT_PDF_FILE_NAME" --layers "$INPUT_PCB_OUTPUT_LAYERS")
    [[ $INPUT_PCB_OUTPUT_BLACK_WHITE == "true" ]] && cmd+=(--black-and-white)
    "${cmd[@]}" "$INPUT_PCB_FILE_NAME"
  fi

  # Export PCB SVG
  if [[ $INPUT_PCB_OUTPUT_SVG == "true" ]]; then
    if [[ -z $INPUT_PCB_OUTPUT_LAYERS ]]; then
      echo "::error::No layers set for PCB SVG output."
      exit 1
    fi

    cmd=(kicad-cli pcb export svg --output "$INPUT_PCB_OUTPUT_SVG_FILE_NAME" --layers "$INPUT_PCB_OUTPUT_LAYERS")
    [[ $INPUT_PCB_OUTPUT_BLACK_WHITE == "true" ]] && cmd+=(--black-and-white)
    "${cmd[@]}" "$INPUT_PCB_FILE_NAME"
  fi

  # Export PCB POS
  if [[ $INPUT_PCB_OUTPUT_POS == "true" ]]; then
    if [[ $INPUT_PCB_OUTPUT_POS_FORMAT != "ascii" && $INPUT_PCB_OUTPUT_POS_FORMAT != "csv" && $INPUT_PCB_OUTPUT_POS_FORMAT != "gerber" ]]; then
      echo "::error::Invalid POS format. Supported formats are 'ascii', 'csv' and 'gerber'."
      exit 1
    fi

    if [[ $INPUT_PCB_OUTPUT_POS_SIDE != "both" && $INPUT_PCB_OUTPUT_POS_SIDE != "front" && $INPUT_PCB_OUTPUT_POS_SIDE != "back" ]]; then
      echo "::error::Invalid POS side. Supported sides are 'both', 'front' and 'back'."
      exit 1
    fi

    kicad-cli pcb export pos \
      --output "$INPUT_PCB_OUTPUT_POS_FILE_NAME" \
      --format "$INPUT_PCB_OUTPUT_POS_FORMAT" \
      --side "$INPUT_PCB_OUTPUT_POS_SIDE" \
      "$INPUT_PCB_FILE_NAME"
  fi

  # Export PCB IPC-2581
  if [[ $INPUT_PCB_OUTPUT_IPC2581 == "true" ]]; then
    kicad-cli pcb export ipc2581 \
      --output "$INPUT_PCB_OUTPUT_IPC2581_FILE_NAME" \
      "$INPUT_PCB_FILE_NAME"
  fi

  # Export PCB STEP
  if [[ $INPUT_PCB_OUTPUT_STEP == "true" ]]; then
    kicad-cli pcb export step \
      --output "$INPUT_PCB_OUTPUT_STEP_FILE_NAME" \
      "$INPUT_PCB_FILE_NAME"
  fi
fi

# Return non-zero exit code for ERC or DRC violations
if [[ $erc_violation -gt 0 ]] || [[ $drc_violation -gt 0 ]]; then
  exit 1
else
  exit 0
fi
