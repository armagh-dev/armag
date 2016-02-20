require_relative 'config_manager'

module Armagh
  module Configuration
    class AgentConfigManager < ConfigManager
      DEFAULT_CONFIG = {
          'available_actions' => {},
      }

      VALID_FIELDS = ['available_actions']

      def initialize(logger)
        super('agent', logger)
      end

      def self.validate(configuration)
        warnings = []
        errors = []

        base_valid = super

        warnings.concat base_valid['warnings']
        errors.concat base_valid['warnings']

        # TODO Validate an agent configuration.  Most of the logic is currently in action_manager but it shouldn't be.  It may not be correct as some functionality has changed

        # Things to validate:
        # * Missing action fields (like doctypes)
        # * Call Action validation (probably need to clean up that error reporting)
        # * A given type/state pair can only be used for a single Parser, Publisher, or Collector
        # * A collector can only take a ready document in, can only produce n document types that are all ready or working.  out types can not be the same as in types  the incoming document gets deleted
        # * A parser can only take a ready document in, can only produce n document types that are all ready or working.  out types can not be the same as in types  the incoming document gets deleted
        # * A subscriber can only take a published document in, can only produce n document types that are all ready or working.  out types can not be the same as in types  the incoming document does not get changed
        # * A publisher only takes a document type (no state -- ready -> published is implied). it's only job is to publish that document.


        {
            'valid'     => errors.empty?,
            'errors'    => errors,
            'warnings'  => warnings
        }
      end
    end
  end
end
