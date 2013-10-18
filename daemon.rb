require 'date'
require 'time'
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
	  if File.exists?(@config.pidfile)
	    pid = File.read(@config.pidfile)
		begin
			Process.getpgid( pid )
			abort "Daemon already running with process id #{pid}." 
		rescue Errno::ESRCH
		    logger.warn("Removing old pid file.")
			File.unlink(@config.pidfile)
		end
      end
      
      logger.info("Initializing Pi-Alarmclock.rb, version 0.1")
      logger.info("Alarm Time: #{@config.alarm_time[:hour]}:#{@config.alarm_time[:min]}")
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
      @clock.set_brightness(1)


	  @light_updater = Thread.new { update_light() }
	  @clock_updater = Thread.new { update_clock() }
	  @alarm_updater = Thread.new { update_alarm() }

      @light_on = @light_switch.on

      @light_switch.changed do
        logger.debug("Light switch changed to #{@light_switch.on? ? "on" : "off"}")        
        @light_updater.run
      end
  
      @alarm_switch.changed do
        logger.debug("Alarm switch changed to #{@alarm_switch.on? ? "on" : "off"}")                
		@alarm_switch_on_time = Time.now if @alarm_switch.on?
        @alarm_updater.run
		@clock_updater.run
		@light_updater.run
      end
      
      @clock_switch.changed do
        logger.debug("Clock switch changed to #{@clock_switch.on? ? "on" : "off"}")        
		@clock_updater.run
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
	  loop do
	    # Light can be controlled by the light switch, or the alarm.		
		if @light_switch.on? then
		  logger.debug("Updating light: Light switch on. Going to sleep.")
		  pwm(2 ** 14)
		  sleep
		elsif alarm_active? then		   
		  logger.debug("Updating light: Sunrise. Next update in one second.")
		  fraction = (Time.now - @alarm_start_time) / @config.sunrise_duration
		  fraction = 1 if fraction > 1 
		  pwm((2 ** (14 * fraction)).to_i + 1)
		  sleep(1)
		else		  
		  pwm(0)
		  if @alarm_switch.on? and @alarm_start_time.nil? then	# @alarm_updater has not set @alarm_start_time yet
		    logger.debug("Updating light: Off, @alarm_start_time is nil.")
		    sleep(1)
		  elsif @alarm_switch.on? then
		    logger.debug("Updating light: Off, sleeping #{Time.now - @alarm_start_time} seconds until next alarm.")
		    sleep(Time.now - @alarm_start_time)
		  else
		    logger.debug("Updating light: Off, going to sleep.")
		    sleep
		  end
		end
	  end
    end

    def update_clock
	  loop do
	    # Show alarm time for two seconds after alarm has been switched on
	    if Time.now - @alarm_switch_on_time < 2 then
		  logger.debug("Updating clock: Showing alarm time for two seconds.")
		  @clock.set_time(Time.new(2000, 1, 1, @config.alarm_time[:hour], @config.alarm_time[:min]), true)
		  sleep(2)
		end
        
		if @clock_switch.on? then
          rounded_time = Time.now - Time.now.sec
		  if @last_time != rounded_time then
		    logger.debug("Updating clock: New time is #{rounded_time}.")
		    @clock.set_time(rounded_time, @alarm_switch.on?)
			@last_time = rounded_time
		  end
		  sleep(1)
        else
		  logger.debug("Updating clock: Off, going to sleep.")
          @clock.set_time(nil, @alarm_switch.on?)
		  sleep
        end
	  end
    end

	def update_alarm
	  loop do
	    if @alarm_switch.on? then
		  @alarm_start_time = next_alarm.to_time - @config.sunrise_duration
		  logger.info("Updating alarm: Next alarm at #{next_alarm}, sunrise starts in #{Time.now - @alarm_start_time} seconds")
		  sleep(next_alarm.to_time - Time.now + 1)		  
		else
		  @alarm_start_time = nil
		  logger.info("Updating alarm: Off, going to sleep.")
		  sleep
		end
	  end
	end

	def alarm_active?
	  @alarm_switch.on? and not @alarm_start_time.nil? and @alarm_start_time < Time.now
	end
   
    def next_alarm
      now = DateTime.now
      alarm = alarm_at_day(now)
      alarm = alarm_at_day(now.next_day) if alarm.to_time - @config.sunrise_duration < now.to_time
      alarm
    end

    def alarm_at_day(day)
      DateTime.new(day.year, day.month, day.day, @config.alarm_time[:hour], @config.alarm_time[:min], 0, day.offset)
    end  
	
	def pwm(val)	  
	  return if @last_pwm_value == val

	  logger.debug("Setting light PWM to #{val}")
	  `gpio -g pwm 18 #{val}`
	  @last_pwm_value = val
	end  
  end    
end

