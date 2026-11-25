#!/usr/bin/env bash
# Bundles Caveat (handwriting) + Plus Jakarta Sans so the app and the notes
# pages look right with NO internet. Best-effort: if a download fails the app
# still works and google_fonts fetches the font on first online use.
set -u
D=assets/google_fonts
B=https://github.com/google/fonts/raw/main/ofl
grab() { # family-dir  url-file  OutPrefix
  curl -fsSL "$B/$1/$2" -o /tmp/font.ttf || { echo "skip $3"; return; }
  for w in ExtraLight Light Regular Medium SemiBold Bold ExtraBold; do cp /tmp/font.ttf "$D/$3-$w.ttf"; done
  echo "bundled $3"
}
grab caveat 'Caveat%5Bwght%5D.ttf' Caveat
grab plusjakartasans 'PlusJakartaSans%5Bwght%5D.ttf' PlusJakartaSans
