module Recall
  
  class Connection

  	def initialize(host="localhost", port=9900)
  		@host, @port = host, port
  	end

    def eval(command)
      socket = TCPSocket.new(@host, @port)
  		socket.write(command)
  		result = socket.read
  		socket.close
  		result
    end

  end

end
