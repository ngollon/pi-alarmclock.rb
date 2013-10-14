module PiAlarmclock
  class Switch

    MIN_HOLD_TIME = 0.5

    def initialize(port)
      @port = port

      File.open("/sys/class/gpio/export", "w") { |f| f.write("#{@port}") }
      File.open("/sys/class/gpio/gpio#{@port}/direction", "w") { |f| f.write("in") }
      File.open("/sys/class/gpio/gpio#{@port}/edge", "w") { |f| f.write("both") }      

      @high_time = Time.now
      @on_before = false
      File.open("/sys/class/gpio/gpio#{@port}/value", "r") { |f| @on = (f.read(1) == '1') }

      @on_handlers = []
      @off_handlers = []
      @changed_handlers = []

      @monitor_thread = Thread.new { monitor }
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

    def on?
      @on
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
        if value == '1' then
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

    def read_debounced (pin)      
      current_value = pin.read(1)
      pin.rewind
      loop do
        rs, ws, es = IO.select(nil, nil, [pin])
        sleep(0.1)
        new_value = pin.read(1)
        pin.rewind
        if new_value != current_value or @override then
          @override = false
          return new_value
        end  
      end
    end
  end    
end

