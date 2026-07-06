#!/bin/bash
NAMES=("Blue" "Green" "Yellow" "Red" "Purple" "White")

mkdir -p CrackTheCaseIos/Assets.xcassets
mkdir -p CrackTheCase/Assets.xcassets

for i in {0..5}; do
    NAME=${NAMES[$i]}
    INDEX=$((i+1))
    
    # iOS
    mkdir -p "CrackTheCaseIos/Assets.xcassets/${NAME}.imageset"
    cp "immaginiPersonaggi/${INDEX}.png" "CrackTheCaseIos/Assets.xcassets/${NAME}.imageset/"
    cat << JSON > "CrackTheCaseIos/Assets.xcassets/${NAME}.imageset/Contents.json"
{
  "images" : [
    {
      "filename" : "${INDEX}.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

    # tvOS
    mkdir -p "CrackTheCase/Assets.xcassets/${NAME}.imageset"
    cp "immaginiPersonaggi/${INDEX}.png" "CrackTheCase/Assets.xcassets/${NAME}.imageset/"
    cat << JSON > "CrackTheCase/Assets.xcassets/${NAME}.imageset/Contents.json"
{
  "images" : [
    {
      "filename" : "${INDEX}.png",
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
