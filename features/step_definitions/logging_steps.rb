require_relative '../../test/helpers/mongo_support'
require 'test/unit/assertions'

And(/^I should see a Document in "([^"]*)" with the following$/) do |collection, table|
  result = MongoSupport.instance.find_document(collection, table.rows_hash)
  assert_not_empty result
end