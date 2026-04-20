# syntax=docker/dockerfile:1.4

FROM telegrammessenger/proxy:2.0beta

RUN <<EOF
  echo "--> Installing dependencies"
  set -ex

  apt update
  apt install -y --no-install-recommends \
    iproute2
EOF
