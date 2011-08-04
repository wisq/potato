Potato
======

Potato is a router system designed to load-balance across an arbitrary number of PPPoE DSL links (the more, the better).

Features:

 * dirt simple web interface
 * continuous link health monitoring via pings
 * automatic selection of links to be used
 * a Jabber notification system on link failure
 * an "isolated" link for high priority traffic
 * "reserved" links assigned to specific machines
 * a biodegradable mascot

License
-------

Potato is to be considered released into the public domain.

Installation
------------

So far, we only know of one Potato installation (our own), and we expect it to be decommissioned within a few months.  It's served us very well, but we're upgrading to fibre and won't be needing it any more.

The Potato code is thus being provided on an "as is" basis, rather than as a packaged whole with a tested installation procedure.

Required packages:

 * ruby
 * pppd
 * iproute2
 * ferm
 * runit

Recommended:

 * RVM [https://rvm.beginrescueend.com/]
 * a basic knowledge of RVM and deploying Ruby apps

I've done my best to provide examples of all the relevant configuration files in the "etc" directory:

 * etc/firewall contains the Potato firewalling framework, which does the actual routing
 * etc/firewall/round-robin.rb is the script that dynamically chooses what links to use
 * etc/potato contains all the runit services and the usb-nic script (for lack of a better place)
 * etc/ppp contains PPP configuration and scripts to hook Potato into pppd
 * etc/iproute2 contains a "null" routing table and one table per interface
 * etc/network/interfaces contains the ifup/ifdown definitions for PPP interfaces
 * etc/nginx contains a basic nginx config to access the Potato app
 * etc/udev contains udev rules to match, rename, and trigger scripts for DSL interfaces
 * etc/cron.daily contains a script to reset the round-robin config (to automatically un-reserve links)

These files are designed to be copied into your own /etc, but if the file already exists, please merge them sensibly with your own file (and back it up).

Our copy of the web app itself resides in /usr/local/potato/app, but if you're familiar with Capistrano, you may prefer that approach; just update the relative paths and possibly the RVM config.

There's also theoretically nothing preventing the use of a system-wide Ruby instead of RVM.

Please feel free to contact me if you need any more info or if I've missed anything.  https://github.com/wisq
