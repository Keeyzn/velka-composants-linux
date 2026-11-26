#!/bin/bash
# Archive des sources exactes de la libmpv LGPL pour Linux, jointe à chaque Release (LGPL 2.1, section 6).
#   ./sources.sh <tar.gz de sortie>
# Contenu : chaque projet de sources.txt au commit exact (sous-modules compris, sans l'historique Git) et les scripts
# de fabrication de ce dépôt. De quoi refaire libmpv.so.2 à l'identique avec libmpv.sh.
# Outils demandés : git, tar, gzip.
set -euo pipefail

out="$(realpath -m "$1")"
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
dest="$work/sources"
mkdir -p "$dest/fabrication"

# Sources au commit exact (Git vérifie l'empreinte de chaque objet), comme dans libmpv.sh.
grep -v '^#' "$here/sources.txt" | while read -r name url tag commit; do
  [ -n "$name" ] || continue
  git init -q "$dest/$name"
  git -C "$dest/$name" fetch -q --depth 1 "$url" "$commit"
  git -C "$dest/$name" -c advice.detachedHead=false checkout -q FETCH_HEAD
  [ "$(git -C "$dest/$name" rev-parse HEAD)" = "$commit" ] || { echo "$name : commit inattendu" >&2; exit 1; }
  git -C "$dest/$name" submodule -q update --init --depth 1 --recursive
  echo "$name $tag $commit"
done

# Historique Git retiré (dossiers .git et fichiers .git des sous-modules) : seul le code reste.
find "$dest" -name .git -prune -exec rm -rf {} +

cp "$here/sources.txt" "$here/libmpv.sh" "$here/streamlink.sh" "$here/README.md" "$here/LICENSE" "$dest/fabrication/"
cat > "$dest/LISEZ-MOI.txt" <<'TXT'
Sources de la libmpv LGPL fournie avec Velka (Linux x86_64)

Chaque dossier contient un projet au commit exact indiqué dans fabrication/sources.txt (sous-modules compris).
Pour refaire la bibliothèque : voir l'en-tête de fabrication/libmpv.sh (outils demandés), puis
  VELKA_TRAVAIL=<dossier de travail> bash fabrication/libmpv.sh libmpv.zip
après avoir placé ces dossiers dans <dossier de travail>/src/.
Licences : mpv et FFmpeg sous GNU LGPL 2.1 ou plus récente (mpv compilé avec -Dgpl=false, FFmpeg sans --enable-gpl
ni --enable-nonfree) ; les textes de licence de chaque projet sont dans son dossier.
TXT

rm -f "$out"
tar -czf "$out" -C "$work" sources
ls -l "$out"
