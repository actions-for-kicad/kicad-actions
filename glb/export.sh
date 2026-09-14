#!/bin/bash
# Sourced by entrypoint.sh inside the PCB output block. Expects the
# INPUT_PCB_OUTPUT_GLB_* variables, $model_dir and $model_dir_var, and
# inherits 'set -e' from the caller.

if [[ $INPUT_PCB_OUTPUT_GLB == "true" ]]; then
  if [[ ! $INPUT_PCB_OUTPUT_GLB_FILE_NAME =~ \.glb$ ]]; then
    echo "::error::Invalid GLB file name. Make sure your GLB file name ends with '.glb'."
    exit 1
  fi

  # The second pattern rejects an all-zero value: it parses as a number but
  # writes "scale": [0,0,0], which collapses the model to a point.
  if ! [[ $INPUT_PCB_OUTPUT_GLB_SCALE =~ ^[0-9]+(\.[0-9]+)?$ ]] ||
     [[ $INPUT_PCB_OUTPUT_GLB_SCALE =~ ^0+(\.0+)?$ ]]; then
    echo "::error::Invalid GLB scale. Make sure your GLB scale is a valid positive number."
    exit 1
  fi

  # Zero would make the mask invisible; above one is not an opacity.
  if [[ -n $INPUT_PCB_OUTPUT_GLB_MASK_OPACITY ]] &&
     { ! [[ $INPUT_PCB_OUTPUT_GLB_MASK_OPACITY =~ ^(0(\.[0-9]+)?|1(\.0+)?)$ ]] ||
       [[ $INPUT_PCB_OUTPUT_GLB_MASK_OPACITY =~ ^0+(\.0+)?$ ]]; }; then
    echo "::error::Invalid GLB mask opacity '$INPUT_PCB_OUTPUT_GLB_MASK_OPACITY'. Use a number above 0 and up to 1, for example 0.83."
    exit 1
  fi

  # A translucent mask with nothing exported under it looks the same as an
  # opaque one, which is easy to mistake for the option not working.
  if [[ -n $INPUT_PCB_OUTPUT_GLB_MASK_OPACITY && $INPUT_PCB_OUTPUT_GLB_MASK_OPACITY != 1* &&
        $INPUT_PCB_OUTPUT_GLB_TRACKS != "true" && $INPUT_PCB_OUTPUT_GLB_ZONES != "true" ]]; then
    echo "::warning::pcb_output_glb_mask_opacity is below 1 but neither pcb_output_glb_tracks nor pcb_output_glb_zones is enabled, so there is no copper under the mask to show through."
  fi

  if [[ $INPUT_PCB_OUTPUT_GLB_COMPONENTS == "true" &&
        $INPUT_PCB_OUTPUT_GLB_BOARD_ONLY != "true" && ! -d $model_dir ]]; then
    echo "::warning::3D model directory '$model_dir' does not exist, so components using the standard KiCad 3D libraries will be missing from the GLB. Commit the models to your repository, or set $model_dir_var to where they live."
  fi

  cmd=(kicad-cli pcb export glb --force --output "$INPUT_PCB_OUTPUT_GLB_FILE_NAME")

  # Visual content. Copper that sits under the soldermask contributes nothing
  # once the mask is opaque, so tracks, zones and inner layers stay off unless
  # asked for. Pads are the copper that shows through the mask openings.
  [[ $INPUT_PCB_OUTPUT_GLB_SOLDERMASK == "true" ]] && cmd+=(--include-soldermask)
  [[ $INPUT_PCB_OUTPUT_GLB_SILKSCREEN == "true" ]] && cmd+=(--include-silkscreen)
  [[ $INPUT_PCB_OUTPUT_GLB_PADS == "true" ]] && cmd+=(--include-pads)
  [[ $INPUT_PCB_OUTPUT_GLB_TRACKS == "true" ]] && cmd+=(--include-tracks)
  [[ $INPUT_PCB_OUTPUT_GLB_ZONES == "true" ]] && cmd+=(--include-zones)
  [[ $INPUT_PCB_OUTPUT_GLB_INNER_COPPER == "true" ]] && cmd+=(--include-inner-copper)

  # With no conductor layers exported, via barrels are not generated, so the
  # holes have to be cut into the board body explicitly or the board looks
  # solid where the vias should be.
  if [[ $INPUT_PCB_OUTPUT_GLB_TRACKS != "true" && $INPUT_PCB_OUTPUT_GLB_ZONES != "true" ]]; then
    cmd+=(--cut-vias-in-body)
  fi

  [[ $INPUT_PCB_OUTPUT_GLB_COMPONENTS != "true" ]] && cmd+=(--no-components)
  [[ $INPUT_PCB_OUTPUT_GLB_BOARD_ONLY == "true" ]] && cmd+=(--board-only)
  [[ $INPUT_PCB_OUTPUT_GLB_NO_DNP == "true" ]] && cmd+=(--no-dnp)
  [[ $INPUT_PCB_OUTPUT_GLB_NO_UNSPECIFIED == "true" ]] && cmd+=(--no-unspecified)
  [[ $INPUT_PCB_OUTPUT_GLB_SUBST_MODELS == "true" ]] && cmd+=(--subst-models)
  [[ $INPUT_PCB_OUTPUT_GLB_FUSE_SHAPES == "true" ]] && cmd+=(--fuse-shapes)
  [[ -n $INPUT_PCB_OUTPUT_GLB_COMPONENT_FILTER ]] && cmd+=(--component-filter "$INPUT_PCB_OUTPUT_GLB_COMPONENT_FILTER")
  [[ -n $INPUT_PCB_OUTPUT_GLB_NET_FILTER ]] && cmd+=(--net-filter "$INPUT_PCB_OUTPUT_GLB_NET_FILTER")
  [[ -n $INPUT_PCB_OUTPUT_GLB_MIN_DISTANCE ]] && cmd+=(--min-distance "$INPUT_PCB_OUTPUT_GLB_MIN_DISTANCE")

  # Anything not a named origin is passed through as an explicit offset, so it
  # has to be validated here: kicad-cli rejects a malformed one with exit code
  # 2, which the check below deliberately treats as success, leaving a
  # capitalised 'Board' or a typo to surface only as "was not created".
  case "$INPUT_PCB_OUTPUT_GLB_ORIGIN" in
    board) ;;
    grid) cmd+=(--grid-origin) ;;
    drill) cmd+=(--drill-origin) ;;
    *)
      if [[ ! $INPUT_PCB_OUTPUT_GLB_ORIGIN =~ ^-?[0-9]+(\.[0-9]+)?x-?[0-9]+(\.[0-9]+)?(mm|in)$ ]]; then
        echo "::error::Invalid GLB origin '$INPUT_PCB_OUTPUT_GLB_ORIGIN'. Supported origins are 'board', 'grid', 'drill', or an explicit offset such as '25.4x25.4mm'."
        exit 1
      fi
      cmd+=(--user-origin "$INPUT_PCB_OUTPUT_GLB_ORIGIN")
      ;;
  esac

  set +e
  "${cmd[@]}" "$INPUT_PCB_FILE_NAME"
  pcb_glb_failure=$?
  set -e
  # kicad-cli can return 2 on success for 3D exports, the same way the STEP
  # export does, so only fail if the code is neither 0 nor 2.
  if [[ $pcb_glb_failure -ne 0 && $pcb_glb_failure -ne 2 ]]; then
    echo "::error::Failed to export PCB GLB file. Exit code: $pcb_glb_failure"
    exit 1
  fi

  if [[ ! -f $INPUT_PCB_OUTPUT_GLB_FILE_NAME ]]; then
    echo "::error::GLB export reported success but '$INPUT_PCB_OUTPUT_GLB_FILE_NAME' was not created."
    exit 1
  fi

  # Post-process into something a real-time renderer can use directly.
  if [[ $INPUT_PCB_OUTPUT_GLB_OPTIMIZE == "true" ]]; then
    if ! command -v python3 &> /dev/null; then
      echo "::warning::python3 not found; skipping GLB post-processing. The exported GLB will use KiCad's CAD-oriented materials."
    else
      pp=(python3 /glb/postprocess.py "$INPUT_PCB_OUTPUT_GLB_FILE_NAME")
      [[ $INPUT_PCB_OUTPUT_GLB_CENTER == "true" ]] && pp+=(--center) || pp+=(--no-center)
      [[ $INPUT_PCB_OUTPUT_GLB_DETECT_METALS == "true" ]] && pp+=(--detect-metals) || pp+=(--no-detect-metals)
      [[ $INPUT_PCB_OUTPUT_GLB_KEEP_TRANSPARENCY == "true" ]] && pp+=(--keep-transparency)
      [[ -n $INPUT_PCB_OUTPUT_GLB_MASK_OPACITY ]] && pp+=(--mask-opacity "$INPUT_PCB_OUTPUT_GLB_MASK_OPACITY")
      [[ -n $INPUT_PCB_OUTPUT_GLB_SCALE ]] && pp+=(--scale "$INPUT_PCB_OUTPUT_GLB_SCALE")
      [[ -n $INPUT_PCB_OUTPUT_GLB_METAL_COLORS ]] && pp+=(--metal-colors "$INPUT_PCB_OUTPUT_GLB_METAL_COLORS")
      "${pp[@]}"
    fi
  fi
fi
