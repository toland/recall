module Recall
  
  class Client

  	def initialize(host="localhost", port=9900)
  		@host, @port = host, port
  	end

    def connect(who)
      greeting = read
      puts greeting
      response = send_command "CONNECT #{who}"
      puts response
    end

    def disconnect
      @socket.close
    end

    def echo(what)
      send_command "ECHO #{what}"
    end

    def send_command(command)
  		write command
  		read
    end

  protected

    def socket
      @socket ||= TCPSocket.new(@host, @port)
    end

    def read
      socket.readline
    end

    def write(what)
      socket.write what
    end

  end

end
