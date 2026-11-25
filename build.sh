#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
bundle="$root/build/LinkRouter.app"
mkdir -p "$bundle/Contents/MacOS"
swiftc -parse-as-library "$root"/App/*.swift -o "$bundle/Contents/MacOS/LinkRouter"
cp "$root/Info.plist" "$bundle/Contents/Info.plist"
