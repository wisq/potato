#!/usr/bin/ruby

require 'yaml'
require 'ipaddr'
require 'fileutils'
require 'tempfile'

class RoundRobin
  BASE_PATH   = '/var/local/run/round_robin'
  CONFIG_FILE = BASE_PATH + '/config.yml'
  STATUS_FILE = BASE_PATH + '/status.yml'

  RESERVE = 'rr-reserve'
  ISOLATE = 'rr-isolate'
  BALANCE = 'rr-balance'

  def initialize
    @status  = {
      :isolate => nil,
      :balance => [],
      :reserve => []
    }
    @reserve = {}
  end

  class ConfigError < StandardError; end

  def load_config
    config = YAML.load_file(CONFIG_FILE)
    return unless config && config['reserved']

    config['reserved'].each do |iface, iplist|
      raise ConfigError, "Unknown interface in config: #{iface}" unless iface =~ /^ppp(\d+)$/
      inum = $1.to_i
      raise ConfigError, "Duplicate interface in config: #{iface}" if @reserve.has_key?(inum)

      iplist.each do |ip|
        raise ConfigError, "Non-IPv4 address in config: #{ip}" unless valid_ip?(ip)
      end

      @reserve[inum] = iplist
    end
  rescue Errno::ENOENT
    puts "No configuration file found."
  rescue ConfigError => e
    puts e.message
  end

  def ping
    ifaces = []
    IO.popen('/sbin/ifconfig') do |fh|
      fh.each_line do |line|
        ifaces << $1.to_i if line =~ /^ppp(\d+)\s/
      end
    end
    pids = {}

    ifaces.each do |inum|
      pid = fork do
        $stdout.close
        exec('/bin/ping',
          '-I', "ppp#{inum}",
          '-n',
          '-i', '0.2',
          '-c', '5',
          '-w', '3',
          '209.217.125.201'
        )
        raise 'exec failed'
      end

      pids[pid] = inum
    end

    ifaces = []
    until pids.empty?
      pid  = Process.wait
      inum = pids.delete(pid)
      ifaces << inum if $?.success?
    end

    @interfaces = ifaces
  end

  def route
    ifaces = @interfaces.sort
    abort('No routable interfaces found!') if ifaces.empty?

    iptables(:flush, RESERVE)
    @reserve.each do |inum, addrs|
      reserve(inum, addrs)
      ifaces.delete(inum) or puts "*** WARNING: ppp#{inum} is DOWN. ***"
    end

    isolate(ifaces.first)
    load_balance(ifaces.count > 2 ? ifaces.drop(1) : ifaces)
  end

  def output_status
    dir = File.dirname(STATUS_FILE)
    FileUtils.mkdir_p(dir)

    Tempfile.open('round_robin.yml', dir) do |fh|
      fh.puts @status.to_yaml
      fh.flush

      File.rename(fh.path, STATUS_FILE)
    end

    File.chmod(0644, STATUS_FILE)
  end

  private

  def run_iptables(*args)
    command = ['/sbin/iptables', '-t', 'mangle'] + args
    system(*command)
    abort('iptables failed') unless $?.success?
  end

  def ip_route(*args)
    command = ['/sbin/ip', 'route'] + args
    system(*command)
    abort('ip route failed') unless $?.success?
  end

  def iptables(action, table, value = nil, source = nil)
    case action
    when :flush
      run_iptables('-F', table)
    when :mark
      extra = source ? ['--source', source] : []
      run_iptables('-A', table, '--jump', 'CONNMARK', '--set-mark', "0x#{100 + value}", *extra)
    when :return
      return if value == 1 # 1 in 1
      run_iptables('-A', table, '--match', 'statistic', '--mode', 'nth', '--every', value.to_s, '--jump', 'RETURN')
    else
      raise "Unknown action: #{action}"
    end
  end

  def reserve(num, addrs)
    iface = "ppp#{num}"
    puts "Reserving #{iface} for #{addrs.join(', ')}."
    addrs.each do |addr|
      iptables(:mark, RESERVE, num, addr)
    end
    (@status[:reserve] ||= []) << iface
  end

  def isolate(num)
    iface = "ppp#{num}"
    puts "Isolating on #{iface}."
    iptables(:flush, ISOLATE)
    iptables(:mark,  ISOLATE, num)

    ip_route('replace', 'default', 'dev', "ppp#{num}")

    @status[:isolate] = iface
  end

  def load_balance(nums)
    list = nums.map {|i| "ppp#{i}"}
    puts "Balancing across #{list.join(', ')}."
    iptables(:flush, BALANCE)
    nums.each_with_index do |inum, index|
      iptables(:mark, BALANCE, inum)
      iptables(:return, BALANCE, nums.count - index)
    end

    @status[:balance] = list
  end

  def valid_ip?(ip)
    split = ip.split('.')
    split.count == 4 && split.all? {|o| valid_ip_octet?(o)}
  end

  def valid_ip_octet?(octet)
    octet =~ /^\d+$/ && (0..255).include?(octet.to_i)
  end
end

rr = RoundRobin.new
rr.load_config
rr.ping
rr.route
rr.output_status
