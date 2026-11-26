#!/usr/bin/env bash
set -euo pipefail

local_bin="$HOME/.local/bin"
opt_dir="$HOME/.local/opt"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"

# Extract once for reliable launching on Atomic hosts without FUSE 2.
install_appimage() (
    local app="$1" version="$2" url="$3" checksum="$4" desktop="$5" icon="$6"
    local launcher="$local_bin/$app" app_dir="$opt_dir/$app-$version"

    if command -v "$app" >/dev/null || [ -x "$launcher" ]; then
        echo "$app already installed, skipping."
        return
    fi

    mkdir -p "$local_bin" "$opt_dir" "$data_dir/applications"
    if [ ! -x "$app_dir/AppRun" ]; then
        local stage extracted
        stage=$(mktemp -d "$opt_dir/.${app}-install.XXXXXX")
        trap 'rm -rf "$stage"' EXIT
        curl -fsSL "$url" -o "$stage/app.AppImage"
        printf '%s  %s\n' "$checksum" "$stage/app.AppImage" | sha256sum -c -
        chmod 755 "$stage/app.AppImage"
        (cd "$stage" && ./app.AppImage --appimage-extract >/dev/null)
        extracted=$(realpath "$stage/squashfs-root")
        test -x "$extracted/AppRun"
        mv -T "$extracted" "$app_dir"
    fi

    install -Dm644 "$app_dir/.DirIcon" "$data_dir/icons/hicolor/256x256/apps/$icon.png"
    sed -e 's/^Categories=$/Categories=Utility;/' -e 's/^Comment=Handy$/Comment=Offline speech-to-text/' "$app_dir/$desktop" > "$data_dir/applications/$desktop"
    if [ "$app" = ghostty ]; then
        for entry in g/ghostty x/xterm-ghostty; do
            if [ ! -e "$HOME/.terminfo/$entry" ]; then
                install -Dm644 "$app_dir/share/terminfo/$entry" "$HOME/.terminfo/$entry"
            fi
        done
    fi

    printf '#!/usr/bin/env bash\nexport APPDIR=%q\nexec "$APPDIR/AppRun" "$@"\n' "$app_dir" > "$launcher"
    chmod 755 "$launcher"
    echo "$app $version installed to $launcher"
)

ghostty_version=1.4.0
handy_version=0.10.2
case "$(uname -m)" in
    x86_64)
        ghostty_arch=x86_64
        ghostty_sha=50ad4f8b54a01e7d41426e7d12ffae9c88aa1c516ac140755e2bca596e1d2ae6
        handy_arch=amd64
        handy_sha=17c5f1a4a33f9c4c5c234a084cc0aaf766f3a5b62662e02d70e51161800ace17
        ;;
    aarch64)
        ghostty_arch=aarch64
        ghostty_sha=932e21c671c215e6140633027acb4e8705cef3377d335202211c32d88b5bf506
        handy_arch=aarch64
        handy_sha=60e2b83bc02ae05e691bfae2d3cbf0b063fc64ff45ff6d212c0ca0a1ee134965
        ;;
    *) echo "Unsupported architecture for Atomic AppImages: $(uname -m)" >&2; exit 1 ;;
esac

install_appimage ghostty "$ghostty_version" \
    "https://github.com/pkgforge-dev/ghostty-appimage/releases/download/v${ghostty_version}/Ghostty-${ghostty_version}-${ghostty_arch}.AppImage" \
    "$ghostty_sha" com.mitchellh.ghostty.desktop com.mitchellh.ghostty
install_appimage handy "$handy_version" \
    "https://github.com/cjpais/Handy/releases/download/v${handy_version}/Handy_${handy_version}_${handy_arch}.AppImage" \
    "$handy_sha" Handy.desktop handy
