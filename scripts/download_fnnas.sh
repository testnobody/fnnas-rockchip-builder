#!/usr/bin/env bash
set -e

mkdir -p cache
cd cache

REPO="ophub/fnnas"
TAG="fnnas_base_image"

API="https://api.github.com/repos/$REPO/releases/tags/$TAG"
URL=$(curl -sL "$API" | jq -r '.assets[] | select(.name|endswith(".img.xz")) | .browser_download_url' | head -n1)

[ -z "$URL" ] && exit 1

curl -L -o fnnas.img.xz "$URL"
xz -d fnnas.img.xz
