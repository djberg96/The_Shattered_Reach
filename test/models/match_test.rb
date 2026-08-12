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

  test "solo opponent takes a legal combat action after an impulse" do
    match = Match.create!(title: "Solo combat", state: ShatteredReach::RulesEngine.start(solo: true))
    ship = match.state["ships"].first
    match.apply!(player: "player_one", action: "allocate", payload: { "ship_id" => ship["id"], "speed" => 1, "front_shields" => 0, "aft_shields" => 0 })
    match.apply!(player: "player_one", action: "lock_allocation", payload: {})
    ai_missile = match.state["ships"].last["weapons"].find { |weapon| weapon["type"] == "missile" }
    ammo_before = ai_missile["ammo"]

    match.apply!(player: "player_one", action: "advance_impulse", payload: {})
    if match.state["activity_step"] == "movement"
      match.apply!(player: "player_one", action: "move_ship", payload: { "ship_id" => ship["id"], "maneuver" => "forward" })
    end

    ai_missile = match.state["ships"].last["weapons"].find { |weapon| weapon["type"] == "missile" }
    assert_equal ammo_before - 1, ai_missile["ammo"]
    assert_equal 1, match.state["missiles"].length
    assert_equal match.state["ships"].last["position"], match.state["missiles"].first["position"]
    assert_match(/Kestrel Cruiser launches/, match.state["log"].last)
  end

  test "solo command can resolve a complete staged turn without AI ownership errors" do
    match = Match.create!(title: "Solo full turn", state: ShatteredReach::RulesEngine.start(solo: true))
    ship = match.state["ships"].first
    match.apply!(player: "player_one", action: "allocate", payload: { "ship_id" => ship["id"], "speed" => 1, "front_shields" => 0, "aft_shields" => 0, "weapons" => [] })
    match.apply!(player: "player_one", action: "lock_allocation", payload: {})

    12.times do
      break if match.state["winner"]

      match.apply!(player: "player_one", action: "advance_impulse", payload: {})
      while match.state["activity_step"] == "movement"
        moving_ship = match.state["ships"].find { |entry| entry["id"] == match.state["pending_movement"].first }
        assert_equal "player_one", moving_ship["player"], "AI movement should resolve automatically"
        match.apply!(player: "player_one", action: "move_ship", payload: { "ship_id" => moving_ship["id"], "maneuver" => match.state["movement_options"].first })
      end
      break if match.state["winner"]

      assert_equal "launch", match.state["activity_step"]
      match.apply!(player: "player_one", action: "finish_launches", payload: {})
      break if match.state["winner"]

      assert_equal "fire", match.state["activity_step"]
      match.apply!(player: "player_one", action: "finish_impulse", payload: {})
    end

    assert match.state["winner"] || (match.state["turn"] == 2 && match.state["phase"] == "allocation")
  end
end
