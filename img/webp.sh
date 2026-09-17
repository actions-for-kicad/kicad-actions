#!/bin/bash
# Sourced by entrypoint.sh inside the PCB output block, as an export in its own
# right rather than as part of the image one. Expects the INPUT_PCB_OUTPUT_WEBP_*
# variables and inherits 'set -e' from the caller.
#
# kicad-cli renders PNG and JPEG and nothing else, so this renders a PNG and
# converts it. The PNG is an intermediate, written outside the workspace and
# removed, so the export produces exactly one file the way every other
# pcb_output_* does.
#
# It carries its own side, size, framing and quality rather than borrowing the
# image export's. A web asset is usually not the picture you want archived --
# smaller, tighter cropped, often a different angle -- and tying the two
# together would mean neither can move without the other. Set both blocks to
# the same values and you get the same picture in both formats.

if [[ $INPUT_PCB_OUTPUT_WEBP == "true" ]]; then
  if [[ ! $INPUT_PCB_OUTPUT_WEBP_FILE_NAME =~ \.webp$ ]]; then
    echo "::error::Invalid WebP file name. Make sure your WebP file name ends with '.webp'."
    exit 1
  fi

  # The render settings are validated against the same kicad-cli flags, and in
  # the same order, as the image export validates its own.
  if [[ ! "$INPUT_PCB_OUTPUT_WEBP_SIDE" =~ ^(top|bottom|left|right|front|back)$ ]]; then
    echo "::error::Invalid WebP side. Supported sides are 'top', 'bottom', 'left', 'right', 'front' or 'back'."
    exit 1
  fi

  if [[ ! "$INPUT_PCB_OUTPUT_WEBP_BACKGROUND" =~ ^(default|transparent|opaque)$ ]]; then
    echo "::error::Invalid WebP background. Supported backgrounds are 'default', 'transparent' or 'opaque'."
    exit 1
  fi

  if ! [[ $INPUT_PCB_OUTPUT_WEBP_WIDTH =~ ^[0-9]+$ ]]; then
    echo "::error::Invalid WebP width. Make sure your WebP width is a valid integer."
    exit 1
  fi
  if ! [[ $INPUT_PCB_OUTPUT_WEBP_HEIGHT =~ ^[0-9]+$ ]]; then
    echo "::error::Invalid WebP height. Make sure your WebP height is a valid integer."
    exit 1
  fi

  if [[ ! "$INPUT_PCB_OUTPUT_WEBP_QUALITY" =~ ^(basic|high|user)$ ]]; then
    echo "::error::Invalid WebP render quality. Supported qualities are 'basic', 'high' or 'user'. To set the encoder's quality, use 'pcb_output_webp_encode_quality'."
    exit 1
  fi

  if ! [[ $INPUT_PCB_OUTPUT_WEBP_ZOOM =~ ^[0-9]+(\.[0-9]+)$ ]]; then
    echo "::error::Invalid WebP zoom. Make sure your WebP zoom is a valid float."
    exit 1
  fi

  if ! [[ $INPUT_PCB_OUTPUT_WEBP_ROTATE =~ ^[0-9]+(\,[0-9]+){2}$ ]]; then
    echo "::error::Invalid WebP rotate. Make sure your WebP rotate is in the format 'x,y,z' with valid integers."
    exit 1
  fi

  # 10# so a padded value like '082' is read as decimal rather than as a
  # malformed octal literal, which would fail inside the arithmetic instead of
  # here with a usable message.
  if ! [[ $INPUT_PCB_OUTPUT_WEBP_ENCODE_QUALITY =~ ^[0-9]{1,3}$ ]] ||
     (( 10#$INPUT_PCB_OUTPUT_WEBP_ENCODE_QUALITY > 100 )); then
    echo "::error::Invalid WebP encode quality '$INPUT_PCB_OUTPUT_WEBP_ENCODE_QUALITY'. Use an integer from 0 to 100, for example 82."
    exit 1
  fi

  # Checked before the render rather than after, so a typo does not cost a
  # minute of raytracing to discover.
  if ! command -v cwebp &> /dev/null; then
    echo "::error::cwebp not found, so '$INPUT_PCB_OUTPUT_WEBP_FILE_NAME' cannot be written. It ships in the 'webp' package, which this action's image installs; a custom base image needs it too."
    exit 1
  fi

  # Outside the workspace: an intermediate that a later 'upload-artifact' step
  # could glob up is not an intermediate.
  webp_render_dir=$(mktemp -d)
  webp_render="$webp_render_dir/render.png"

  cmd=(kicad-cli pcb render \
    --output "$webp_render" \
    --side "$INPUT_PCB_OUTPUT_WEBP_SIDE" \
    --background "$INPUT_PCB_OUTPUT_WEBP_BACKGROUND" \
    --width "$INPUT_PCB_OUTPUT_WEBP_WIDTH" \
    --height "$INPUT_PCB_OUTPUT_WEBP_HEIGHT" \
    --quality "$INPUT_PCB_OUTPUT_WEBP_QUALITY" \
    --zoom "$INPUT_PCB_OUTPUT_WEBP_ZOOM" \
    --rotate "$INPUT_PCB_OUTPUT_WEBP_ROTATE" \
  )
  [[ $INPUT_PCB_OUTPUT_WEBP_PERSPECTIVE == "true" ]] && cmd+=(--perspective)
  [[ $INPUT_PCB_OUTPUT_WEBP_FLOOR == "true" ]] && cmd+=(--floor)
  "${cmd[@]}" "$INPUT_PCB_FILE_NAME"

  if [[ ! -f $webp_render ]]; then
    echo "::error::The render for '$INPUT_PCB_OUTPUT_WEBP_FILE_NAME' reported success but produced no file."
    exit 1
  fi

  # Cropping happens on the PNG, where the alpha channel says where the board
  # is. The same guards as the image export's autoframing, minus the "is it a
  # PNG" one -- here it always is.
  if [[ $INPUT_PCB_OUTPUT_WEBP_AUTOFRAME == "true" ]]; then
    if [[ $INPUT_PCB_OUTPUT_WEBP_BACKGROUND == "opaque" ]]; then
      echo "::warning::pcb_output_webp_autoframe needs a transparent background to find the board, but pcb_output_webp_background is 'opaque'. Leaving '$INPUT_PCB_OUTPUT_WEBP_FILE_NAME' as rendered."
    elif ! [[ $INPUT_PCB_OUTPUT_WEBP_AUTOFRAME_MARGIN =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      echo "::error::Invalid WebP autoframe margin '$INPUT_PCB_OUTPUT_WEBP_AUTOFRAME_MARGIN'. Use a non-negative number, for example 0.04."
      exit 1
    elif ! command -v python3 &> /dev/null; then
      echo "::warning::python3 not found; skipping WebP autoframing."
    else
      python3 /img/autoframe.py "$webp_render" \
        --margin "$INPUT_PCB_OUTPUT_WEBP_AUTOFRAME_MARGIN"
    fi
  fi

  conv=(cwebp -quiet)
  if [[ $INPUT_PCB_OUTPUT_WEBP_LOSSLESS == "true" ]]; then
    # -z is the lossless effort preset; 9 is the smallest file. A board render
    # is flat colour and sharp silkscreen, which lossless compresses far better
    # than it does a photograph, so the size penalty is modest.
    conv+=(-lossless -z 9)
  else
    # Lossy colour, lossless alpha. 100 is cwebp's own default for -alpha_q and
    # is pinned here rather than inherited: a transparent render gets
    # composited over a page background, where a lossy alpha channel shows up
    # as a halo along the board edge.
    conv+=(-q "$INPUT_PCB_OUTPUT_WEBP_ENCODE_QUALITY" -alpha_q 100)
  fi

  "${conv[@]}" "$webp_render" -o "$INPUT_PCB_OUTPUT_WEBP_FILE_NAME"
  rm -rf "$webp_render_dir"

  if [[ ! -f $INPUT_PCB_OUTPUT_WEBP_FILE_NAME ]]; then
    echo "::error::WebP conversion reported success but '$INPUT_PCB_OUTPUT_WEBP_FILE_NAME' was not created."
    exit 1
  fi
fi
