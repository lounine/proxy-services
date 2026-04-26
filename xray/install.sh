#!/usr/bin/env ash

set -euo pipefail


check_if_running_as_root() {
  if [ "$(id -u)" -gt 0 ]; then
    echo "ERROR: This script must be run as root"; exit 1
  fi
}

identify_architecture() {
  if [ "$(uname)" != 'Linux' ]; then
    echo "ERROR: Unsupported operating system"; exit 1
  fi
  case "$(uname -m)" in
  'i386' | 'i686')      MACHINE='32'        ;;
  'amd64' | 'x86_64')   MACHINE='64'        ;;
  'armv5tel')           MACHINE='arm32-v5'  ;;
  'armv6l')             MACHINE='arm32-v6'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || \
                        MACHINE='arm32-v5'  ;;
  'armv7' | 'armv7l')   MACHINE='arm32-v7a'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || \
                        MACHINE='arm32-v5'  ;;
  'armv8' | 'aarch64')  MACHINE='arm64-v8a' ;;
  'mips')               MACHINE='mips32'    ;;
  'mipsle')             MACHINE='mips32le'  ;;
  'mips64')             MACHINE='mips64'
        lscpu | grep -q "Little Endian" && 
                        MACHINE='mips64le'  ;;
  'mips64le')           MACHINE='mips64le'  ;;
  'ppc64')              MACHINE='ppc64'     ;;
  'ppc64le')            MACHINE='ppc64le'   ;;
  'riscv64')            MACHINE='riscv64'   ;;
  's390x')              MACHINE='s390x'     ;;
  *)    echo "ERROR: Unsupported architecture"; exit 1  ;;
  esac
}

download_xray() {
  echo "Downloading Xray files..."
  if ! curl -f -L -H 'Cache-Control: no-cache' -o "$ZIP_FILE" "$DOWNLOAD_LINK" -#; then
    echo 'ERROR: Download failed! Please check your network or try again.'; exit 1
  fi
  if ! curl -f -L -H 'Cache-Control: no-cache' -o "$ZIP_FILE.dgst" "$DOWNLOAD_LINK.dgst" -#; then
    echo 'ERROR: Download failed! Please check your network or try again.'; exit 1
  fi
}

verify_checksum() {
  echo "Verifying checksum..."
  CHECKSUM=$(awk -F '= ' '/256=/ {print $2}' "$ZIP_FILE.dgst")
  LOCALSUM=$(sha256sum "$ZIP_FILE" | awk '{printf $1}')
  if [ "$CHECKSUM" != "$LOCALSUM" ]; then
    echo 'ERROR: SHA256 check failed'; exit 1
  fi
}

decompress_files() {
  echo "Decompressing files..."
  unzip -q "$ZIP_FILE" -d "$TMP_DIRECTORY"
}

install_xray() {
  echo "Installing Xray..."
  install -m 755 "${TMP_DIRECTORY}/xray" "/usr/local/bin/xray"
  install -m 755 -d /usr/local/share/xray/
  install -m 644 "${TMP_DIRECTORY}/geoip.dat" "/usr/local/share/xray/geoip.dat"
  install -m 644 "${TMP_DIRECTORY}/geosite.dat" "/usr/local/share/xray/geosite.dat"
  install -m 755 -d /usr/local/etc/xray/
  install -m 755 -d -o 1000 -g 1000 /var/log/xray/
}


check_if_running_as_root || return 1
identify_architecture || return 1

TMP_DIRECTORY="$(mktemp -d)"
ZIP_FILE="${TMP_DIRECTORY}/Xray-linux-$MACHINE.zip"
DOWNLOAD_LINK="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-$MACHINE.zip"

download_xray
verify_checksum
decompress_files
install_xray

rm -r "$TMP_DIRECTORY"
