require_relative 'logging.rb'

module PiAlarmclock
  class Switch
    include Logging

	MIN_HOLD_TIME = 0.5

	def initialize(port_number)
	  @port = port_number
	  File.open("/sys/class/gpio/export", "w") { |f| f.write("#{@port}") }
	  File.open("/sys/class/gpio/gpio#{@port}/direction", "w") { |f| f.write("in") }
	  File.open("/sys/class/gpio/gpio#{@port}/edge", "w") { |f| f.write("both") }	  

	  @high_time = Time.now
	  @on_before = false
	  File.open("/sys/class/gpio/gpio#{@port}/value", "r") { |f| @on = (|f|.read(1) == 1) }

	  @on_handlers = []
	  @off_handlers = []
	  @changed_handlers = []

	  Thread.new( monitor() )
	end

	def set_on
	  return if @on 
	  @on = true
	  @on_before = true
	  @override = true
	  @on_handlers.each { |h| h.call }
      @changed_handlers.each { |h| h.call }
	end

	def set_off
	  return if not @on 
	  @on = false
	  @on_before = false
	  @override = true
	  @off_handlers.each { |h| h.call }
      @changed_handlers.each { |h| h.call }
	end

	def on(method=nil, &block)		
	  if method then
	    method.call if @on
		@on_handlers << method
	  end
	  if block
	    block.call if @on
        @on_handlers << block
	  end
	end

	def off(method=nil, &block)		
	  if method then
	    method.call if not @on
		@off_handlers << method
	  end
	  if block
	    block.call if not @on
        @off_handlers << block
	  end
	end

	def changed(method=nil, &block)		
	  if method then
	    @changed_handlers << method
	  end
	  if block
	    @changed_handlers << block
	  end
	end

	def monitor
	  pin = File.open("/sys/class/gpio/gpio#{@port}/value", "r")
      loop do
		value = read_debounced(pin)
		if value == 1 then
		  # clock switch is on, so show the clock and remember this time
		  @high_time = Time.now
		  @on_before = @on
		  @on = true		  
		  @on_handlers.each { |h| h.call }
          @changed_handlers.each { |h| h.call }
		else
		  # Depressed, check if it was held or just pressed
		  if Time.now - @high_time > MIN_HOLD_TIME or @on_before then
		    @on = false		
			@off_handlers.each { |h| h.call }
			@changed_handlers.each { |h| h.call }		  		
		  end
		end	
	  end
	end	

	def read_debounced (file)
	  currentValue = file.read(1)
	  loop do
	    rs, ws, es = IO.select(nil, nil, [file])
		sleep(0.05)
	    if es
	    	r = es[0]
			newValue = r.read(1)
			if newValue != currentValue or @override then
			  @override = false
			  return newValue
            end  
	    else
	    	puts "timeout"
	    end
	  end
	end
  end    
end

