# Copyright 2016 Noragh Analytics, Inc.
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

require_relative '../errors'
require 'armagh/documents/source'
require 'armagh/support/sftp'

module Armagh
  module Utils
    class Archiver
      MAX_ARCHIVES_PER_DIR = 5_000

      def initialize(logger)
        @logger = logger
      end

      def within_archive_context
        @remaining_files = nil
        @archive_dir = nil

        Support::SFTP::Connection.open(Support::SFTP.archive_config) do |sftp|
          @sftp = sftp
          yield
        end
      ensure
        @sftp = nil
        @remaining_files = nil
        @archive_dir = nil
      end

      def archive_file(file_path, archive_data)
        raise Errors::ArchiveError, 'Unable to archive file when outside of an archive context.' unless @sftp
        update_archive_dir

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

        newest_today_dir = @sftp.ls(month_dir).select { |d| d.start_with? day }.last
        archive_dir = File.join(month_dir, newest_today_dir)
        num_files = @sftp.ls(archive_dir).length

        remaining = MAX_ARCHIVES_PER_DIR - num_files

        if remaining > 0
          @remaining_files = remaining
          @archive_dir = archive_dir
        else
          @remaining_files = MAX_ARCHIVES_PER_DIR
          dir_num = newest_today_dir.split('.').last.to_i + 1
          @archive_dir = File.join(month_dir, "#{day}.%04d") % dir_num
        end
      end
    end
  end
end
