#!/bin/bash
# Copies the room "clue scene" photos from stanze_indizzi/ into both app
# targets' asset catalogs, one imageset per RoomID case (see
# CrackTheCaseCore/Sources/CrackTheCaseCore/Model/Room.swift's `clueAsset`).
# Distinct imageset names from copy_room_covers.sh's ("<room>Clue" suffix)
# so the two don't collide in the same Assets.xcassets.
set -euo pipefail

SRC_DIR="stanze_indizzi"

# "source file base name (without ' indizio' + extension)":RoomID:extension
PAIRS=(
    "biblioteca:library:png"
    "aula magna:assemblyHall:png"
    "mensa:cafeteria:png"
    "palestra:gym:jpg"
    "dormitorio:dormitory:png"
    "info:computerLab:jpg"
    "scienze:scienceLab:jpg"
    "segreteria:secretaryOffice:jpg"
    "aula studio:studyHall:png"
)

for TARGET_DIR in "CrackTheCaseIos/Assets.xcassets" "CrackTheCase/Assets.xcassets"; do
    for PAIR in "${PAIRS[@]}"; do
        SRC_NAME="$(echo "$PAIR" | cut -d: -f1)"
        ROOM_ID="$(echo "$PAIR" | cut -d: -f2)"
        EXT="$(echo "$PAIR" | cut -d: -f3)"
        ASSET_NAME="${ROOM_ID}Clue"

        mkdir -p "${TARGET_DIR}/${ASSET_NAME}.imageset"
        cp "${SRC_DIR}/${SRC_NAME} indizio.${EXT}" "${TARGET_DIR}/${ASSET_NAME}.imageset/${ASSET_NAME}.${EXT}"
        cat << JSON > "${TARGET_DIR}/${ASSET_NAME}.imageset/Contents.json"
{
  "images" : [
    {
      "filename" : "${ASSET_NAME}.${EXT}",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
    done
done

echo "Room clue-photo imagesets created in both Assets.xcassets catalogs."
