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

  test "game commands are not confused with the Rails action parameter" do
    match = Match.create!(title: "Command test", state: ShatteredReach::RulesEngine.start(solo: true))
    ship = match.state["ships"].first

    post action_match_url(match), params: { player: "player_one", command: "allocate", payload: { ship_id: ship["id"], speed: 3, front_shields: 1, aft_shields: 0, weapons: [] } }, as: :json

    assert_response :success
    assert_equal 3, response.parsed_body.dig("ships", 0, "allocation", "speed")
  end

  test "solo HTTP commands cannot take control of the AI ship" do
    match = Match.create!(title: "Solo ownership", state: ShatteredReach::RulesEngine.start(solo: true))
    ai_ship = match.state["ships"].last

    post action_match_url(match), params: { player: "player_two", command: "allocate", payload: { ship_id: ai_ship["id"], speed: 3, front_shields: 0, aft_shields: 0, weapons: [] } }, as: :json

    assert_response :unprocessable_content
    assert_match(/not under your command/, response.parsed_body.fetch("error"))
  end
end
