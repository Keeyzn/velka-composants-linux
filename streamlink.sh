#!/bin/bash
# Fabrique Streamlink pour Linux x86_64 avec son propre Python, pour Velka.
#   ./streamlink.sh <archive Python autonome .tar.gz> <version de Streamlink> <zip de sortie>
# Python : archive « install_only » de astral-sh/python-build-standalone (x86_64-unknown-linux-gnu), empreinte vérifiée
# par l'appelant. Streamlink et ses dépendances viennent de PyPI (paquets binaires seulement). Disposition du zip :
#   streamlink/bin/streamlink   lanceur (cherché par Velka), qui exécute python/bin/python3 -I -m streamlink
#   streamlink/python/…         Python autonome avec Streamlink installé
# Les liens symboliques sont remplacés par des copies (l'extraction de Velka n'a pas à les gérer).
# Outils demandés : tar, zip.
set -euo pipefail

python_archive="$1"
version="$2"
out="$(realpath -m "$3")"
work="$(mktemp -d)"
dest="$work/streamlink"
mkdir -p "$dest"
tar xzf "$python_archive" -C "$dest"
[ -x "$dest/python/bin/python3" ] || { echo "python/bin/python3 introuvable dans l'archive Python" >&2; exit 1; }

"$dest/python/bin/python3" -I -m pip install --no-cache-dir --disable-pip-version-check --only-binary=:all: "streamlink==$version"
# Versions installées, notées avant de retirer pip.
"$dest/python/bin/python3" -I -m pip freeze --disable-pip-version-check > "$dest/VERSIONS.txt"
# Script installé par pip : chemin absolu de cette machine dans sa première ligne, inutilisable ailleurs.
rm -f "$dest/python/bin/streamlink"
# Inutile pour lancer Streamlink : tests de Python, interface Tk, IDLE, en-têtes C, pip et son installeur.
py="$dest/python"
stdlib="$(echo "$py"/lib/python3.*)"
rm -rf "$stdlib/test" "$stdlib/idlelib" "$stdlib/tkinter" "$stdlib/turtledemo" "$stdlib/ensurepip" \
  "$stdlib"/lib-dynload/_tkinter* "$py"/lib/tcl* "$py"/lib/tk* "$py"/lib/itcl* "$py"/lib/libtcl* "$py"/lib/libtk* \
  "$py/include" "$py/share" "$stdlib"/site-packages/pip "$stdlib"/site-packages/pip-* "$py"/bin/pip* \
  "$py"/lib/thread* "$stdlib"/config-* "$py"/bin/2to3* "$py"/bin/idle* "$py"/bin/pydoc* "$py"/bin/python*-config \
  "$py"/bin/idna "$py"/bin/normalizer "$py"/bin/wsdump
# libpython : le programme python3 de python-build-standalone contient déjà tout Python et ne la charge pas (les
# modules compilés non plus) ; seuls les programmes qui intègrent Python s'en servent. Vérifié plus bas (essai).
rm -f "$py"/lib/libpython3*.so*
# Un seul programme Python (python3) : python et python3.X sont le même fichier de 60 Mo.
real="$(readlink -f "$py/bin/python3")"
rm -f "$py/bin/python3"
mv "$real" "$py/bin/python3"
rm -f "$py"/bin/python "$py"/bin/python3.[0-9]*
# Symboles de débogage retirés (libpython et le programme python3 en contiennent environ 150 Mo).
find "$py" -type f \( -name '*.so' -o -name '*.so.*' \) -exec strip --strip-unneeded {} +
strip "$py/bin/python3"

mkdir -p "$dest/bin"
cat > "$dest/bin/streamlink" <<'SH'
#!/bin/sh
# Lanceur de Streamlink pour Velka : Python autonome du dossier voisin, isolé (-I) des réglages Python de la machine.
dir="$(cd "$(dirname "$0")/.." && pwd)"
exec "$dir/python/bin/python3" -I -m streamlink "$@"
SH
chmod 755 "$dest/bin/streamlink"

# Liens symboliques remplacés par des copies.
find "$dest" -type l | while read -r link; do
  target="$(readlink -f "$link")"
  rm "$link"
  if [ -d "$target" ]; then cp -R "$target" "$link"; else cp "$target" "$link"; fi
done
[ -z "$(find "$dest" -type l)" ] || { echo "liens symboliques restants" >&2; exit 1; }

# Essai : le lanceur répond, depuis un autre dossier que celui de fabrication.
moved="$work/essai/streamlink"
mkdir -p "$work/essai"
cp -R "$dest" "$moved"
"$moved/bin/streamlink" --version
"$moved/bin/streamlink" --can-handle-url https://www.twitch.tv/velka
"$moved/python/bin/python3" -I -c "import lxml.etree, Crypto.Cipher.AES, ssl, trio; print('Modules compilés : OK,', ssl.OPENSSL_VERSION)"
echo "Version de glibc demandée au plus : $(find "$moved" -type f \( -name '*.so*' -o -path '*/bin/python3' \) -exec objdump -T {} \; 2>/dev/null | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -n 1)"
rm -rf "$work/essai"

cat > "$dest/LISEZ-MOI.txt" <<TXT
Streamlink $version pour Velka (Linux x86_64)

Streamlink (https://streamlink.github.io, licence BSD 2 clauses) et ses dépendances (VERSIONS.txt), installés depuis
PyPI dans le Python autonome de astral-sh/python-build-standalone (https://github.com/astral-sh/python-build-standalone,
licence PSF et licences des bibliothèques incluses). Aucun code modifié. Lancement : bin/streamlink.
Script de fabrication : https://github.com/Keeyzn/velka-composants-linux
TXT

rm -f "$out"
(cd "$work" && zip -qr "$out" streamlink)
ls -l "$out"
