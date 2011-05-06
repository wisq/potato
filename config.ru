require 'rubygems'
require 'bundler'

Bundler.require

$LOAD_PATH << File.dirname(__FILE__)
require 'lib/app'
run Sinatra::Application
