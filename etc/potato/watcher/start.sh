#!/bin/bash

. /etc/potato/common.sh

exec bundle exec bin/linkwatch.rb /etc/potato/watcher/config.yml
