#!/usr/bin/ruby

require_relative 'config.rb'
require_relative 'daemon.rb'

abort "Usage alarmclock.rb <start|stop>" unless ARGV.count == 1 and (ARGV[0] == 'start' || ARGV[0] == 'stop')

daemon = Alarmclock::Daemon.new(Alarmclock::Config)
Alarmclock::Logging.configure(Alarmclock::Config.logfile, Alarmclock::Config.loglevel)

if ARGV[0] == 'start'
  daemon.start
end

if ARGV[0] == 'stop'
  daemon.stop  
end

