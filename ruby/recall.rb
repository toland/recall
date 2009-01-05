require 'rubygems'
gem 'json'

require 'json' 
require 'json/add/core'
require 'json/add/rails'


module Recall
  
  class Client

  	def initialize(host="localhost", port=9900)
  		@host, @port = host, port
  	end

    def connect(who)
      greeting = read
      puts greeting
      response = send_command "CONNECT", who
      puts response
    end

    def reconnect(who)
      disconnect
      connect(who)
    end

    def disconnect
      if !@socket.nil? && !@socket.closed?
        @socket.close
      end
      @socket = nil
    end

    def self.mkcommand(name, token, *args)
      define_method(name.to_s) do |*args|
        send_command token, *args
      end
    end

    mkcommand :echo,          "ECHO",     :what
    mkcommand :create_table,  "MKTABLE",  :name, :fields
    mkcommand :drop_table,    "RMTABLE",  :name
    mkcommand :insert,        "INSERT",   :record
    mkcommand :delete,        "DELETE",   :table, :key
    mkcommand :find,          "FIND",     :table, :key

    def send_command(command, *args)
      cmd = [command, *args].to_json 
      puts cmd
      write cmd
      JSON.parse read
    end

    def socket
      if @socket.nil? || @socket.closed?
        @socket = TCPSocket.new(@host, @port)
      end

      @socket
    end

  protected

    def read
      socket.readline
    end

    def write(what)
      socket.write what
    end

  end

end
