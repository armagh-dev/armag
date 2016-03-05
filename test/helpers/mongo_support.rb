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

require 'mongo'
require 'singleton'
require 'socket'

class MongoSupport

  include Singleton

  DATABASE_NAME = 'armagh' unless defined? DATABASE_NAME
  HOST = '127.0.0.1' unless defined? HOST
  PORT = '27017' unless defined? PORT

  CONNECTION_STRING = "#{HOST}:#{PORT}" unless defined? CONNECTION_STRING

  OUT_PATH = '/tmp/cuke_mongo.out' unless defined? OUT_PATH

  def initialize
    @mongod_exec = `which mongod`
    @mongo_exec = `which mongo`
    @mongo_pid = nil
    @client = nil

    @hostname = Socket.gethostname

    Mongo::Logger.logger.level = Logger::WARN

    raise 'No mongod found' if @mongod_exec.empty? || @mongod_exec.nil?
    raise 'No mongo found' if @mongo_exec.empty? || @mongo_exec.nil?
  end

  def start_mongo
    unless running?
      File.truncate(OUT_PATH, 0) if File.file? OUT_PATH
      @mongo_pid = Process.spawn(@mongod_exec, :out => OUT_PATH)
      sleep 0.5
    end

    @client ||= Mongo::Client.new([ CONNECTION_STRING ], :database => DATABASE_NAME)

    @mongo_pid
  end

  def running?
    running = false

    if @mongo_pid
      sock = Socket.new(:INET, :STREAM)
      raw = Socket.sockaddr_in(PORT, HOST)
      begin
        running = true if sock.connect(raw)
      rescue; end
    end

    running
  end

  def get_mongo_output
    if File.file? OUT_PATH
      File.read OUT_PATH
    else
      ''
    end
  end

  def delete_config(type)
    @client['config'].find('type' => type).delete_one
  end

  def set_config(type, config)
    @client['config'].find('type' => type).replace_one(config.merge({'type' => type}), {upsert: true})
  end

  def get_status
    @client['status'].find('_id' => @hostname).limit(1).first
  end

  def get_documents
    @client['documents'].find
  end

  def stop_mongo
    return if @mongo_pid.nil?

    Process.kill(:SIGTERM, @mongo_pid)
    Process.wait(@mongo_pid)

    @client = nil
    @mongo_pid = nil
  end

  def clean_database
    `mongo #{DATABASE_NAME} --eval "db.dropDatabase();"`
  end
end
