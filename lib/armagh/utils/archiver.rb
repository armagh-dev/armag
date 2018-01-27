# Copyright 2018 Noragh Analytics, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied.
#
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'configh'
require 'etc'

require 'armagh/support/encoding'
require 'armagh/documents/source'
require 'armagh/support/sftp'

require 'facets/hash/deep_merge'

module Armagh
  module Utils

    class Archiver
      CONFIG_NAME = 'default'

      class ArchiveError < StandardError; end

      DEFAULT_CONFIG = {
        'host' => 'localhost',
        'username' => Etc.getpwuid(Process.uid).name,
        'directory_path' => '/tmp/var/archive'
      }

      include Configh::Configurable
      include Support::SFTP

      define_parameter name: 'max_archives_per_dir', type: 'positive_integer', description: 'Maximum number archives to store per subdirectory.', required: true, default: 5000, group: 'archive'

      define_constant name: 'duplicate_put_directory_paths', value: [], group: 'sftp'
      define_constant name: 'filename_pattern', value: nil, group: 'sftp'
      define_constant name: 'maximum_transfer', value: 10_000_000, group: 'sftp'

      def self.find_or_create_config(config_store, values = {})
        config_values = {'sftp' => DEFAULT_CONFIG}.deep_merge(values)
        find_or_create_configuration(config_store, CONFIG_NAME, values_for_create: config_values, maintain_history: true)
      end

      def initialize(logger, archive_config)
        @logger = logger
        @archive_config = archive_config
      end

      def within_archive_context
        @remaining_files = nil
        @archive_dir = nil

        Support::SFTP::Connection.open(@archive_config) do |sftp|
          @sftp = sftp
          yield
        end
      ensure
        @sftp = nil
        @remaining_files = nil
        @archive_dir = nil
      end

      def archive_file(file_path, archive_data)
        raise ArchiveError, 'Unable to archive file when outside of an archive context.' unless @sftp
        update_archive_dir

        archive_data =
          Support::Encoding.fix_encoding(
            archive_data,
            proposed_encoding: archive_data.dig('source', 'encoding'),
            logger: @logger
          )
        meta_json = archive_data.to_json
        meta_filename = "#{file_path}.meta"
        File.write(meta_filename, meta_json)

        [meta_filename, file_path].each do |file|
          @sftp.put_file(file, @archive_dir)
          @remaining_files -= 1
        end

        File.delete meta_filename
        @logger.debug "Archived #{file_path} and #{file_path}.meta to #{@archive_dir}"

        File.join(@archive_dir, file_path)
      end

      private def update_archive_dir
        return unless @remaining_files.nil? || @remaining_files < 1 || @archive_dir.nil?
        today = Time.now.utc
        year = today.year.to_s
        month = '%02d' % today.month
        day = '%02d' % today.day

        month_dir = File.join(year, month)
        base_day_dir = File.join(month_dir, "#{day}.%04d") % 0
        @sftp.mkdir_p base_day_dir

        newest_today_dir = @sftp.ls(month_dir).select {|d| d.start_with? day}.last
        archive_dir = File.join(month_dir, newest_today_dir)
        num_files = @sftp.ls(archive_dir).length

        max_archives_per_dir = @archive_config.archive.max_archives_per_dir
        remaining = max_archives_per_dir - num_files

        if remaining > 0
          @remaining_files = remaining
          @archive_dir = archive_dir
        else
          @remaining_files = max_archives_per_dir
          dir_num = newest_today_dir.split('.').last.to_i + 1
          @archive_dir = File.join(month_dir, "#{day}.%04d") % dir_num
        end
      end
    end
  end
end
