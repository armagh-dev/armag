require_relative 'config_manager'

module Armagh
  module Configuration
    class AgentConfigManager < ConfigManager
      DEFAULT_CONFIG = {
          'available_actions' => {},
      }

      def initialize(logger)
        super('agent', logger)
      end
    end
  end
end
