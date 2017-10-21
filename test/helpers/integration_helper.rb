require 'test/unit'

require_relative 'armagh_test'

require_relative 'mongo_support'

Test::Unit.at_start do
  puts 'Starting Mongo'
  MongoSupport.instance.start_mongo
end

Test::Unit.at_exit do
  puts 'Stopping Mongo'
  MongoSupport.instance.clean_database
  MongoSupport.instance.clean_replica_set
  MongoSupport.instance.stop_mongo
end