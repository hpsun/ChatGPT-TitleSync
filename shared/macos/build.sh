#!/bin/sh
# Build only the shared Foundation/AppKit companion; never launch an editor.
# Usage: sh build.sh [OUTPUT_DIRECTORY]
set -eu
base=$(CDPATH= cd "$(dirname "$0")" && pwd)
out=${1:-$base}
mkdir -p "$out"
: "${CC:=clang}"
"$CC" -fobjc-arc -fmodules -Wall -Wextra -O2 \
  -framework Foundation -framework AppKit \
  "$base/TitleRules.m" -o "$out/chatgpt-titlesync-rules"
printf '%s\n' "$out/chatgpt-titlesync-rules"
