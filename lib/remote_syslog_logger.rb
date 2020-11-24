require 'remote_syslog_logger/formatter'
require 'remote_syslog_logger/udp_sender'
require 'logger'

module RemoteSyslogLogger
  VERSION = '1.0.5'

  def self.new(remote_hostname, remote_port, options = {})
    logger_class = options[:logger_class] || Logger
    logger = logger_class.new RemoteSyslogLogger::UdpSender.new(remote_hostname, remote_port, options)
    logger.formatter = options[:formatter] || RemoteSyslogLogger::Formatter.new
    logger
  end
end
