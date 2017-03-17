require 'active_support/concern'

module RocketJob
  module Plugins
    module Job
      # Rocket Job Throttling Framework.
      #
      # Example:
      #   # Do not run this job when the MySQL slave delay exceeds 5 minutes.
      #   class MyJob < RocketJob
      #     # Define a custom mysql throttle
      #     # Prevents all jobs of this class from running on the current server.
      #     define_throttle :mysql_throttle_exceeded?
      #
      #     def perform
      #       # ....
      #     end
      #
      #     private
      #
      #     # Returns true if the MySQL slave delay exceeds 5 minutes
      #     def mysql_throttle_exceeded?
      #       status        = ActiveRecord::Base.connection.connection.select_one('show slave status')
      #       seconds_delay = Hash(status)['Seconds_Behind_Master'].to_i
      #       seconds_delay >= 300
      #     end
      #   end
      module Throttle
        extend ActiveSupport::Concern

        included do
          class_attribute :rocket_job_throttles
          self.rocket_job_throttles = []
        end

        module ClassMethods
          # Add a new throttle.
          #
          # Parameters:
          #   method: [Symbol]
          #     Name of method to call to evaluate whether a throttle has been exceeded.
          #     Note: Must return true or false.
          #   filter: [Symbol|Proc]
          #     Name of method to call to return the filter when the throttle has been exceeded.
          #     Or, a block that will return the filter.
          #     Default: :throttle_class_filter (Throttle all jobs of this class)
          #
          # Note: LIFO: The last throttle to be defined is executed first.
          def define_throttle(method, filter: :throttle_class_filter)
            raise(ArgumentError, "Filter for #{method} must be a Symbol or Proc") unless filter.is_a?(Symbol) || filter.is_a?(Proc)

            rocket_job_throttles.unshift(ThrottleDefinition.new(method, filter))
          end
        end

        # Default throttle to use when the throttle is exceeded.
        # When the throttle has been exceeded all jobs of this class will be ignored until the
        # next refresh. `RocketJob::Config::re_check_seconds` which by default is 60 seconds.
        def throttle_class_filter
          {:_type.nin => [self.class.name]}
        end

        # Merge filter(s)

        private

        ThrottleDefinition = Struct.new(:method, :filter)

        # Returns the matching filter, or nil if no throttles were triggered.
        def rocket_job_evaluate_throttles
          rocket_job_throttles.each do |throttle|
            # Throttle exceeded?
            if send(throttle.method)
              logger.debug { "Throttle: #{throttle.method} has been exceeded. Filtering all #{self.class.name} jobs" }
              filter = throttle.filter
              return filter.is_a?(Proc) ? filter.call(self) : send(filter)
            end
          end
          nil
        end

      end

    end
  end
end
