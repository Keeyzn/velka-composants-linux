#!/bin/bash
# Fabrique libmpv LGPL pour Linux x86_64, pour Velka.
#   ./libmpv.sh <zip de sortie>
# Sources : sources.txt (dépôt, étiquette et commit exact de chaque projet). Toutes les bibliothèques sont compilées
# ici et liées dans une seule libmpv.so.2 ; elle ne demande au système que la glibc, le son (libpulse, libasound) et
# rien d'autre. Licence : mpv compilé avec -Dgpl=false, FFmpeg sans --enable-gpl ni --enable-nonfree (LGPL 2.1 ou plus
# récente) ; autres bibliothèques sous licences libres permissives ou LGPL.
# Outils demandés : gcc, g++, make, nasm, pkg-config, git, python3, meson (1.3 ou plus récent), ninja, zip, et les
# en-têtes libpulse-dev et libasound2-dev.
set -euo pipefail

out="$(realpath -m "$1")"
here="$(cd "$(dirname "$0")" && pwd)"
work="${VELKA_TRAVAIL:-$(mktemp -d)}"
src="$work/src"
prefix="$work/prefix"
jobs="$(nproc)"
mkdir -p "$src" "$prefix"

export PKG_CONFIG_PATH="$prefix/lib/pkgconfig:$prefix/lib/x86_64-linux-gnu/pkgconfig"
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/share/pkgconfig"
export CFLAGS="-O2 -fPIC" CXXFLAGS="-O2 -fPIC"

# Sources au commit exact (Git vérifie l'empreinte de chaque objet).
grep -v '^#' "$here/sources.txt" | while read -r name url tag commit; do
  [ -n "$name" ] || continue
  if [ ! -d "$src/$name/.git" ]; then
    git init -q "$src/$name"
    git -C "$src/$name" fetch -q --depth 1 "$url" "$commit"
    git -C "$src/$name" -c advice.detachedHead=false checkout -q FETCH_HEAD
  fi
  [ "$(git -C "$src/$name" rev-parse HEAD)" = "$commit" ] || { echo "$name : commit inattendu" >&2; exit 1; }
  git -C "$src/$name" submodule -q update --init --depth 1 --recursive
done

# Bibliothèques statiques (code relogeable) dans $prefix.
meson_static() {
  local name="$1"; shift
  meson setup "$work/build-$name" "$src/$name" --prefix="$prefix" --libdir=lib --buildtype=release \
    --default-library=static -Db_staticpic=true -Dwrap_mode=nodownload "$@"
  ninja -C "$work/build-$name" install
}

(cd "$src/zlib" && ./configure --static --prefix="$prefix" && make -j"$jobs" install)
meson_static freetype -Dbrotli=disabled -Dbzip2=disabled -Dharfbuzz=disabled -Dpng=disabled -Dzlib=disabled -Dtests=disabled
meson_static fribidi -Ddocs=false -Dbin=false -Dtests=false
meson_static harfbuzz -Dfreetype=disabled -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dchafa=disabled \
  -Dicu=disabled -Dgraphite2=disabled -Dtests=disabled -Ddocs=disabled -Dutilities=disabled -Dintrospection=disabled
meson_static libass -Dfontconfig=disabled -Drequire-system-font-provider=false -Dtest=disabled -Dcompare=disabled \
  -Dprofile=disabled -Dfuzz=disabled -Dcheckasm=disabled
meson_static libplacebo -Dvulkan=disabled -Dopengl=enabled -Dglslang=disabled -Dshaderc=disabled -Dlcms=disabled \
  -Ddovi=disabled -Dlibdovi=disabled -Dxxhash=disabled -Dunwind=disabled -Ddemos=false -Dtests=false
# libplacebo contient du C++ : sa bibliothèque standard est liée dans libmpv (aucune version de libstdc++ demandée au
# système, mpv étant lié comme un programme C).
grep -q 'libstdc++' "$prefix/lib/pkgconfig/libplacebo.pc" || sed -i 's|^Libs:.*|& -l:libstdc++.a|' "$prefix/lib/pkgconfig/libplacebo.pc"
grep -q 'libstdc++' "$prefix/lib/pkgconfig/libplacebo.pc" || { echo "libplacebo.pc : ligne Libs absente" >&2; exit 1; }

# FFmpeg : composants internes seulement (aucune bibliothèque du système détectée), sans GPL ni nonfree.
mkdir -p "$work/build-ffmpeg"
(cd "$work/build-ffmpeg" && "$src/ffmpeg/configure" --prefix="$prefix" --enable-static --disable-shared --enable-pic \
  --disable-programs --disable-doc --disable-debug --disable-autodetect --enable-zlib \
  --pkg-config-flags=--static --extra-cflags="-I$prefix/include" --extra-ldflags="-L$prefix/lib" \
  && make -j"$jobs" && make install)
if grep -q -- '--enable-gpl\|--enable-nonfree' "$prefix/lib/pkgconfig/libavutil.pc" 2>/dev/null; then
  echo "FFmpeg n'est pas LGPL" >&2; exit 1
fi

# mpv : libmpv seule, rien de détecté automatiquement, sortie vidéo par l'API de rendu OpenGL de l'application.
meson setup "$work/build-mpv" "$src/mpv" --prefix="$prefix" --libdir=lib --buildtype=release --prefer-static \
  -Dauto_features=disabled -Dlibmpv=true -Dcplayer=false -Dgpl=false -Dtests=false \
  -Dlibavdevice=enabled -Dgl=enabled -Dplain-gl=enabled -Dzlib=enabled -Diconv=enabled -Dpulse=enabled -Dalsa=enabled \
  -Dc_link_args="-static-libgcc -Wl,--exclude-libs,ALL" -Dcpp_link_args="-static-libgcc -static-libstdc++"
ninja -C "$work/build-mpv"
lib="$(find "$work/build-mpv" -maxdepth 1 -name 'libmpv.so.2*' -type f | head -n 1)"
[ -n "$lib" ] || { echo "libmpv.so.2 introuvable" >&2; exit 1; }

dest="$work/paquet/libmpv"
rm -rf "$work/paquet" && mkdir -p "$dest"
cp "$lib" "$dest/libmpv.so.2"
strip --strip-unneeded "$dest/libmpv.so.2"

# Dépendances du système : seulement la glibc et le son.
echo "Bibliothèques demandées au système :"
readelf -d "$dest/libmpv.so.2" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | tee "$work/needed.txt"
allowed='^(libc|libm|libdl|libpthread|librt|libpulse|libasound|ld-linux-x86-64)\.so'
if grep -Ev "$allowed" "$work/needed.txt"; then
  echo "bibliothèque du système non prévue (ci-dessus)" >&2; exit 1
fi
echo "Version de glibc demandée au plus : $(objdump -T "$dest/libmpv.so.2" | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -n 1)"

# Essai : la bibliothèque se charge et répond (API cliente).
python3 - "$dest/libmpv.so.2" <<'PY'
import ctypes, sys
lib = ctypes.CDLL(sys.argv[1])
v = lib.mpv_client_api_version()
print(f"API cliente mpv {v >> 16}.{v & 0xffff}")
lib.mpv_create.restype = ctypes.c_void_p
h = lib.mpv_create()
assert h, "mpv_create a échoué"
lib.mpv_initialize.argtypes = [ctypes.c_void_p]
assert lib.mpv_initialize(ctypes.c_void_p(h)) == 0, "mpv_initialize a échoué"
lib.mpv_terminate_destroy.argtypes = [ctypes.c_void_p]
lib.mpv_terminate_destroy(ctypes.c_void_p(h))
PY

# Licences et versions.
mkdir -p "$dest/licences"
cp "$src/mpv/LICENSE.LGPL" "$dest/licences/mpv-LGPL.txt"
cp "$src/ffmpeg/COPYING.LGPLv2.1" "$dest/licences/ffmpeg-LGPL-2.1.txt"
cp "$src/libplacebo/LICENSE" "$dest/licences/libplacebo.txt"
cp "$src/libass/COPYING" "$dest/licences/libass.txt"
cp "$src/fribidi/COPYING" "$dest/licences/fribidi.txt"
cp "$src/harfbuzz/COPYING" "$dest/licences/harfbuzz.txt"
cp "$src/freetype/LICENSE.TXT" "$dest/licences/freetype.txt"
cp "$src/freetype/docs/FTL.TXT" "$dest/licences/freetype-FTL.txt"
cp "$src/zlib/LICENSE" "$dest/licences/zlib.txt"
grep -v '^#' "$here/sources.txt" > "$dest/SOURCES.txt"
cat > "$dest/LISEZ-MOI.txt" <<TXT
libmpv pour Velka (Linux x86_64), licence GNU LGPL 2.1 ou plus récente.

mpv (https://mpv.io) compilé avec -Dgpl=false ; FFmpeg (https://ffmpeg.org) sans --enable-gpl ni --enable-nonfree ;
libplacebo, libass, FriBidi, HarfBuzz, FreeType et zlib liés dans la bibliothèque (licences dans licences/). Sources
exactes (dépôts et commits) : SOURCES.txt. Aucun code modifié. Script de fabrication :
https://github.com/Keeyzn/velka-composants-linux
Vous pouvez remplacer libmpv.so.2 par votre propre version de libmpv dans Velka (Réglages > Avancé et Système >
Chemins personnalisés).
TXT

rm -f "$out"
(cd "$work/paquet" && zip -qr "$out" libmpv)
ls -l "$out"
