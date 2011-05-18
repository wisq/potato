#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'

require 'redis'

$LOAD_PATH << File.dirname(__FILE__) + '/..'
require 'lib/app.rb'

class Pinger
  # Interval between pings; if changed, adjust KEEP.
  INTERVAL = 1
  # Pings will be considered lost if they take more than half a second.
  TIMEOUT = 0.5
  # We show 15sec, 1min, 5min + trend.
  # So we need at least 10 mins of data.
  KEEP_COUNT = 600

  def self.ping(nic)
    puts "Pinger starting."
    pinger = Pinger.new(nic)
    puts "Pinger ready."

    begin
      pinger.ping
    rescue SignalException => e
      raise e unless e.signm == 'SIGHUP'

      puts "SIGHUP received, restarting ping."
      retry
    end
  ensure
    puts "Pinger shutting down."
  end

  def initialize(nic)
    @nic = nic

    @ppp = Potato::PPP.new

    @redis = Redis.new
    @redis_key = "ping-#{nic}"

    @last_status = Time.now.min

    if old_lost = @redis.lindex(@redis_key, 0)
      puts "Resuming old ping with #{old_lost} lost packets."
    end
    @lost = old_lost.to_i
  end

  def ping
    reap_old_pings

    until iface = @ppp.find_by_nic(@nic)
      puts "Interface #{@nic} not attached yet."
      sleep(30)
    end

    target = iface.ip_remote
    device = iface.device

    @last_response = @last_timeout = 0
    launch_ping(target, device)
    launch_timeout

    update_loop
  ensure
    @timeout_thread.kill if @timeout_thread
    @ping_thread.kill if @ping_thread
    Process.kill('TERM', @ping_pid) if @ping_pid

    @timeout_thread = @ping_thread = @ping_pid = nil
  end

  private

  # Reap any old zombie ping processes.
  # If we do this during the ensure, a double-signal
  # can leave zombies lying around.
  def reap_old_pings
    loop { Process.waitpid(-1, Process::WNOHANG) }
  rescue Errno::ECHILD
  end

  def launch_ping(target, device)
    puts "Pinging #{target} on #{device}."

    args = [
      '-i', INTERVAL,
      '-t', 0,
      '-r',
      '-I', device,
      target
    ]

    ping_fh, ping_writer = IO.pipe
    @ping_pid = fork do
      $stdout.reopen(ping_writer)
      $stdin.close

      exec('ping', *args.map(&:to_s))
    end

    @ping_thread = Thread.new do
      offset = 0
      last_seq = 0

      ping_fh.each_line do |line|
        next unless line =~ / icmp_req=(\d+) /
        seq = $1.to_i

        if seq < last_seq
          offset += last_seq + 1
          puts "Ping wraps around: #{last_seq} -> #{seq}"
        end
        last_seq = seq

        ping_result(offset + seq, :response)
      end
    end
  end

  def launch_timeout
    @expected = {1 => Time.now + INTERVAL + TIMEOUT}

    Thread.abort_on_exception = true
    @timeout_thread = Thread.new do
      loop do
        now = Time.now
        @expected.dup.each do |seq, time|
          ping_result(seq, :timeout) if time < now
        end

        if next_timeout = @expected.values.min
          sleep(next_timeout - Time.now)
        else
          sleep(INTERVAL)
        end
      end
    end
  end

  def ping_result(seq, result)
    expect_time = TIMEOUT
    expect_next = true

    case result
    when :timeout
      @lost += 1
      expect_time = 0
      puts "Ping #{seq} timed out."
      @last_timeout = seq
    when :response
      if seq < @last_response
        puts "Ping #{seq} received out of order."
        expect_next = false
      elsif !@expected.has_key?(seq)
        if seq > @last_timeout
          puts "Ping #{seq} received too early, recalibrating timeouts."
        else
          puts "Ping #{seq} received after timeout, recalibrating timeouts."
        end
        @expected.clear
        @last_response = seq
      else
        @last_response = seq
      end
    else
      raise "Unknown ping result: #{result}"
    end

    @expected.delete(seq)
    @expected[seq + 1] = Time.now + INTERVAL + expect_time if expect_next
  end

  def output_status
    return if Time.now.min == @last_status

    if prior = @redis.lindex(@redis_key, 59)
      diff = @lost - prior.to_i
      percent = sprintf('%.2f', diff / 0.6)
      puts "Current loss: #{prior} -> #{@lost} = #{percent}%"
    end

    @last_status = Time.now.min
  end

  def update_loop
    loop do
      sleep(1)
      @redis.lpush(@redis_key, @lost)
      @redis.ltrim(@redis_key, 0, KEEP_COUNT)
    end
  end
end

$stdout.sync = true
Pinger.ping(*ARGV)
