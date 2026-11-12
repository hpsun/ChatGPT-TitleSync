#!/bin/bash
# Compile only. Never launches a monitor, editor, or AX request.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
output="${1:-$repo/macos}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
bash "$repo/shared/macos/build.sh" "$output"
clang -fobjc-arc -fblocks -c "$repo/shared/macos/RulesClient.m" -o "$output/RulesClient.o" -framework Foundation
swiftc "$repo/macos/ChatGPTWindowTitles.swift" "$output/RulesClient.o" -import-objc-header "$repo/shared/macos/RulesClient.h" -framework AppKit -framework ApplicationServices -o "$output/chatgpt-titlesync-swift"
clang -fobjc-arc -fblocks -framework Cocoa -framework ApplicationServices "$repo/macos/ChatGPTWindowTitles.m" "$repo/shared/macos/RulesClient.m" -o "$output/chatgpt-titlesync-objc"
printf '%s\n' "$output/chatgpt-titlesync-swift" "$output/chatgpt-titlesync-objc" "$output/chatgpt-titlesync-rules"
