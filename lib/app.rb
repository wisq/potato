require 'sinatra'
require 'redis'
require 'json'
require 'active_support/base64'

require 'lib/potato'

INTERFACE = /^ppp\d$/
COMMANDS = {
  'up'   => ['/sbin/ifup'],
  'down' => ['/sbin/ifdown', '--force']
}

set :public, File.dirname(__FILE__) + '/../public'

get '/stat.js' do
  Potato::PPP.load_round_robin

  $ppp   ||= Potato::PPP.new
  $redis ||= Redis.new

  status = {}
  ifaces = {}
  $ppp.interfaces.each do |iface|
    ifaces[iface.name] = iface.to_hash($redis)
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
