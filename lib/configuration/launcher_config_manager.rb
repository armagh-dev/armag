require_relative 'config_manager'

module Armagh
  module Configuration
    class LauncherConfigManager < ConfigManager
      DEFAULT_CONFIG = {
          'num_agents' => 1,
          'checkin_frequency' => 5
      }

      def initialize(logger)
        super('launcher', logger)
      end
    end
  end
end
