#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_root="${script_dir:h}"
output_root="${project_root}/.build/release-app"
app_bundle="${output_root}/Codex 额度精灵岛.app"

cd "${project_root}"
swift build -c release
rm -rf "${app_bundle}"
mkdir -p "${app_bundle}/Contents/MacOS" "${app_bundle}/Contents/Resources"
cp ".build/release/CodexQuotaIsland" "${app_bundle}/Contents/MacOS/CodexQuotaIsland"
cp "Resources/Info.plist" "${app_bundle}/Contents/Info.plist"
codesign --force --sign - --timestamp=none "${app_bundle}"
print "Built: ${app_bundle}"
