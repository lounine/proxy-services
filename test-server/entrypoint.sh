#!/bin/sh

set -eu

/usr/bin/supervisord -c /etc/supervisord.conf
