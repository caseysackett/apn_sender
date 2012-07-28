module APN
  # Subclass of Resque::Worker which initializes a single TCP socket on creation to communicate with Apple's Push Notification servers.
  # Shares this socket with each child process forked off by Resque to complete a job. Socket is closed in the before_unregister_worker
  # callback, which gets called on normal or exceptional exits.
  #
  # End result: single persistent TCP connection to Apple, so they don't ban you for frequently opening and closing connections,
  # which they apparently view as a DOS attack.
  #
  # Accepts <code>:environment</code> (production vs anything else) and <code>:cert_path</code> options on initialization.  If called in a 
  # Rails context, will default to RAILS_ENV and RAILS_ROOT/config/certs. :environment will default to development.  
  # APN::Sender expects two files to exist in the specified <code>:cert_path</code> directory: 
  # <code>apn_production.pem</code> and <code>apn_development.pem</code>.
  #
  # If a socket error is encountered, will teardown the connection and retry again twice before admitting defeat.
  class Sender < ::Resque::Worker
    include APN::Connection::Base
    TIMES_TO_RETRY_SOCKET_ERROR = 2
    IO_SELECT_WAIT = 2

    # Send a raw string over the socket to Apple's servers (presumably already formatted by APN::Notification)
    def send_to_apple( notification, attempt = 0 )
      if attempt > TIMES_TO_RETRY_SOCKET_ERROR
        log_and_die("Error with connection to #{apn_host} (retried #{TIMES_TO_RETRY_SOCKET_ERROR} times): #{error}")
      end

      log(:info, "Sending notification with token: #{notification.token}") if @opts[:verbose]
      log(:info, "Sending notification with options: #{notification.options}") if @opts[:verbose]
      log(:info, "Sending notification with packaged message: #{notification.packaged_message}") if @opts[:verbose]

      if @opts[:use_enhanced_format]
        self.socket.write( notification.enhanced_packaged_notification )

        read, write, error = IO.select([self.socket], nil, [self.socket], IO_SELECT_WAIT)
        if !error.nil? && !error.first.nil?
          log(:error, "Error with connection to #{apn_host} (attempt #{attempt})")
          teardown_connection
          setup_connection
          send_to_apple(notification, attempt + 1)
        end

        if !read.nil? && !read.first.nil?
          error_response = self.socket.read_nonblock(6)
          log(:error, "Error returned: #{error_response}")
          teardown_connection
          setup_connection
        end
      else
        self.socket.write( notification.to_s )
      end
      log(:info, "Finished sending notification string to apple") if @opts[:verbose]

    rescue SocketError => error
      log(:error, "Error with connection to #{apn_host} (attempt #{attempt}): #{error}")
      
      # Try reestablishing the connection
      teardown_connection
      setup_connection
      send_to_apple(notification, attempt + 1)
    end
    
    protected
    
    def apn_host
      @apn_host ||= apn_production? ? "gateway.push.apple.com" : "gateway.sandbox.push.apple.com"
    end
    
    def apn_port
      2195
    end

  end

end
