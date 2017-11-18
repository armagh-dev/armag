require_relative '../../test/helpers/mongo_support'
require_relative '../../lib/armagh/logging/alert'
require 'test/unit/assertions'

And(/^I should see a Document in "([^"]*)" with the following$/) do |collection, table|
  result = MongoSupport.instance.find_document(collection, table.rows_hash)
  assert_not_empty result
end

Then(/the alerts count( for the "([^"]*)" (workflow|action)){0,1} should be (.*)$/) do |_constraint, constraint_name, constraint_type, expected_alerts_count|
  workflow = nil
  action = nil
  case constraint_type
    when 'workflow' then workflow = constraint_name
    when 'action' then action = constraint_name
  end
  actual_alerts_count = Armagh::Logging::Alert.get_counts( workflow: workflow , action: action )
  assert_equal eval(expected_alerts_count), actual_alerts_count
  p Armagh::Logging::Alert.get
end

Then(/the alerts messages( for the "([^"]*)" (workflow|action)){0,1} should be (.*)$/) do |_constraint, constraint_name, constraint_type, expected_alerts_messages|
  workflow = nil
  action = nil
  case constraint_type
    when 'workflow' then workflow = constraint_name
    when 'action' then action = constraint_name
  end
  actual_alerts = Armagh::Logging::Alert.get( workflow: workflow , action: action )
  actual_alerts_messages = actual_alerts.collect{ |a| a['full_message'] }
  assert_equal eval(expected_alerts_messages), actual_alerts_messages
end

When(/the administrator clears the alerts for the "([^"]*)" (workflow|action)$/) do |constraint_name, constraint_type|
  workflow = nil
  action = nil
  case constraint_type
    when 'workflow' then workflow = constraint_name
    when 'action' then action = constraint_name
  end
  Armagh::Logging::Alert.clear( workflow: workflow , action: action )
end
