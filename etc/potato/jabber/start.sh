#!/bin/bash

. /etc/potato/common.sh

exec bundle exec bin/jabber_bot.rb /etc/potato/jabber/config.yml
