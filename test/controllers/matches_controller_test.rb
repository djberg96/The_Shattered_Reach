# frozen_string_literal: true

require "test_helper"

class MatchesControllerTest < ActionDispatch::IntegrationTest
  test "landing page renders" do
    get root_url
    assert_response :success
    assert_select "h1", /SHATTERED/
  end

  test "a tutorial can be created" do
    post matches_url, params: { scenario: "tutorial" }
    assert_response :redirect
    assert_equal "tutorial", Match.last.state["scenario"]
  end
end
