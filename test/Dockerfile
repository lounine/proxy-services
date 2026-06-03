# syntax=docker/dockerfile:1.4

FROM alpine:3

RUN <<EOF
  echo "--> Installing dependencies"
  set -ex -o pipefail

  apk add --no-cache curl
EOF
