#!/bin/bash

. /etc/potato/common.sh

exec bundle exec bin/pinger.rb dsl2
