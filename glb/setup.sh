#!/bin/bash
# Sourced by entrypoint.sh. Expects $major_version to be set.
#
# KiCad only defines the 3D model path variable for its own major version, but
# boards authored in an older release reference the older name, for example
# '${KICAD8_3DMODEL_DIR}/LED_THT.3dshapes/...'. kicad-cli does not migrate
# those the way the GUI does, so every such component is silently dropped from
# 3D exports. Point the legacy names at the same directory.
model_dir_var="KICAD${major_version}_3DMODEL_DIR"
model_dir="${!model_dir_var:-/usr/share/kicad/3dmodels}"
export "$model_dir_var=$model_dir"
for legacy_version in 6 7 8 9 10 11; do
  legacy_var="KICAD${legacy_version}_3DMODEL_DIR"
  if [[ -z ${!legacy_var} ]]; then
    export "$legacy_var=$model_dir"
  fi
done

# The upstream guard for "PCB output selected without a PCB file" lives in a
# single condition in entrypoint.sh that gains a line with every new output.
# Checking here instead keeps this feature from editing that line.
if [[ -z $INPUT_PCB_FILE_NAME && $INPUT_PCB_OUTPUT_GLB == "true" ]]; then
    echo "::error::PCB output/DRC options selected without a PCB file."
    exit 1
fi
