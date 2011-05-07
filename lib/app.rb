require 'sinatra'
require 'json'
require 'active_support/base64'

require 'lib/potato'

INTERFACE = /^mlppp[0-2]$/
COMMANDS = {
  'up'   => ['/sbin/ifup'],
  'down' => ['/sbin/ifdown', '--force']
}

set :public, File.dirname(__FILE__) + '/../public'

get '/stat.js' do
  ppp = Potato::PPP.new

  status = {}
  ifaces = {}
  ppp.interfaces.each do |iface|
    ifaces[iface.name]   = iface.status
    status[:ip_local ] ||= iface.ip_local
    status[:ip_remote] ||= iface.ip_remote
  end

  cutoff = Time.now - 600
  log = Potato::Log.new.last(10).select { |l| l.time >= cutoff }.map { |e| e.to_hash }

  {
    :status => status,
    :ifaces => ifaces,
    :log => log
  }.to_json
end

get '/admin/check/:mode' do
  return "Not logged in" unless user = http_user

  mode = params[:mode]
  return "Invalid mode: #{mode}" unless ['in', 'out'].include?(mode)

  Potato::Log.open do |log|
    log << {:user => user, :action => mode}
  end

  'SUCCESS'
end

get '/admin/set/:iface/:mode' do
  return "Not logged in" unless user = http_user

  iface = params[:iface]
  return "Invalid interface: #{iface}" unless iface =~ INTERFACE

  mode = params[:mode]
  return "Invalid mode: #{mode}" unless command = COMMANDS[mode]

  Potato::Log.open do |log|
    log << {:user => user, :action => mode, :iface => iface}
  end

  fork do
    exec('/usr/bin/sudo', *(command + [iface]))
    raise 'exec failed'
  end

  'SUCCESS'
end

def http_user
  auth = request.env['HTTP_AUTHORIZATION']
  return if auth.nil?

  auth = auth.split(' ', 2).last
  user, pass = ActiveSupport::Base64.decode64(auth).split(':', 2)
  raise "Invalid username: #{user}.inspect" unless user =~ /^[A-Za-z0-9]+$/
  user
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
