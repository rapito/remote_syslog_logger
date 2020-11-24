module RemoteSyslogLogger
	class Formatter
		# Formatters get the formatted level from the logger.
		LEVEL_SEVERITY_MAP = {
				"DEBUG" => :debug,
				"INFO" => :info,
				"WARN" => :warn,
				"ERROR" => :error,
				"FATAL" => :fatal,
				"UNKNOWN" => :unknown
		}
		SEVERITY_MAP = {
				'FATAL' => 'emerg',
				'ALERT' => 'alert',
				'CRITICAL' => 'crit',
				'ERROR' => 'err',
				'WARN' => 'warn',
				'UNKNOWN' => 'notice',
				'INFO' => 'info',
				'DEBUG' => 'debug'
		}
		EMPTY_ARRAY = []

		private

		def call(severity, timestamp, progname, msg)
			build_log_entry severity, timestamp, progname, msg
		end

		def build_log_entry(severity, time, progname, logged_obj)
			level = LEVEL_SEVERITY_MAP.fetch(severity)
			mapped_severity = SEVERITY_MAP.fetch(severity)
			tags = extract_active_support_tagged_logging_tags

			if logged_obj.is_a?(Hash)
				# Extract the tags
				tags = tags.clone
				tags.push(logged_obj.delete(:tag)) if logged_obj.key?(:tag)
				tags.concat(logged_obj.delete(:tags)) if logged_obj.key?(:tags)
				tags.uniq!

				message = logged_obj.delete(:message)

				LogEntry.new(level, mapped_severity, time, progname, message, tags: tags)
			else
				LogEntry.new(level, mapped_severity, time, progname, logged_obj, tags: tags)
			end
		end

		# Because of all the crazy ways Rails has attempted tags, we need this crazy method.
		def extract_active_support_tagged_logging_tags
			Thread.current[:activesupport_tagged_logging_tags] ||
					Thread.current[tagged_logging_object_key_name] ||
					EMPTY_ARRAY
		end

		def tagged_logging_object_key_name
			@tagged_logging_object_key_name ||= "activesupport_tagged_logging_tags:#{object_id}"
		end
	end

	class LogEntry #:nodoc:
		BINARY_LIMIT_THRESHOLD = 1_000.freeze
		DT_PRECISION = 6.freeze
		MESSAGE_MAX_BYTES = 8192.freeze

		attr_reader :event, :level, :severity, :message, :progname, :tags, :time

		# Creates a log entry suitable to be sent to the Timber API.
		# @param level [Integer] the log level / severity
		# @param severity [Integer] the log level severity
		# @param time [Time] the exact time the log message was written
		# @param progname [String] the progname scope for the log message
		# @param message [String] Human readable log message.
		# @return [LogEntry] the resulting LogEntry object
		def initialize(level, severity, time, progname, message, event, options = {})
			@level = level
			@severity = severity
			@time = time.utc
			@progname = progname

			# If the message is not a string we call inspect to ensure it is a string.
			# This follows the default behavior set by ::Logger
			# See: https://github.com/ruby/ruby/blob/trunk/lib/logger.rb#L615
			@message = message.is_a?(String) ? message : message.inspect
			@message = @message.byteslice(0, MESSAGE_MAX_BYTES)
			@tags = options[:tags]
		end

		# Builds a hash representation containing simple objects, suitable for serialization (JSON).
		def to_hash(options = {})
			options ||= {}
			hash = {
					:level => level,
					:dt => formatted_dt,
					:message => message
			}

			if !tags.nil? && tags.length > 0
				hash[:tags] = tags
			end

			if !event.nil?
				hash.merge!(event)
			end

			if !context_snapshot.nil? && context_snapshot.length > 0
				hash[:context] = context_snapshot
			end

			if options[:only]
				hash.select do |key, _value|
					options[:only].include?(key)
				end
			elsif options[:except]
				hash.select do |key, _value|
					!options[:except].include?(key)
				end
			else
				hash
			end
		end

		def inspect
			to_s
		end

		def to_json(options = {})
			to_hash.to_json
		end

		def to_msgpack(*args)
			to_hash.to_msgpack(*args)
		end

		# This is used when LogEntry objects make it to a non-Timber logger.
		def to_s
			message + "\n"
		end

		private

		def formatted_dt
			@formatted_dt ||= time.iso8601(DT_PRECISION)
		end

		# Attempts to encode a non UTF-8 string into UTF-8, discarding invalid characters.
		# If it fails, a nil is returned.
		def encode_string(string)
			string.encode('UTF-8', {
					:invalid => :replace,
					:undef => :replace,
					:replace => '?'
			})
		rescue Exception
			nil
		end
	end

end
