#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
PACKAGE_DIR="${ROOT_DIR}/package"
APPDIR="${ROOT_DIR}/AppDir"
CACHE_DIR="${ROOT_DIR}/.cache/appimage-tools"
DIST_DIR="${ROOT_DIR}/dist"

FFMPEG_BIN="${FFMPEG_BIN:-}"
FFPROBE_BIN="${FFPROBE_BIN:-}"
FFMPEG_CACHE_DIR="${ROOT_DIR}/.cache/ffmpeg"

download_file() {
  local url="$1"
  local output="$2"

  if command -v wget >/dev/null 2>&1; then
    wget -q -O "${output}" "${url}"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "${output}" "${url}"
  else
    echo "Neither wget nor curl is available."
    exit 1
  fi
}

resolve_ffmpeg_tools() {
  if [[ -z "${FFMPEG_BIN}" ]]; then
    FFMPEG_BIN="$(command -v ffmpeg || true)"
  fi
  if [[ -z "${FFPROBE_BIN}" ]]; then
    FFPROBE_BIN="$(command -v ffprobe || true)"
  fi

  if [[ -n "${FFMPEG_BIN}" && -n "${FFPROBE_BIN}" ]]; then
    return 0
  fi

  echo "ffmpeg/ffprobe not found in PATH, downloading static build..."
  rm -rf "${FFMPEG_CACHE_DIR}"
  mkdir -p "${FFMPEG_CACHE_DIR}"

  local archive_path="${FFMPEG_CACHE_DIR}/ffmpeg.tar.xz"
  download_file "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz" "${archive_path}"

  tar -xf "${archive_path}" -C "${FFMPEG_CACHE_DIR}"

  local extracted_dir
  extracted_dir="$(find "${FFMPEG_CACHE_DIR}" -maxdepth 1 -type d -name 'ffmpeg-*-amd64-static' | head -n 1)"

  if [[ -z "${extracted_dir}" ]]; then
    echo "Failed to extract ffmpeg static archive."
    exit 1
  fi

  FFMPEG_BIN="${extracted_dir}/ffmpeg"
  FFPROBE_BIN="${extracted_dir}/ffprobe"

  if [[ ! -x "${FFMPEG_BIN}" || ! -x "${FFPROBE_BIN}" ]]; then
    echo "Downloaded ffmpeg binaries are not executable."
    exit 1
  fi
}

qt_query() {
  local key="$1"

  if command -v qtpaths6 >/dev/null 2>&1; then
    qtpaths6 --query "${key}" 2>/dev/null || true
    return
  fi

  if command -v qmake6 >/dev/null 2>&1; then
    qmake6 -query "${key}" 2>/dev/null || true
    return
  fi

  if command -v qmake >/dev/null 2>&1; then
    qmake -query "${key}" 2>/dev/null || true
  fi
}

resolve_ffmpeg_tools

cmake -S "${ROOT_DIR}" -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PACKAGE_DIR}"
cmake --build "${BUILD_DIR}" -j

echo "Build finished, preparing AppDir..."

rm -rf "${PACKAGE_DIR}"
mkdir -p "${PACKAGE_DIR}/bin" "${PACKAGE_DIR}/tools" "${PACKAGE_DIR}/qml" "${PACKAGE_DIR}/plugins" "${PACKAGE_DIR}/lib"

if [[ -f "${BUILD_DIR}/bin/ClipClipping" ]]; then
  cp "${BUILD_DIR}/bin/ClipClipping" "${PACKAGE_DIR}/bin/ClipClipping"
elif [[ -f "${BUILD_DIR}/bin/Release/ClipClipping" ]]; then
  cp "${BUILD_DIR}/bin/Release/ClipClipping" "${PACKAGE_DIR}/bin/ClipClipping"
else
  echo "Could not find built ClipClipping binary in ${BUILD_DIR}/bin"
  exit 1
fi

QT_BASE="${QT_ROOT_DIR:-}"
if [[ -z "${QT_BASE}" ]]; then
  QT_BASE="$(qt_query QT_INSTALL_PREFIX)"
  if [[ -z "${QT_BASE}" ]]; then
    QMAKE_BIN="$(command -v qmake6 || command -v qmake || true)"
    if [[ -z "${QMAKE_BIN}" ]]; then
      echo "qmake6/qmake not found and QT_ROOT_DIR is not set. Cannot locate Qt runtime."
      exit 1
    fi
    QT_BASE="$(dirname "$(dirname "${QMAKE_BIN}")")"
  fi
fi

QT_QML_DIR="${QT_BASE}/qml"
QT_PLUGINS_DIR="${QT_BASE}/plugins"
QT_LIB_DIR="${QT_BASE}/lib"

if [[ ! -d "${QT_PLUGINS_DIR}" ]]; then
  QT_PLUGINS_DIR="$(qt_query QT_INSTALL_PLUGINS)"
fi
if [[ ! -d "${QT_QML_DIR}" ]]; then
  QT_QML_DIR="$(qt_query QT_INSTALL_QML)"
fi
if [[ ! -d "${QT_LIB_DIR}" ]]; then
  QT_LIB_DIR="$(qt_query QT_INSTALL_LIBS)"
fi

if [[ ! -d "${QT_PLUGINS_DIR}" || ! -d "${QT_QML_DIR}" || ! -d "${QT_LIB_DIR}" ]]; then
  echo "Failed to resolve Qt runtime directories."
  echo "QT_BASE=${QT_BASE}"
  echo "QT_PLUGINS_DIR=${QT_PLUGINS_DIR}"
  echo "QT_QML_DIR=${QT_QML_DIR}"
  echo "QT_LIB_DIR=${QT_LIB_DIR}"
  echo "Set QT_ROOT_DIR manually, e.g.: QT_ROOT_DIR=/path/to/Qt/6.x.x/gcc_64 ./scripts/build-appimage.sh"
  exit 1
fi

if [[ ! -f "${QT_PLUGINS_DIR}/platforms/libqxcb.so" ]]; then
  echo "Qt platform plugin libqxcb.so not found in ${QT_PLUGINS_DIR}/platforms"
  exit 1
fi

cat > "${PACKAGE_DIR}/bin/qt.conf" <<'EOF'
[Paths]
Prefix=..
Plugins=plugins
QmlImports=qml
EOF

cp -a "${QT_PLUGINS_DIR}/platforms" "${PACKAGE_DIR}/plugins/"
if [[ -d "${QT_PLUGINS_DIR}/xcbglintegrations" ]]; then cp -a "${QT_PLUGINS_DIR}/xcbglintegrations" "${PACKAGE_DIR}/plugins/"; fi
if [[ -d "${QT_PLUGINS_DIR}/wayland-shell-integration" ]]; then cp -a "${QT_PLUGINS_DIR}/wayland-shell-integration" "${PACKAGE_DIR}/plugins/"; fi
if [[ -d "${QT_PLUGINS_DIR}/wayland-decoration-client" ]]; then cp -a "${QT_PLUGINS_DIR}/wayland-decoration-client" "${PACKAGE_DIR}/plugins/"; fi
if [[ -d "${QT_PLUGINS_DIR}/imageformats" ]]; then cp -a "${QT_PLUGINS_DIR}/imageformats" "${PACKAGE_DIR}/plugins/"; fi
if [[ -d "${QT_PLUGINS_DIR}/multimedia" ]]; then cp -a "${QT_PLUGINS_DIR}/multimedia" "${PACKAGE_DIR}/plugins/"; fi
if [[ -d "${QT_PLUGINS_DIR}/mediaservice" ]]; then cp -a "${QT_PLUGINS_DIR}/mediaservice" "${PACKAGE_DIR}/plugins/"; fi

cp -a "${QT_LIB_DIR}"/libQt6*.so* "${PACKAGE_DIR}/lib/" || true
cp -a "${QT_LIB_DIR}"/libicu*.so* "${PACKAGE_DIR}/lib/" || true

for module_dir in QtQuick QtQuick.2 QtQml QtMultimedia; do
  if [[ -d "${QT_QML_DIR}/${module_dir}" ]]; then
    cp -a "${QT_QML_DIR}/${module_dir}" "${PACKAGE_DIR}/qml/"
  fi
done

cp "${FFMPEG_BIN}" "${PACKAGE_DIR}/tools/ffmpeg"
cp "${FFPROBE_BIN}" "${PACKAGE_DIR}/tools/ffprobe"
chmod +x "${PACKAGE_DIR}/tools/ffmpeg" "${PACKAGE_DIR}/tools/ffprobe"

rm -rf "${APPDIR}"
mkdir -p "${CACHE_DIR}" "${DIST_DIR}"
mkdir -p "${APPDIR}/usr"
cp -a "${PACKAGE_DIR}/." "${APPDIR}/usr/"

mkdir -p "${APPDIR}/usr/share/applications"
cat > "${APPDIR}/usr/share/applications/clipclipping.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=ClipClipping
Exec=ClipClipping
Icon=clipclipping
Categories=AudioVideo;Video;
EOF

mkdir -p "${APPDIR}/usr/share/icons/hicolor/256x256/apps"
cp "${ROOT_DIR}/assets/ClipClippingIcon.png" "${APPDIR}/usr/share/icons/hicolor/256x256/apps/clipclipping.png"
cp "${ROOT_DIR}/assets/ClipClippingIcon.png" "${APPDIR}/clipclipping.png"

# Required by appimagetool when linuxdeploy step fails early
cp "${APPDIR}/usr/share/applications/clipclipping.desktop" "${APPDIR}/clipclipping.desktop"
ln -snf "usr/share/icons/hicolor/256x256/apps/clipclipping.png" "${APPDIR}/.DirIcon"
cat > "${APPDIR}/AppRun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

APPDIR="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="${APPDIR}/usr/lib:${LD_LIBRARY_PATH:-}"
export QT_PLUGIN_PATH="${APPDIR}/usr/plugins"
export QML2_IMPORT_PATH="${APPDIR}/usr/qml"
unset QT_QPA_PLATFORMTHEME
export QT_QUICK_DIALOGS_USE_NATIVE_DIALOGS=0
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
unset QT_QUICK_BACKEND
unset LIBGL_ALWAYS_SOFTWARE
unset QSG_RHI_BACKEND

exec "${APPDIR}/usr/bin/ClipClipping" "$@"
EOF
chmod +x "${APPDIR}/AppRun"

pushd "${CACHE_DIR}" >/dev/null
if [[ ! -f linuxdeploy-x86_64.AppImage ]]; then
  wget -q https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
fi
if [[ ! -f linuxdeploy-plugin-qt-x86_64.AppImage ]]; then
  wget -q https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage
fi
if [[ ! -f appimagetool-x86_64.AppImage ]]; then
  wget -q https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
fi
chmod +x linuxdeploy-x86_64.AppImage linuxdeploy-plugin-qt-x86_64.AppImage
chmod +x appimagetool-x86_64.AppImage
ln -sf linuxdeploy-plugin-qt-x86_64.AppImage linuxdeploy-plugin-qt

export LINUXDEPLOY_USE_HOST_TOOLS=1

OUTPUT_NAME="ClipClipping-local-x86_64.AppImage"
rm -f "${ROOT_DIR}"/ClipClipping-*.AppImage

echo "Running linuxdeploy (this step can take a while)..."
if ! ./linuxdeploy-x86_64.AppImage \
  --appdir "${APPDIR}" \
  -e "${APPDIR}/usr/bin/ClipClipping" \
  -d "${APPDIR}/usr/share/applications/clipclipping.desktop" \
  -i "${APPDIR}/usr/share/icons/hicolor/256x256/apps/clipclipping.png" \
  --output appimage; then
  echo "linuxdeploy failed, trying fallback appimagetool..."
fi

if [[ ! -f "${ROOT_DIR}/ClipClipping-x86_64.AppImage" && ! -f "${CACHE_DIR}/ClipClipping-x86_64.AppImage" ]]; then
  echo "Running appimagetool fallback..."
  ARCH=x86_64 ./appimagetool-x86_64.AppImage "${APPDIR}"
fi

if [[ -f "${CACHE_DIR}/ClipClipping-x86_64.AppImage" ]]; then
  mv "${CACHE_DIR}/ClipClipping-x86_64.AppImage" "${DIST_DIR}/${OUTPUT_NAME}"
elif [[ -f "${ROOT_DIR}/ClipClipping-x86_64.AppImage" ]]; then
  mv "${ROOT_DIR}/ClipClipping-x86_64.AppImage" "${DIST_DIR}/${OUTPUT_NAME}"
fi

if [[ ! -f "${DIST_DIR}/${OUTPUT_NAME}" ]]; then
  echo "AppImage was not produced."
  exit 1
fi

echo "Built AppImage: ${DIST_DIR}/${OUTPUT_NAME}"
popd >/dev/null
