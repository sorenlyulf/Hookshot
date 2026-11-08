#!/bin/bash
# The Linux AppImage: Hookshot Builder with everything it needs to build the game on the player's PC. No game data and
# nothing made from it is in it: the game is built from the player's own copy, as on Windows.
#
#   scripts/linux/deps.sh        (first: the compiler, Python, FFmpeg, SDL2, headers into build-linux/deps)
#   scripts/linux/appimage.sh    -> build-linux/Hookshot-<version>-x86_64.AppImage
# The same image builds the game and, with --play, starts the one it saved.
#
# Works on Arch Linux / CachyOS (and still on Ubuntu / Debian: the host's layout is detected below).
#
# The sysroot the AppImage carries is the BUILD SYSTEM's C library, so the builds run on that glibc and newer.
# Built on Ubuntu 22.04 (CI) that is glibc 2.35. Built on Arch it is Arch's current glibc (2.40+), so the AppImage will
# only build working games on equally recent systems. For wide compatibility build inside an Ubuntu 22.04 container.
# work/ (hot_funcs.txt, hot_order.txt, hookshot_pieces.prof, image/chunks.txt: addresses and counts from playing, no
# game code) is carried along when it is there.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
B=$ROOT/build-linux
DEPS=${DEPS:-$B/deps}
APPDIR=$B/AppDir
VERSION=${HOOKSHOT_VERSION:-$(git describe --tags --always 2>/dev/null || echo dev)}
export EMSDK=$DEPS/emsdk RX_CPM=$DEPS/cpm
PY=$DEPS/python/bin/python3

# ---- the host's layout: Arch keeps the C library in /usr/lib and GCC under x86_64-pc-linux-gnu, Debian / Ubuntu use
# the multiarch directories ----
DISTRO=debian
if [ -r /etc/os-release ]; then
    . /etc/os-release
    case " ${ID:-} ${ID_LIKE:-} " in *" arch "*) DISTRO=arch;; esac
fi
if [ "$DISTRO" = arch ]; then
    M=/usr/lib                       # the C library and start files
    GCC_TRIPLE=x86_64-pc-linux-gnu
else
    M=/usr/lib/x86_64-linux-gnu
    GCC_TRIPLE=x86_64-linux-gnu
fi
echo "host: $DISTRO, $(ldd --version | head -1)"
if [ "$DISTRO" = arch ]; then
    echo "note: the sysroot will carry this system's (new) glibc; build in an Ubuntu 22.04 container for glibc 2.35 compatibility" >&2
fi

# ---- the Vulkan back end, built here once (it needs no game) ----
VKW=$B/vk-work
rm -rf "$VKW/sa/build/hookshot_vk.so"
OOT_WORK=$VKW RX_VK_ONLY=1 RX_RELEASE=1 "$PY" -I nx2/build.py --standalone --jobs "${JOBS:-$(nproc)}"
VK=$VKW/sa/build/hookshot_vk.so
[ -f "$VK" ] || { echo "hookshot_vk.so was not built"; exit 1; }

# ---- the tools' native helpers, built now: the AppImage is read-only. a64emit with its C++ runtime inside (the one this system
# builds with is newer than older systems have), and the stamp build_emit.py checks, so it is not built again ----
E=third_party/a64-kit/lift
"$EMSDK/upstream/bin/clang++" -std=c++20 -O2 -shared -fPIC -static-libstdc++ -static-libgcc -Wno-everything \
    -o "$E/liba64emit.so" "$E/a64emit.cpp"
"$PY" -I -c "import hashlib, sys; f = ['$E/a64emit.cpp', '$E/suyu/arm64_to_c.h']; open('$E/liba64emit.so.sha1', 'w').write(hashlib.sha1(b''.join(open(x, 'rb').read() for x in f)).hexdigest())"
"$PY" -I third_party/a64-kit/lift/build_emit.py
"$PY" -I -c "import sys; sys.path.insert(0, 'nx2'); import zbic; zbic.lib()"

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/share/hookshot" "$APPDIR/usr/lib/hookshot"
T=$APPDIR/usr/share/hookshot
L=$APPDIR/usr/lib/hookshot

# ---- the tools (the sources the player's build compiles, and the scripts) ----
cp -a nx2 host LICENSE readme.md assets "$T/"
printf '%s\n' "$VERSION" > "$T/VERSION"   # (no git history in here: nx2/version.py reads the release name from it)
mkdir -p "$T/builder" "$T/gpu/render" "$T/gpu/vk" "$T/third_party"
cp -a builder/linux "$T/builder/"
cp -a gpu/render/*.h "$T/gpu/render/"
cp -a gpu/vk/vk_api.h "$T/gpu/vk/"
cp -a third_party/opus "$T/third_party/"
mkdir -p "$T/third_party/zbic" "$T/third_party/a64-kit"
cp -a third_party/zbic/zbic.so third_party/zbic/LICENSE third_party/zbic/PROVENANCE.md "$T/third_party/zbic/"
cp -a third_party/a64-kit/* "$T/third_party/a64-kit/"
rm -f "$T/third_party/a64-kit/tools/lld-link.exe"
if [ -d work ]; then
    mkdir -p "$T/work/image"
    for f in hot_funcs.txt hot_order.txt hookshot_pieces.prof; do [ -f "work/$f" ] && cp "work/$f" "$T/work/"; done
    [ -f work/image/chunks.txt ] && cp work/image/chunks.txt "$T/work/image/"
fi
find "$T" -name __pycache__ -prune -exec rm -rf {} +

# ---- what it builds with ----
cp -a "$DEPS/python" "$APPDIR/usr/python"
mkdir -p "$L/emsdk"
cp -a "$DEPS/emsdk/upstream" "$L/emsdk/"
cp -a "$DEPS/ffmpeg" "$L/ffmpeg"
cp "$VK" "$L/hookshot_vk.so"
cp "$DEPS/sdl2/libSDL2-2.0.so.0" "$L/libSDL2-2.0.so.0"
cp -a "$DEPS/licenses" "$T/licenses"   # (LLVM, FFmpeg, dav1d, SDL2: what this AppImage carries besides Hookshot)

# the sysroot: this system's C library (headers, start files, the libraries to link against) and GCC's runtime pieces
S=$L/sysroot
mkdir -p "$S/usr/lib" "$S/usr/lib/gcc/$GCC_TRIPLE" "$S/lib64"
ln -s usr/lib "$S/lib"
if [ "$DISTRO" = arch ]; then
    # Arch's libc.so / libm.so linker scripts name /usr/lib/libc.so.6 and so on, so the files stay directly in usr/lib;
    # the multiarch name the Debian-style layout (and anything that looks for it) uses points back to the same place
    SL=$S/usr/lib
    ln -s . "$S/usr/lib/x86_64-linux-gnu"
else
    SL=$S/usr/lib/x86_64-linux-gnu
    mkdir -p "$SL"
fi
cp -a /usr/include "$S/usr/"
rm -rf "$S/usr/include/c++" "$S/usr/include/x86_64-linux-gnu/c++" "$S/usr/include/llvm"* "$S/usr/include/clang"*
for f in crt1.o crti.o crtn.o Scrt1.o rcrt1.o libc.so libc.so.6 libc_nonshared.a libm.so libm.so.6 libm.a libmvec.so libmvec.so.1 \
         libmvec.a libpthread.so.0 libpthread.a libdl.so.2 libdl.a librt.so.1 librt.a libutil.a libgcc_s.so.1 ld-linux-x86-64.so.2; do
    # (-L: Arch and Debian both have symlinks here; the sysroot gets real files)
    if [ -e "$M/$f" ]; then cp -aL "$M/$f" "$SL/"; fi
done
cp -aL /lib64/ld-linux-x86-64.so.2 "$S/lib64/"
GCC=$(ls -d /usr/lib/gcc/$GCC_TRIPLE/*/ | sort -V | tail -1)
G=$S/usr/lib/gcc/$GCC_TRIPLE/$(basename "$GCC")
mkdir -p "$G"
for f in crtbegin.o crtbeginS.o crtbeginT.o crtend.o crtendS.o libgcc.a libgcc_eh.a libgcc_s.so; do
    if [ -e "$GCC/$f" ]; then cp -aL "$GCC/$f" "$G/"; fi
done
# (libgcc_s.so is a linker script or a symlink to libgcc_s.so.1: found in the sysroot through lib -> usr/lib, and in
# usr/lib itself on Arch)
for need in "$SL/crt1.o" "$SL/libc.so" "$SL/libc.so.6" "$G/crtbegin.o" "$G/libgcc.a"; do
    [ -e "$need" ] || { echo "sysroot is missing $need (on Arch: sudo pacman -S --needed base-devel)"; exit 1; }
done

# ---- check: the bundled compiler builds and links a program against the sysroot, and it runs ----
cat > "$B/t.c" <<'EOF'
#include <pthread.h>
#include <stdio.h>
#include <math.h>
static void *f(void *p) { return p; }
int main(void) { pthread_t t; pthread_create(&t, 0, f, 0); pthread_join(t, 0); printf("ok %g\n", sqrt(2.0)); return 0; }
EOF
"$L/emsdk/upstream/bin/clang" --sysroot="$S" -fuse-ld=lld -O2 -march=x86-64-v3 "$B/t.c" -o "$B/t" -lpthread -lm
"$B/t"

# ---- the AppDir's own files ----
cp builder/linux/AppRun "$APPDIR/AppRun"
cp builder/linux/hookshot-builder.desktop "$APPDIR/"
cp assets/hookshot.png "$APPDIR/hookshot.png"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
cp assets/hookshot.png "$APPDIR/usr/share/icons/hicolor/256x256/apps/hookshot.png"

OUT=$B/Hookshot-$VERSION-x86_64.AppImage
rm -f "$OUT"
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$DEPS/appimagetool" --comp zstd "$APPDIR" "$OUT"
echo "$OUT: $(du -h "$OUT" | cut -f1)"
