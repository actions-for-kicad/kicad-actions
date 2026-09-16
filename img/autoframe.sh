#!/bin/bash
# Sourced by entrypoint.sh at the end of the PCB image block. Expects the
# INPUT_PCB_OUTPUT_IMAGE_* variables and inherits 'set -e' from the caller.
#
# The guard for "image output selected without autoframing" lives here rather
# than in entrypoint.sh's own condition, so this feature adds one sourced line
# there instead of growing an existing one.

if [[ $INPUT_PCB_OUTPUT_IMAGE_AUTOFRAME == "true" ]]; then
  if [[ ! $INPUT_PCB_OUTPUT_IMAGE_FILE_NAME =~ \.png$ ]]; then
    echo "::warning::pcb_output_image_autoframe needs an alpha channel and only PNG carries one, so '$INPUT_PCB_OUTPUT_IMAGE_FILE_NAME' is left as rendered."
  elif [[ $INPUT_PCB_OUTPUT_IMAGE_BACKGROUND == "opaque" ]]; then
    # 'default' is transparent for PNG, so only an explicit 'opaque' is wrong.
    echo "::warning::pcb_output_image_autoframe needs a transparent background to find the board, but pcb_output_image_background is 'opaque'. Leaving '$INPUT_PCB_OUTPUT_IMAGE_FILE_NAME' as rendered."
  elif ! [[ $INPUT_PCB_OUTPUT_IMAGE_AUTOFRAME_MARGIN =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "::error::Invalid image autoframe margin '$INPUT_PCB_OUTPUT_IMAGE_AUTOFRAME_MARGIN'. Use a non-negative number, for example 0.04."
    exit 1
  elif ! command -v python3 &> /dev/null; then
    echo "::warning::python3 not found; skipping image autoframing."
  else
    python3 /img/autoframe.py "$INPUT_PCB_OUTPUT_IMAGE_FILE_NAME" \
      --margin "$INPUT_PCB_OUTPUT_IMAGE_AUTOFRAME_MARGIN"
  fi
fi
