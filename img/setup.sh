#!/bin/bash
# Sourced by entrypoint.sh, alongside glb/setup.sh and for the same reason.
#
# The upstream guard for "PCB output selected without a PCB file" is a single
# condition in entrypoint.sh that would gain a line for every output this fork
# adds. Checking here leaves that line upstream's.
#
# Silence is the trap being closed: without this, asking for a WebP with no PCB
# file skips the whole PCB block and the job goes green having produced nothing.

if [[ -z $INPUT_PCB_FILE_NAME && $INPUT_PCB_OUTPUT_WEBP == "true" ]]; then
    echo "::error::PCB output/DRC options selected without a PCB file."
    exit 1
fi
