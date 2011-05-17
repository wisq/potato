require 'tdb'
require 'json'
require 'active_support/core_ext/hash/indifferent_access'

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
    class Interface
      def initialize(data)
        params = data.chop.split(';').map { |p| p.split('=', 2) }.flatten(1)
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

      def ip_local
        @data['IPLOCAL']
      end

      def ip_remote
        @data['IPREMOTE']
      end

      def to_hash
        {
          :status    => status,
          :ip_local  => ip_local,
          :ip_remote => ip_remote
        }
      end
    end

    class DummyInterface < Interface
      attr_reader :name

      def initialize(name)
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
      'dsl0' => 'mlppp0',
      'dsl1' => 'mlppp1',
      'dsl2' => 'mlppp2'
    }

    def interfaces
      NICS.map do |nic, dev|
        find_by_nic(nic) || DummyInterface.new(dev)
      end.compact
    end

    def find_by_nic(nic)
      return unless handle = db["DEVICE=#{nic}"]
      Interface.new(db[handle])
    end

    private

    def db
      @db ||= TDB.new('/var/run/pppd2.tdb', :open_flags => IO::RDONLY)
    end
  end
end
