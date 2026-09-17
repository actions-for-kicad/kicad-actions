#!/bin/bash
# Sourced by entrypoint.sh at the end of the PCB image block, after
# autoframe.sh. Expects the INPUT_PCB_OUTPUT_IMAGE_* variables and inherits
# 'set -e' from the caller.
#
# kicad-cli renders to PNG and JPEG only, so WebP is a conversion of what it
# just wrote rather than a second render: one pass of the raytracer, two files
# out of it, guaranteed to be the same picture. Sourcing after autoframe.sh is
# what makes that true -- autoframing rewrites the PNG in place, so converting
# first would ship a WebP framed differently from its own PNG.
#
# The render is kept. The point is a web-sized asset *alongside* the PNG, not
# instead of it: the PNG is what archives, diffs and non-web consumers want.

if [[ $INPUT_PCB_OUTPUT_IMAGE_WEBP == "true" ]]; then
  webp_file_name=$INPUT_PCB_OUTPUT_IMAGE_WEBP_FILE_NAME
  # Default to the render's own name with the extension swapped, so the pair
  # stays matched without the caller having to name both files.
  [[ -z $webp_file_name ]] &&
    webp_file_name="${INPUT_PCB_OUTPUT_IMAGE_FILE_NAME%.*}.webp"

  if [[ ! $webp_file_name =~ \.webp$ ]]; then
    echo "::error::Invalid WebP file name '$webp_file_name'. Make sure your WebP file name ends with '.webp'."
    exit 1
  fi

  # 10# so a padded value like '082' is read as decimal rather than as a
  # malformed octal literal, which would fail inside the arithmetic instead of
  # here with a usable message.
  if ! [[ $INPUT_PCB_OUTPUT_IMAGE_WEBP_QUALITY =~ ^[0-9]{1,3}$ ]] ||
     (( 10#$INPUT_PCB_OUTPUT_IMAGE_WEBP_QUALITY > 100 )); then
    echo "::error::Invalid WebP quality '$INPUT_PCB_OUTPUT_IMAGE_WEBP_QUALITY'. Use an integer from 0 to 100, for example 82."
    exit 1
  fi

  if [[ ! -f $INPUT_PCB_OUTPUT_IMAGE_FILE_NAME ]]; then
    echo "::error::Image render '$INPUT_PCB_OUTPUT_IMAGE_FILE_NAME' was not created, so there is nothing to convert to WebP."
    exit 1
  fi

  # Unlike autoframing, which only improves a file that already exists, a
  # missing WebP is a missing artifact. Fail rather than warn.
  if ! command -v cwebp &> /dev/null; then
    echo "::error::cwebp not found, so '$webp_file_name' cannot be written. It ships in the 'webp' package, which this action's image installs; a custom base image needs it too."
    exit 1
  fi

  cmd=(cwebp -quiet)
  if [[ $INPUT_PCB_OUTPUT_IMAGE_WEBP_LOSSLESS == "true" ]]; then
    # -z is the lossless effort preset; 9 is the smallest file. A board render
    # is flat colour and sharp silkscreen, which lossless compresses far
    # better than it does a photograph, so the size penalty is modest.
    cmd+=(-lossless -z 9)
  else
    # Lossy colour, lossless alpha. 100 is cwebp's own default for -alpha_q
    # and is pinned here rather than inherited: a transparent render gets
    # composited over a page background, where a lossy alpha channel shows up
    # as a halo along the board edge.
    cmd+=(-q "$INPUT_PCB_OUTPUT_IMAGE_WEBP_QUALITY" -alpha_q 100)
  fi

  "${cmd[@]}" "$INPUT_PCB_OUTPUT_IMAGE_FILE_NAME" -o "$webp_file_name"

  if [[ ! -f $webp_file_name ]]; then
    echo "::error::WebP conversion reported success but '$webp_file_name' was not created."
    exit 1
  fi
fi
