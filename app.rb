require 'sinatra'
require 'tdb'
require 'json'

set :public, File.dirname(__FILE__) + '/public'

get '/stat.js' do
  ppp = Potato::PPP.new

  status = {}
  ifaces = {}
  ppp.interfaces.each do |iface|
    ifaces[iface.name]   = iface.status
    status[:ip_local ] ||= iface.ip_local
    status[:ip_remote] ||= iface.ip_remote
  end

  {
    :status => status,
    :ifaces => ifaces
  }.to_json
end

INTERFACE = /^mlppp[0-2]$/
COMMANDS = {
  'down' => '/sbin/ifdown',
  'up'   => '/sbin/ifup'
}

get '/set/:iface/:mode' do
  iface = params[:iface]
  return "Invalid interface: #{iface}" unless iface =~ INTERFACE

  mode = params[:mode]
  return "Invalid mode: #{mode}" unless command = COMMANDS[mode]

  fork do
    exec('/usr/bin/sudo', command, iface)
    raise 'exec failed'
  end

  'SUCCESS'
end

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
