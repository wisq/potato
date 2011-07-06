#!/usr/bin/env ruby

# This code is designed to run a generic outbound-only Jabber bot.
# The test_blame2jabber script can be used to connect to this
# and send messages to individual users when CI builds fail.
#
# The xmpp4r-simple gem is required.
#
# Usage: jabber-bot <config.yml>
#
# Example config.yml file:
#
# :jabber_id: my.bot@gmail.com
# :password:  my.bot.password
# :druby_uri: druby://localhost:5223

require 'drb'
require 'yaml'
require 'timeout'

require 'rubygems'
require 'xmpp4r'
require 'xmpp4r/roster'

$stdout.sync = true # logging

class JabberBot
  def self.launch_config(file)
    config = YAML.load_file(file)
    launch(config[:jabber_id], config[:password], config[:druby_uri])
  end

  def self.launch(jabber_id, password, druby_uri)
    client = Client.new(jabber_id)
    server = Server.new(client, druby_uri)
    
    puts "JabberBot is starting."

    Thread.abort_on_exception = true
    client.start(password)
    server.start

    puts "JabberBot is ready."

    server.thread.join
    
    puts "JabberBot is exiting."
  end
end

class JabberBot::Client
  attr_reader :thread

  def initialize(jabber_id)
    @jabber_id = Jabber::JID.new(jabber_id)
    @deferred = {}
    @pending  = []
  end

  def start(password)
    @monitor_thread = Thread.new do
      sleep(3)
      loop do
        unless connected?
          begin
            connect(password)
          rescue StandardError => e
            puts "Unable to connect: #{e.inspect}"
          end
        end
        sleep(60)
      end
    end
    
    @delivery_thread = Thread.new do
      next_send = Time.now
      loop do
        until Time.now >= next_send
          sleep(next_send - Time.now + 0.1) # resist Thread.wakeup calls
        end

        if !@pending.empty? && connected?
          msg = @pending.shift
          if msg
            deliver_message(msg)
            next_send = Time.now + 1.0
            next
          end
        end
        
        sleep(60) # if not connected or nothing to send
      end
    end
  end

  def connect(password)
    puts "Connecting to Jabber server."
    @jabber = Jabber::Client.new(@jabber_id)
    @jabber.connect
    @jabber.auth(password)
    @jabber.send(Jabber::Presence.new.set_type(:available))
    @roster = Jabber::Roster::Helper.new(@jabber)

    @jabber.add_message_callback do |msg|
      message_received(msg)
    end
    @roster.add_subscription_request_callback do |roster_item, presence|
      @roster.accept_subscription(presence.from)
    end

    @roster.add_subscription_callback do |roster_item, presence|
      flush_deferred_queue(presence.from)
    end
    @roster.add_update_callback do |roster_item, presence|
      flush_deferred_queue(presence.jid)
    end
    
    @connected = true
    puts "Connected."
    @delivery_thread.wakeup
  end

  def deliver(jid, body)
    jid = Jabber::JID.new(jid) unless jid.respond_to?(:resource)
    msg = Jabber::Message.new(jid, body)
    msg.type = :chat

    add_pending([msg])
  end
  
  private
  
  def connected?
    return false unless @connected && @jabber.is_connected?
    if ping?
      true
    else
      puts "Ping timed out, disconnecting."
      @jabber.close!
      @connected = false
    end
  end
  
  def ping?
    iq = Jabber::Iq.new(:get, @jabber.jid.domain)
    iq.from = @jabber.jid
    ping = iq.add(REXML::Element.new('ping'))
    ping.add_namespace 'urn:xmpp:ping'

    begin
      Timeout.timeout(10) do
        reply = @jabber.send_with_id(iq)
        return reply.kind_of?(Jabber::Iq) && reply.type == :result
      end
    rescue Timeout::Error; end
    false
  end
  
  def add_pending(msgs)
    @pending += msgs
    @delivery_thread.wakeup
  end
  
  def deliver_message(msg)
    jid = msg.to
    if subscribed_to?(jid)
      send_message(msg)
    else
      (@deferred[jid] ||= []) << msg
      add_contact(jid)
    end
  end

  def send_message(msg)
    @jabber.send(msg)
    puts "Sent message to #{msg.to}: #{msg.body.inspect}"
  end
  
  def subscribed_to?(jid)
    if item = @roster.items[jid]
      [:to, :both].include?(item.subscription)
    else
      false
    end
  end

  def add_contact(jid)
    request = Jabber::Presence.new
    request.type = :subscribe
    request.to   = jid
    @jabber.send(request)
  end

  def flush_deferred_queue(jid)
    return unless subscribed_to?(jid)
    add_pending(@deferred.delete(jid) || [])
  end
  
  def message_received(msg)
    if msg.type == :error
      deliver(msg.from, msg.body)
    else
      puts "Received #{msg.type.inspect} message from #{msg.from}: #{msg.body.inspect}"
    end
  end
end

class JabberBot::Server
  def initialize(client, uri)
    @client = client
    @uri    = uri
  end

  def start
    DRb.start_service(@uri, self)
  end

  def thread
    DRb.thread
  end

  def deliver(email, message)
    @client.deliver(email, message)
  end
end

JabberBot.launch_config(*ARGV)
