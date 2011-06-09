require 'tdb'
require 'json'
require 'active_support/core_ext/hash/indifferent_access'
require 'yaml'

module Potato
  class Log
    class Entry
      attr_reader :time
      attr_accessor :user, :action, :iface

      def self.unpack(line)
        params = JSON.parse(line).with_indifferent_access
        params[:time] = Time.at(params[:time].to_f)
        new(params)
      end

      def initialize(params)
        @time   = params[:time]
        @user   = params[:user]
        @action = params[:action]
        @iface  = params[:iface]
      end

      def pack
        to_hash.to_json
      end

      def to_hash
        @time ||= Time.now
        {
          :time => @time.to_f,
          :user => @user,
          :action => @action,
          :iface => @iface
        }
      end
    end

    def self.open
      log = self.new
      begin
        yield log
      ensure
        log.close
      end
    end

    def initialize
      @fh = File.open('/var/log/potato/actions.log', 'a+')
    end

    def <<(params)
      line = Entry.new(params).pack
      lock(File::LOCK_EX) do
        @fh.syswrite(line + "\n")
      end
    end

    def last(num)
      lines = []
      lock(File::LOCK_SH) do
        back = 50 * (num + 1)
        size = @fh.stat.size
        back = size if size < back

        @fh.seek(0 - size, IO::SEEK_END)
        @fh.gets # throw away

        while line = @fh.gets
          break unless line =~ /\n$/ # partial line at end
          lines << line
        end
      end

      lines.last(num).map { |l| Entry.unpack(l) }
    end

    def close
      @fh.close
    end

    private

    def lock(mode)
      @fh.flock(mode)
      begin
        yield
      ensure
        @fh.flock(File::LOCK_UN)
      end
    end
  end

  class PPP
    def self.load_round_robin
      @@round_robin = YAML.load_file('/var/local/run/round_robin/status.yml')
    end

    def self.round_robin
      @@round_robin
    end

    class Interface
      def initialize(nic, data)
        params = data.chop.split(';').map { |p| p.split('=', 2) }.flatten(1)
        @nic  = nic
        @data = Hash[*params]
      end

      def name
        @data['CALL_FILE']
      end

      def device
        @data['IFNAME']
      end

      def status
        if ip_remote
          :up
        else
          :busy
        end
      end

      def routing_status
        return :unknown unless PPP.round_robin
        return :isolated if PPP.round_robin[:isolate] == name
        return :balanced if PPP.round_robin[:balance].include?(name)
        return :reserved if PPP.round_robin[:reserve].include?(name)
        return :unknown
      end

      def isolated?
        return true unless PPP.round_robin # assume no ifaces isolated
      end

      def ip_local
        @data['IPLOCAL']
      end

      def ip_remote
        @data['IPREMOTE']
      end

      def to_hash(redis)
        ping = Potato::Ping.new(redis, "ping-#{@nic}")
        pingdata = [15, 60, 300].map do |p|
          percent = ping.percent(p)
          {
            :percent => percent ? sprintf("%.1f%%", (percent * 10).ceil / 10.0) : nil,
            :trend   => ping.trend(p)
          }
        end

        {
          :status    => status,
          :routing   => routing_status,
          :ip_local  => ip_local,
          :ip_remote => ip_remote,
          :pings     => pingdata
        }

      end
    end

    class DummyInterface < Interface
      attr_reader :name

      def initialize(nic, name)
        @nic  = nic
        @name = name
      end

      def status
        :down
      end

      def ip_local
        nil
      end

      def ip_remote
        nil
      end
    end

    NICS = {
      'dsl0' => 'ppp0',
      'dsl1' => 'ppp1',
      'dsl2' => 'ppp2',
      'dsl3' => 'ppp3',
      'dsl4' => 'ppp4',
      'dsl5' => 'ppp5'
    }

    def interfaces
      NICS.map do |nic, name|
        find_by_nic(nic) || DummyInterface.new(nic, name)
      end.compact
    end

    def find_by_nic(nic)
      return unless handle = db["DEVICE=#{nic}"]
      Interface.new(nic, db[handle])
    end

    private

    def db
      @db ||= TDB.new('/var/run/pppd2.tdb', :open_flags => IO::RDONLY)
    end
  end

  class Ping
    def initialize(redis, key)
      @redis = redis
      @key   = key
    end

    def loss(offset, length, maxlen = available)
      return [nil, 0] if offset >= maxlen

      length = [length, maxlen].min
      new  = @redis.lindex(@key, offset)
      old  = @redis.lindex(@key, offset + length)
      loss = new.to_i - old.to_i
      raise "Negative loss: #{old} -> #{new}" if loss < 0

      loss = length if loss > length
      [loss, length]
    end

    def percent(period)
      loss, period = loss(0, period)
      return if loss.nil?
      100.0 * loss / period
    end

    def trend(period)
      avail = available

      new, new_len = loss(0,      period, avail)
      old, old_len = loss(period, period, avail)
      return :unknown if new.nil? || old.nil? || new_len < period || old_len < period

      if new > old
        :up
      elsif new < old
        :down
      else
        :stable
      end
    end

    def available
      @redis.llen(@key)
    end
  end
end
