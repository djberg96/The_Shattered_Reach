# frozen_string_literal: true

require "test_helper"

class MatchesControllerTest < ActionDispatch::IntegrationTest
  test "landing page renders" do
    get root_url
    assert_response :success
    assert_select "h1", /SHATTERED/
  end

  test "a tutorial can be created" do
    post matches_url, params: { mode: "tutorial", board_size: 20 }
    assert_response :redirect
    assert_equal "tutorial", Match.last.state["scenario"]
    assert_equal 20, Match.last.state["board_size"]
  end
end
