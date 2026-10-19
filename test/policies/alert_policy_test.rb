require "test_helper"

class AlertPolicyTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  parallelize(workers: 1)

  test "anonymous scope returns no alerts" do
    assert_empty AlertPolicy::Scope.new(nil, Alert.all).resolve
  end

  test "alert endpoints fail verification if policy scoping is omitted" do
    controller = Api::AlertsController.new
    assert_raises(Pundit::PolicyScopingNotPerformedError) do
      controller.send(:verify_policy_scoped)
    end
  end
end
