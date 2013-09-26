require_relative 'logging.rb'
require_relative 'switch.rb'

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
      logger.info("Alarm Time: #{@config.whitelist_directory}")
      logger.info("Sunrise Duration: #{@config.greylist_directory}")

	  # Prepare GPIO using the wiringPi binary
      `gpio export 18 out`
	  `gpio pwmr #{2 ** 14}`
	  `gpio -g mode 18 pw`
	  	    
      Process.daemon
      File.open(@config.pidfile, 'w') { |file| file.write(Process.pid) }
    
      logger.info("Process ID: #{Process.pid}")

	  @light_switch = Switch.new(17)
	  @alarm_switch = Switch.new(21)
	  @clock_switch = Switch.new(22)

	  @light_on = @light_switch.on

	  @light_switch.changed do
	    logger.debug("Light switch changed to #{@light_switch.on ? "on" : "off"}")
	    @sunrise_thread.terminate unless @sunrise_thread.nil?
		update_light		
	  end
	  
	  @alarm_switch.on do
	    logger.debug("Alarm switch changed to #{@alarm_switch.on ? "on" : "off"}")	    
	    @alarm_thread = Thread.new ( run_alarm() )
		update_clock
	  end

	  @alarm_switch.off do
	    logger.debug("Alarm switch changed to #{@alarm_switch.on ? "on" : "off"}")	    
	    @alarm_thread.terminate
	    update_clock		
	  end
	  
	  @clock_switch.on do 
		logger.debug("Clock switch changed to #{@clock_switch.on ? "on" : "off"}")	    
	    @clock_thread = Thread.new( run_clock() )
	  end

	  @clock_switch.off do
		logger.debug("Clock switch changed to #{@clock_switch.on ? "on" : "off"}")	    
	    update_clock()
		@clock_thread.terminate
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
	  val = 2 ** 14 if @light_switch.on 
	  `gpio -g pwm 18 #{val}`
	end

	def update_clock
	  # Show current time
	  # Show a dot if alarm is set
	end

	def run_clock
	  loop do		
		update_clock
		sleep(10)
      end
	end

    def run_alarm
	  logger.info("Alarm thread started.")	    
	    
	  loop do
	    # Calculate the next alarm time
	    today = Date.now
	    alarm_time = Time.new(today.year, today.month, today.day) + @config.alarm_time - @config.sunrise_duration
	    if Timw.now > alarm_time then
	      tomorrow = today.next_dat 
	      alarm_time = Time.new(tomorrow.year, tomorrow.month, tomorrow.day) + @config.alarm_time - @config.sunrise_duration
	    end
		logger.info("Next alarm in #{alarm_time - Time.now} seconds at #{Time.at(alarm_time)}.")    	  
	    sleep(alarm_time - Time.now)
	    @sunrise_thread = Thread.new( sunrise() )
	    sleep(1)
	  end
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

