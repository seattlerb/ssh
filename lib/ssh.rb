require 'rubygems'
require 'open4'

##
# SSH provides a simple streaming ssh command runner. That's it.
# This is a one trick pony.
#
#   ssh = SSH.new "example.com", "/var/log"
#   puts ssh.run "ls"
#
# SSH was extracted from rake-remote_task which was extracted from vlad.
#
# SSH's idea contributed by Joel Parker Henderson.

class SSH
  VERSION = "1.1.0"

  class Error < RuntimeError; end

  class CommandFailedError < Error
    attr_reader :status
    def initialize status
      @status = status
    end
  end

  include Open4

  attr_accessor :ssh_cmd, :ssh_flags, :target_host, :target_dir
  attr_accessor :sudo_prompt, :sudo_password

  def initialize target_host = nil, target_dir = nil
    self.ssh_cmd       = "ssh"
    self.ssh_flags     = []
    self.target_host   = target_host
    self.target_dir    = target_dir

    self.sudo_prompt   = /^Password:/
    self.sudo_password = nil
  end

  def run command
    command = "cd #{target_dir} && #{command}" if target_dir
    cmd     = [ssh_cmd, ssh_flags, target_host, command].flatten

    if $DEBUG then
      trace = [ssh_cmd, ssh_flags, target_host, "'#{command}'"]
      warn trace.flatten.join ' '
    end

    pid, inn, out, err = popen4(*cmd)

    status, result = empty_streams pid, inn, out, err

    unless status.success? then
      e = status.exitstatus
      c = cmd.join ' '
      raise(CommandFailedError.new(status), "Failed with status #{e}: #{c}")
    end

    result.join
  ensure
    inn.close rescue nil
    out.close rescue nil
    err.close rescue nil
  end

  def empty_streams pid, inn, out, err
    result  = []
    inn.sync   = true
    streams    = [out, err]
    out_stream = {
      out => $stdout,
      err => $stderr,
    }

    # Handle process termination ourselves
    status = nil
    Thread.start do
      status = Process.waitpid2(pid).last
    end

    until streams.empty? do
      # don't busy loop
      selected, = select streams, nil, nil, 0.1

      next if selected.nil? or selected.empty?

      selected.each do |stream|
        if stream.eof? then
          streams.delete stream if status # we've quit, so no more writing
          next
        end

        data = stream.readpartial(1024)
        out_stream[stream].write data

        if stream == err and data =~ sudo_prompt then
          inn.puts sudo_password
          data << "\n"
          $stderr.write "\n"
        end

        result << data
      end
    end

    return status, result
  end
end
