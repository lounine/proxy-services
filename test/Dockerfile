# syntax=docker/dockerfile:1.4

FROM alpine:3

RUN <<EOF
  echo "--> Installing dependencies"
  set -ex -o pipefail

  apk update && apk add --no-cache \
    supervisor iproute2 bash curl iperf3 coreutils ncurses jq
  
  ALPINE_ARCH=$(apk --print-arch)
  case "$ALPINE_ARCH" in
    i486 )         ARCH='386'     ;;
    x86_64 )       ARCH='amd64'   ;;
    aarch64 )      ARCH='arm64'   ;;
    armv7)         ARCH='armv7'   ;;
    loongarch64 )  ARCH='loong64' ;;
    ppc64le )      ARCH='ppc64le' ;;
    s390x )        ARCH='s390x'   ;;
    *)      echo "Unsupported architecture: $ALPINE_ARCH";  exit 1  ;;
  esac

  wget -qO- https://github.com/xjasonlyu/tun2socks/releases/latest/download/tun2socks-linux-${ARCH}.zip | unzip -o -d /usr/local/bin/ -
  mv /usr/local/bin/tun2socks-linux-${ARCH} /usr/local/bin/tun2socks
  chmod +x /usr/local/bin/tun2socks
EOF


COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
