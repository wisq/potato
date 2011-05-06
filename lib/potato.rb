require 'tdb'

module Potato
  class PPP
    class Interface
      def initialize(data)
        params = data.split(';').map { |p| p.split('=', 2) }.flatten(1)
        @data = Hash[*params]
      end

      def name
        @data['CALL_FILE']
      end

      def status
        if @data['BUNDLE']
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
    end

    class DummyInterface
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
        if handle = db["DEVICE=#{nic}"]
          Interface.new(db[handle])
        else
          DummyInterface.new(dev)
        end
      end.compact
    end

    private

    def db
      @@db ||= TDB.new('/var/run/pppd2.tdb', :open_flags => IO::RDONLY)
    end
  end
end
