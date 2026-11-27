#!/usr/bin/env bash
# Builds the place, runs all checks and puts the deliverables into dist/
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(grep -o 'Config.Version = "[^"]*"' src/ReplicatedStorage/Shared/Config.lua | cut -d'"' -f2)
echo "== Syntax check (Luau compiler)"
lune run tools/check.luau src
echo "== Build place"
lune run tools/build_place.luau build
echo "== Server simulation"
lune run tools/test/server_test.luau | tail -n 3
echo "== Lab / creatures / theft / arena simulation (multiplayer)"
lune run tools/test/lab_test.luau | tail -n 2
echo "== Client UI simulation"
lune run tools/test/client_test.luau | tail -n 2
echo "== Package"
mkdir -p dist dist/backup
cp build/RestaurantIslandTycoon.rbxl dist/RestaurantIslandTycoon.rbxl
rm -f dist/RestaurantIslandTycoon.rbxlx.zip
(cd build && zip -q -9 ../dist/RestaurantIslandTycoon.rbxlx.zip RestaurantIslandTycoon.rbxlx)
cp build/RestaurantIslandTycoon.rbxl "dist/backup/RestaurantIslandTycoon_v${VERSION}_backup.rbxl"
rm -f "dist/backup/RestaurantIslandTycoon_v${VERSION}_source.zip"
zip -q -r -9 "dist/backup/RestaurantIslandTycoon_v${VERSION}_source.zip" src tools docs default.project.json README.md
ls -la dist dist/backup
