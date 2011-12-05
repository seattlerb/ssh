require "ssh"
require 'stringio'

class StringIO
  def readpartial(size) read end # suck!
end

module Process
  def self.expected status
    @@expected ||= []
    @@expected << status
  end

  class << self
    alias :waitpid2_old :waitpid2

    def waitpid2(pid)
      [ @@expected.shift ]
    end
  end
end

module FakePOpen
  attr_accessor :commands, :action, :input, :output, :error

  class Status < Struct.new :exitstatus
    def success?() exitstatus == 0 end
  end

  def popen4 *command
    @commands << command

    @input = StringIO.new
    out    = StringIO.new @output.shift.to_s
    err    = StringIO.new @error.shift.to_s

    raise if block_given?

    status = self.action ? self.action[command.join(' ')] : 0
    Process.expected Status.new(status)

    return 42, @input, out, err
  end

  def select reads, writes, errs, timeout
    [reads, writes, errs]
  end
end

class SSH
  include FakePOpen
end
