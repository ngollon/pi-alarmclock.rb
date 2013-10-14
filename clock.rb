# need 'i2c' gem installed
require "i2c/i2c"
require "i2c/backends/i2c-dev"

module PiAlarmclock
  class Clock
#    include Logging

    # Registers
    HT16K33_REGISTER_DISPLAY_SETUP        = 0x80
    HT16K33_REGISTER_SYSTEM_SETUP         = 0x20
    HT16K33_REGISTER_DIMMING              = 0xE0

    # Blink rate
    HT16K33_BLINKRATE_OFF                 = 0x00
    HT16K33_BLINKRATE_2HZ                 = 0x01
    HT16K33_BLINKRATE_1HZ                 = 0x02
    HT16K33_BLINKRATE_HALFHZ              = 0x03

    # First line 0 - 9, second line A - E
    DIGITS = [ 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F, \
               0x77, 0x7C, 0x39, 0x5E, 0x79, 0x71 ]


    def initialize(address = 0x70, options = {blink_rate: HT16K33_BLINKRATE_OFF, brightness: 15})
      @device = I2C.create('/dev/i2c-1')
      @address = address

      # What does this do?
      @device.write(@address, HT16K33_REGISTER_SYSTEM_SETUP | 0x01, 0x00)

      # set blink rate and brightness
      set_blink_rate(options[:blink_rate])
      set_brightness(options[:brightness])
    end

    def set_time(time, alarm = false)
      if time.nil? then
        (0..3).each { |i| write(i,0) }
        if alarm then
          write(4,0x80)
        else
          write(4,0x00)
        end
      else
        hour = time.hour
        hour_tens = hour / 10
        hour_ones = hour % 10
        minute = time.min
        minute_tens = minute / 10
        minute_ones = minute % 10
  
        write_digit(0, hour_tens)
        write_digit(1, hour_ones)
        set_colon(true)
        write_digit(3, minute_tens)
        write_digit(4, minute_ones, alarm)
      end
    end
     
    def set_blink_rate(rate)
      rate = HT16K33_BLINKRATE_OFF if rate > HT16K33_BLINKRATE_HALFHZ
      @device.write(@address, HT16K33_REGISTER_DISPLAY_SETUP | 0x01 | (rate << 1), 0x00)
    end
 
    def set_brightness(brightness)
      brightness = 15 if brightness > 15      
      @device.write(@address, HT16K33_REGISTER_DIMMING | brightness, 0x00)
    end 

    def write_digit(position, value, dot = false)
      return if position > 7
      return if value > 0xF
      if dot then dot_mask = 1 << 7 else dot_mask = 0 end
      write(position, DIGITS[value] | dot_mask)
    end

    def set_colon(state = false)
      if state then
        write(2,0xF)
      else
        write(2,0x0)
      end
    end

    def clear
      (0...4).each{|n| write(n, 0x00)}
    end
 
    def fill
      (0...4).each{|n| write(n, 0xFF)}
    end
 
    def write(row, value)
       # MAX-COL?
#      value = (value << 8 - 1) | (value >> 1)
      @device.write(@address, row * 2, value & 0xFF)
      @device.write(@address, row * 2 + 1, value >> 8)
    end
  end
end
