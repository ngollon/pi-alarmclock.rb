require 'date'
require './logging.rb'
require './switch.rb'
require './clock.rb'

module PiAlarmclock
  class Daemon
    include Logging

    MIN_HOLD_TIME = 0.5

    def initialize(config)
      @config = config
    end

    def start
      abort "Daemon already running. Check the pidfile at #{@config.pidfile}" if File.exists?(@config.pidfile)
      
      logger.info("Initializing Pi-Alarmclock.rb, version 0.1")
      logger.info("Alarm Time: #{@config.alarm_time}")
      logger.info("Sunrise Duration: #{@config.sunrise_duration}")

      # Prepare GPIO using the wiringPi binary
      `gpio export 18 out`
      `gpio pwmr #{2 ** 14}`
      `gpio -g mode 18 pwm`
              
      Process.daemon
      File.open(@config.pidfile, 'w') { |file| file.write(Process.pid) }
    
      logger.info("Process ID: #{Process.pid}")

      @light_switch = Switch.new(17)
      @alarm_switch = Switch.new(27)
      @clock_switch = Switch.new(22)

      @clock = PiAlarmclock::Clock.new
      @clock.clear

      @light_on = @light_switch.on

      @light_switch.changed do
        logger.debug("Light switch changed to #{@light_switch.on? ? "on" : "off"}")
        @sunrise_thread.terminate unless @sunrise_thread.nil?
        update_light        
      end
  
      @alarm_switch.on do
        logger.debug("Alarm switch changed to #{@alarm_switch.on? ? "on" : "off"}")        
        @alarm_thread = Thread.new { run_alarm() }
        update_clock
      end

      @alarm_switch.off do
        logger.debug("Alarm switch changed to #{@alarm_switch.on? ? "on" : "off"}")        
        @alarm_thread.terminate unless @alarm_thread.nil?
        update_clock        
      end

      @clock_switch.changed do
        logger.debug("Clock switch changed to #{@clock_switch.on? ? "on" : "off"}")        
        if @clock_switch.on? then
          @clock_thread = Thread.new { run_clock() }
        else
          update_clock()
          @clock_thread.terminate unless @clock_thread.nil?
        end 
      end
      
      sleep  
    end

    def stop
      abort "No running process found" if not File.exists?(@config.pidfile)
      pid = File.read(@config.pidfile)
      logger.info("Stopping Daemon with process id: #{pid}")
      begin
        File.unlink(@config.pidfile)        
        Process.kill(9, Integer(pid))
      rescue Exception => msg
        logger.error("Process probably not running, message: #{msg}")
      end     
    end    
    
    def update_light
      val = 0
      val = 2 ** 14 if @light_switch.on?
      `gpio -g pwm 18 #{val}`
    end

    def update_clock
      return if @override_clock 
      # Show current time
      # Show a dot if alarm is set
      if @clock_switch.on? then 
        @clock.set_time(Time.now, @alarm_switch.on?)
      else
        @clock.set_time(nil, @alarm_switch.on?)
      end
    end

    def run_clock
      loop do        
        update_clock
        sleep(1)
      end
    end

    def run_alarm
      logger.info("Alarm thread started.")        
      @override_clock = true
      clock.set_time(Time.new(2100, 1, 1, @config.alarm_time[:hour], @config.alarm_time[:min]), true)
      sleep(2)
      @override_clock = false
      update_clock

      loop do
        # Calculate the next alarm time
        alarm_time = next_alarm
        seconds_to_alarm = (alarm_time - now) * 24 * 60 * 60;
        logger.info("Next alarm in #{seconds_to_alarm} seconds at #{alarm_time}.")          
        sleep(seconds_to_alarm)
        @sunrise_thread = Thread.new( sunrise() )
        sleep(10)
      end
    end

    def next_alarm
      now = DateTime.now
      alarm = alarm_at_day(now)
      alarm = alarm_at_day(now.next_day) if alarm < now
      alarm
    end

    def alarm_at_day(day)
      DateTime.new(day.year, day.month, day.day, @config.alarm_time[:hour], @config.alarm_time[:min])
    end

    def sunrise
      start_time = Time.now
      logger.info("Sunrise started.")
      runtime = 0
      while (runtime < @config.sunrise_duration) do
        runtime = Time.now - start_time
        fraction = runtime / @config.sunrise_duration
        pwm = (2 ** (14 * fraction)).to_i + 1
        `gpio -g pwm 18 #{pwm}`
        sleep(0.1)
      end
      logger.info("Sunrise complete.")
    end
  end    
end

