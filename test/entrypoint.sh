#!/bin/sh

set -eu

for file in /usr/local/bin/test/*; do
  if [ -f "$file" ] && [ -x "$file" ]; then
    filename=$(basename "$file")
    ln -sf ./test/"$filename" /usr/local/bin/"${filename%.*}"
  fi
done

function setup_tun() {
  port=$1
  ip1=$(( port / 10000 ))
  ip2=$(( (port - ip1 * 10000) / 100 ))
  ip3=$(( port - ip1 * 10000 - ip2 * 100 ))
  ip=10.${ip1}.${ip2}.${ip3}

  ip tuntap add mode tun dev tun_${port}
  ip addr add ${ip}/32 dev tun_${port}
  ip link set dev tun_${port} up
}

# in.socks.test.out.vision.reality
setup_tun 9000
setup_tun 9004
setup_tun 9006

# in.socks.test.out.xhttp.direct.stream-up
setup_tun 9100
setup_tun 9104
setup_tun 9106

# in.socks.test.out.xhttp.nginx.stream-up
setup_tun 9110
setup_tun 9114
setup_tun 9116

# in.socks.test.out.xhttp.direct.packet-up
setup_tun 9200
setup_tun 9204
setup_tun 9206

# in.socks.test.out.xhttp.nginx.packet-up
setup_tun 9210
setup_tun 9214
setup_tun 9216
  
# in.socks.test.out.cdn.xhttp.direct.packet-up
setup_tun 9300
setup_tun 9304
setup_tun 9306

# in.socks.test.out.cdn.xhttp.nginx.packet-up
setup_tun 9310
setup_tun 9314
setup_tun 9316

/usr/bin/supervisord -c /etc/supervisord.conf
