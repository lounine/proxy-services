# syntax=docker/dockerfile:1.4

FROM alpine:3

RUN <<EOF
  echo "--> Installing dependencies"
  set -ex -o pipefail

  apk update && apk add --no-cache \
    supervisor iperf3
EOF


COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
