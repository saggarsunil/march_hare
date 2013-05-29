module HotBunnies
  class Exception < ::StandardError
  end


  class ChannelLevelException < Exception
    attr_reader :channel_close

    def initialize(message, channel_close)
      super(message)

      @channel_close = channel_close
    end
  end

  class ConnectionLevelException < Exception
    attr_reader :connection_close

    def initialize(message, connection_close)
      super(message)

      @connection_close = connection_close
    end
  end


  class PossibleAuthenticationFailureError < Exception

    #
    # API
    #

    attr_reader :username, :vhost

    def initialize(username, vhost, password_length)
      @username = username
      @vhost    = vhost

      super("RabbitMQ closed TCP connection before authentication succeeded: this usually means authentication failure due to misconfiguration or that RabbitMQ version does not support AMQP 0.9.1. Please check your configuration. Username: #{username}, vhost: #{vhost}, password length: #{password_length}")
    end # initialize(settings)
  end # PossibleAuthenticationFailureError


  class PreconditionFailed < ChannelLevelException
  end

  class NotFound < ChannelLevelException
  end

  class ResourceLocked < ChannelLevelException
  end

  class AccessRefused < ChannelLevelException
  end

  class ChannelError < ConnectionLevelException
  end

  class InvalidCommand < ConnectionLevelException
  end

  class FrameError < ConnectionLevelException
  end

  class UnexpectedFrame < ConnectionLevelException
  end



  # Converts RabbitMQ Java client exceptions
  # @private
  class Exceptions
    def self.convert(e, unwrap_io_exception = true)
      case e
      when java.io.IOException then
        c = e.cause

        if unwrap_io_exception
          convert(c, false)
        else
          c
        end
      when com.rabbitmq.client.AlreadyClosedException then
        cmd = e.reason

        puts cmd.method.class.inspect
      when com.rabbitmq.client.ShutdownSignalException then
        cmd = e.reason

        exception_for_protocol_method(cmd.method)
      else
        e
      end
    end

    def self.convert_and_reraise(e)
      raise convert(e)
    end

    def self.exception_for_protocol_method(m)
      case m
      # com.rabbitmq.client.AMQP.Connection.Close does not resolve the inner
      # class correctly. Looks like a JRuby bug we work around by using Rubyesque
      # class name. MK.
      when Java::ComRabbitmqClient::AMQP::Connection::Close then
        exception_for_connection_close(m)
      when Java::ComRabbitmqClient::AMQP::Channel::Close then
        exception_for_channel_close(m)
      else
        NotImplementedError.new("Exception convertion for protocol method #{m.inspect} is not implemented!")
      end
    end # def self


    def self.exception_for_connection_close(m)
      klass = case m.reply_code
              when 320 then
                ConnectionForced
              when 501 then
                FrameError
              when 503 then
                InvalidCommand
              when 504 then
                ChannelError
              when 505 then
                UnexpectedFrame
              else
                raise "Unknown reply code: #{m.reply_code}, text: #{m.reply_text}"
              end

      klass.new("Connection-level error: #{m.reply_text}", m)
    end

    def self.exception_for_channel_close(m)
      klass = case m.reply_code
              when 403 then
                AccessRefused
              when 404 then
                NotFound
              when 405 then
                ResourceLocked
              when 406 then
                PreconditionFailed
              else
                ChannelLevelException
              end

      klass.new(m.reply_text, m)
    end
  end # Exceptions
end # HotBunnies