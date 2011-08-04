#!/bin/sh

set -e

cd /etc/firewall

# We actually 'cat' a bunch of files together into combined.ferm and run that.
# I liked it better when ferm actually supported multiple files.
ferm routing.ferm

./round-robin.rb

for prio in 10000 10001; do
	while ip rule del prio $prio; do true; done
done

# Add a number for each PPP interface.
for i in 0 1 2 3 4 5; do
	ip rule add prio 10000 fwmark 0x10$i lookup ppp$i
	ip rule add prio 10001 fwmark 0x10$i lookup null
done

sysctl -w net.ipv4.ip_forward=1
