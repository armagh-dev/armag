#!/usr/bin/env ruby

require 'fileutils'

unless ARGV.length == 1
  STDERR.puts 'Usage: generate_files <num_files>'
  exit 1
end

NUM_FILES = ARGV[0].to_i
DIR = '/tmp/input'

FileUtils.mkdir_p DIR

content = ''

NUM_FILES.times do |file_num|
  file = File.join(DIR, "file_#{file_num}")
  empty_file = File.join(DIR, "empty_file_#{file_num}")
  content.clear
  10.times do |line_num|
    content << "Line #{line_num} of file #{file_num}\n"
  end

  File.write(file, content.strip)
  puts "Created #{file}"

  FileUtils.touch empty_file
end

