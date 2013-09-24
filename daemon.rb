require_relative 'logging.rb'

module PiAlarmclock
  class Daemon
    include Logging

    def initialize(config)
      @config = config
    end

    def start
      abort "Daemon already running. Check the pidfile at #{@config.pidfile}" if File.exists?(@config.pidfile)
      
      logger.info("Initializing Pi-Alarmclock.rb, version 0.1")
      logger.info("Alarm Time: #{@config.whitelist_directory}")
      logger.info("Sunrise Duration: #{@config.greylist_directory}")

	  # Prepare GPIO using the wiringPi binary
      # ...	  

	  # Configure switch IO ports for use as edge triggered interrupts
	  File.open("/sys/class/gpio/gpio17/edge", "w") { |f| f.write("both") }
	  File.open("/sys/class/gpio/gpio21/edge", "w") { |f| f.write("both") }
	  File.open("/sys/class/gpio/gpio22/edge", "w") { |f| f.write("both") }
	
      Process.daemon
      File.open(@config.pidfile, 'w') { |file| file.write(Process.pid) }
    
      logger.info("Process ID: #{Process.pid}")

      Thread.new( monitor_lightswitch() )
	  Thread.new( monitor_alarmswitch() )
	  Thread.new( monitor_clockswitch() )

	  loop do
		# Check for alarm time, and call sunrise if needed
	  end
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

	def monitor_lightswitch
	  gpio17 = File.open("/sys/class/gpio/gpio17/value", "r")
      loop do
		value = read(gpio17)		
	  end
	end

	def monitor_alarmswitch
	  gpio21 = File.open("/sys/class/gpio/gpio21/value", "r")
      loop do
		value = read(gpio21)		
	  end
	end

	def monitor_clockswitch
	  gpio22 = File.open("/sys/class/gpio/gpio22/value", "r")
      loop do
		value = read(gpio22)		
	  end
	end

	def read (file)
	  loop dp 
	    rs,ws,es = IO.select(nil, nil, [file])
	    if es
	    	r = es[0]
	    	return r.read(1)
	    else
	    	puts "timeout"
	    end
	  end
	end

	def update_clock
	   loop do
		 # Get current time and send to display via I2C
		 sleep(10)
	   end
	end

	def sunrise
	  start_time = Time.now
	  runtime = 0
	  while (runtime < @config.sunrise_duration) do
	    runtime = Time.now - start_time
		fraction = runtime / @config.sunrise_duration
		pwm = (2 ** (14 * fraction)).to_i
		# Set PWM for GPIO 18 to pwm
	  end 
	end
  end    
end

