# frozen_string_literal: true

require "test_helper"

class MatchTest < ActiveSupport::TestCase
  test "solo lock runs a legal opponent allocation" do
    match = Match.create!(title: "Solo", state: ShatteredReach::RulesEngine.start(solo: true))
    ship = match.state["ships"].first
    match.apply!(player: "player_one", action: "allocate", payload: { "ship_id" => ship["id"], "speed" => 1, "shields" => 0 })
    match.apply!(player: "player_one", action: "lock_allocation", payload: {})

    assert_equal "impulse", match.state["phase"]
    assert match.state["ships"].last["locked"]
  end
end
