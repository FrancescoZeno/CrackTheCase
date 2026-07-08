#!/bin/bash
# Copies the chosen room cover photos from stanze_copertina_scelte/ into
# both app targets' asset catalogs, one imageset per RoomID case (see
# CrackTheCaseCore/Sources/CrackTheCaseCore/Model/Room.swift's `coverAsset`).
# Mirrors the pattern `copy_assets.sh` uses for the suspect/avatar art.
set -euo pipefail

SRC_DIR="stanze_copertina_scelte"

# sourceFileBaseName:RoomID pairs.
PAIRS=(
    "biblioteca:library"
    "aula magna:assemblyHall"
    "mensa:cafeteria"
    "palestra:gym"
    "dormitorio:dormitory"
    "info:computerLab"
    "scienze:scienceLab"
    "segreteria:secretaryOffice"
    "aula studio:studyHall"
)

for TARGET_DIR in "CrackTheCaseIos/Assets.xcassets" "CrackTheCase/Assets.xcassets"; do
    for PAIR in "${PAIRS[@]}"; do
        SRC_NAME="${PAIR%%:*}"
        ROOM_ID="${PAIR##*:}"

        mkdir -p "${TARGET_DIR}/${ROOM_ID}.imageset"
        cp "${SRC_DIR}/${SRC_NAME}.jpg" "${TARGET_DIR}/${ROOM_ID}.imageset/${ROOM_ID}.jpg"
        cat << JSON > "${TARGET_DIR}/${ROOM_ID}.imageset/Contents.json"
{
  "images" : [
    {
      "filename" : "${ROOM_ID}.jpg",
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

echo "Room cover imagesets created in both Assets.xcassets catalogs."
