#!/bin/bash

bundle_install=auto
. /etc/potato/common.sh

export RACK_ENV=production
exec bundle exec unicorn -c /etc/potato/app/unicorn.conf
