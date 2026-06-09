#!/usr/bin/env bash

set -eu

iperf3 --title TEST_1 --bind-dev tun_9000 --time 5 --omit 1 --client test-remote
