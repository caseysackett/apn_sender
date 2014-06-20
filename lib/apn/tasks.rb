def start_worker
  require 'apn'

  worker = nil

  logger = Logger.new(File.join(Rails.root, 'log', 'apn_sender.log'))
  begin
    worker = APN::Sender.new(:cert_path => ENV['CERT_PATH'],
                             :environment => ENV['ENVIRONMENT'],
                             :app => ENV['APP'],
                             :logger => logger,
                             :use_enhanced_format => ENV['USE_ENHANCED_FORMAT'],
                             :verbose => true)
    worker.logger = logger
    worker.verbose = true
    worker.very_verbose = true
  rescue Exception => e
    logger.error "Error raised while saving user #{e.inspect} #{e.message} #{e.backtrace}"
    raise e
    # abort "set QUEUE env var, e.g. $ QUEUE=critical,high rake resque:work"
  end

  puts "*** Starting worker to send apple notifications in the background from #{worker}"

  worker.work(ENV['INTERVAL'] || 5) # interval, will block
end

# Slight modifications from the default Resque tasks
namespace :apn do
  task :setup
  task :work => :sender
  task :workers => :senders

  desc "Start an APN worker"
  task :sender => :setup do
    start_worker
  end

  desc "Start multiple APN workers. Should only be used in dev mode."
  task :senders do
    threads = []
    logger = Logger.new(File.join(Rails.root, 'log', 'apn_sender.log'))
    ENV['APPS'].split(' ').each do |app|
      logger.error("Starting thread for worker #{app}")
      threads << Thread.new do
        ENV['APP'] = app
        start_worker
      end
    end

    threads.each { |thread| thread.join }
  end
end
