#!/usr/bin/env ruby

require 'yaml'
require 'drb'
require 'set'

$stdout.sync = true # logging

class LinkWatch
  class Hours
    def initialize(spec)
      @start, @stop = spec.split('-').map {|t| parse_daytime(t) }
    end

    def include?(raw_time)
      time = time_to_daytime(raw_time)

      if @stop < @start # spans midnight
        time >= @start || time <= @stop
      else
        time >= @start && time <= @stop
      end
    end

    private

    def parse_daytime(spec)
      hours, minutes, seconds = spec.split(':', 3).map(&:to_i) + [0, 0, 0]
      hours*3600 + minutes*60 + seconds
    end

    def time_to_daytime(time)
      midnight = Time.local(time.year, time.month, time.day)
      time.to_i - midnight.to_i
    end
  end

  class Interface
    def self.for(name)
      if name =~ /^ppp\d+$/
        PPP.new(name)
      else
        NIC.new(name)
      end
    end

    attr_reader :name, :up, :last_seen
    alias_method :up?, :up

    def initialize(name)
      @name = name
    end

    def up=(value)
      @prior_up  = @up
      @up        = value
      @last_seen = Time.now if @up
    end

    def down?
      !up?
    end

    def log_message
      return if @prior_up.nil?

      if up?
        log_up_message if !@prior_up
      else
        log_down_message
      end
    end

    def down_status
      if @last_seen.nil?
        "is #{down_verb}"
      else
        "has been #{down_verb} for #{(Time.now - @last_seen).to_i} seconds"
      end
    end

    def log_up_message
      notify_up_message
    end

    def log_down_message
      notify_down_message
    end

    def notify_message
      first = @last_notified.nil?

      if up?
        return if @last_notified == :up
        return unless notify_up?
        @last_notified = :up
        return if first
        notify_up_message
      else
        return if @last_notified == :down
        return unless notify_down?
        @last_notified = :down
        return if first
        notify_down_message
      end
    end

    def notify_up?
      true
    end
    def notify_down?
      true
    end

    class NIC < Interface
      def down_verb
        "missing"
      end

      def log_down_message
        "Interface #{name} #{down_status}."
      end

      def notify_up_message
        "Interface #{name} is back."
      end

      def notify_down_message
        "Interface #{name} has disappeared!"
      end
    end

    class PPP < Interface
      PPP_TOLERANCE = 120 # seconds

      def down_verb
        "down"
      end

      def notify_delay
      end

      def notify_down?
        return true if @last_seen.nil? # first run, will be ignored
        Time.now >= (@last_seen + PPP_TOLERANCE)
      end

      def notify_up_message
        "PPP link #{name} is back up."
      end

      def notify_down_message
        "PPP link #{name} #{down_status}."
      end
    end
  end

  class Watcher
    def initialize(config_file)
      config    = YAML.load_file(config_file)
      @jabber   = DRbObject.new(nil, config[:druby_uri])
      @watchers = config[:watchers]
      @hours    = config[:hours].map {|h| Hours.new(h)}

      @interfaces = Hash.new
      config[:interfaces].each do |name|
        @interfaces[name] = Interface.for(name)
      end
    end

    def run
      raise "No interfaces to watch" if @interfaces.empty?
      raise "Nobody to notify" if @watchers.empty?

      puts "Linkwatch is running."

      begin
        loop do
          run_loop
          sleep 10
        end
      rescue SignalException
      end

      puts "Linkwatch shutting down."
    end

    private

    def notify_hours?
      @hours.any? {|h| h.include? Time.now }
    end

    def run_loop
      cutoff = Time.now

      File.read('/proc/net/dev').split("\n").drop(2).each do |line|
        name  = line.split(':', 2).first.strip
        iface = @interfaces[name]
        iface.up = true if iface
      end

      messages = []
      statuses = []

      @interfaces.values.each do |iface|
        iface.up = false if iface.last_seen.nil? || iface.last_seen < cutoff

        if log_message = iface.log_message
          puts log_message
        end

        if notify_hours? && notify_message = iface.notify_message
          puts "Sending notification: #{notify_message}"
          @watchers.each do |addr|
            @jabber.deliver(addr, notify_message)
          end
        end
      end
    end
  end
end

LinkWatch::Watcher.new(ARGV.first).run
