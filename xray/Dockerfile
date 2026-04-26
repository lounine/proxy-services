# syntax=docker/dockerfile:1.4

FROM alpine:3

RUN <<EOF
  echo "--> Installing dependencies"
  set -ex -o pipefail

  apk add --no-cache curl unzip
EOF

COPY ./install.sh /install.sh

RUN <<EOF
  echo "--> Installing xray"
  set -ex -o pipefail

  ash /install.sh
EOF

RUN <<EOF
  echo "--> Cleaning up"
  set -ex -o pipefail

  apk del --no-cache curl unzip
  rm -f /install.sh
EOF

USER 1000:1000
ENTRYPOINT [ "/usr/local/bin/xray" ]
CMD [ "run", "-confdir", "/usr/local/etc/xray/" ]
