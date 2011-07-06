#!/usr/bin/env ruby

require 'yaml'
require 'drb'
require 'set'

PPP_TOLERANCE = 5 # minutes

$stdout.sync = true # logging

config     = YAML.load_file(ARGV.first)
jabber     = DRbObject.new(nil, config[:druby_uri])
interfaces = Set.new(config[:interfaces])
watchers   = config[:watchers]

abort "No interfaces to watch" if interfaces.empty?
abort "Nobody to notify" if watchers.empty?

puts "Linkwatch is running."

last_seen = Hash.new

begin
  loop do
    ifaces_now = Set.new(File.read('/proc/net/dev').split("\n").drop(2).map do |line|
      line.split(':', 2).first.strip
    end)

    (interfaces & ifaces_now).each do |iface|
      last_seen[iface] = Time.now
    end

    last_seen.each do |iface, last_time|
      is_ppp = iface =~ /^ppp\d+$/

      delta     = (Time.now - last_time).round
      tolerance = is_ppp ? PPP_TOLERANCE*60 : 10

      if delta >= tolerance
        message =
          if is_ppp
            "PPP link #{iface} has been down for #{PPP_TOLERANCE} minutes."
          else
            "Interface #{iface} has disappeared!"
          end

        puts message
        watchers.each do |addr|
          jabber.deliver(addr, message)
        end

        last_seen.delete(iface)
      elsif !ifaces_now.include?(iface)
        puts "Link #{iface} is down, will notify in #{tolerance - delta} seconds."
      end
    end

    sleep 10
  end
rescue SignalException
end

puts "Linkwatch shutting down."
