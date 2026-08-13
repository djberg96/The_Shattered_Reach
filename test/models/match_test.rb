# frozen_string_literal: true

require "test_helper"

class MatchTest < ActiveSupport::TestCase
  test "movement can be undone to its complete decision point" do
    state = ShatteredReach::RulesEngine.start
    ship = state["ships"].first
    state["phase"] = "impulse"
    state["impulse"] = 1
    state["activity_step"] = "movement"
    state["pending_movement"] = [ship["id"]]
    state["movement_options"] = ShatteredReach::RulesEngine.legal_movement_actions(state, ship["id"])
    match = Match.create!(title: "Movement undo", state: state)
    before = match.game_state

    match.apply!(player: ship["player"], action: "move_ship", payload: { "ship_id" => ship["id"], "maneuver" => "forward" })
    refute_equal before["ships"].first["position"], match.state["ships"].first["position"]

    match.apply!(player: ship["player"], action: "undo_movement", payload: {})

    assert_equal before["ships"], match.state["ships"]
    assert_equal before["activity_step"], match.state["activity_step"]
    assert_equal before["pending_movement"], match.state["pending_movement"]
    assert_equal before["movement_options"], match.state["movement_options"]
    assert_nil match.state["movement_undo"]
    assert_match(/undoes the last movement decision/, match.state["log"].last)
  end

  test "solo undo rewinds the player's move and subsequent AI movement and launch" do
    state = ShatteredReach::RulesEngine.start(solo: true)
    human, opponent = state["ships"]
    state["phase"] = "impulse"
    state["impulse"] = 1
    state["activity_step"] = "movement"
    state["pending_movement"] = [human["id"], opponent["id"]]
    state["movement_options"] = ShatteredReach::RulesEngine.legal_movement_actions(state, human["id"])
    match = Match.create!(title: "Solo movement undo", state: state)
    before = match.game_state

    match.apply!(player: "player_one", action: "move_ship", payload: { "ship_id" => human["id"], "maneuver" => "forward" })

    assert_equal "launch", match.state["activity_step"]
    assert_equal opponent["weapons"].count { |weapon| weapon["type"] == "missile" }, match.state["missiles"].length
    refute_equal before["ships"].map { |ship| ship["position"] }, match.state["ships"].map { |ship| ship["position"] }

    match.apply!(player: "player_one", action: "undo_movement", payload: {})

    assert_equal before["ships"], match.state["ships"]
    assert_empty match.state["missiles"]
    assert_equal "movement", match.state["activity_step"]
    assert_equal [human["id"], opponent["id"]], match.state["pending_movement"]
  end

  test "continuing beyond missile launch invalidates movement undo" do
    state = ShatteredReach::RulesEngine.start
    ship = state["ships"].first
    state["phase"] = "impulse"
    state["impulse"] = 1
    state["activity_step"] = "movement"
    state["pending_movement"] = [ship["id"]]
    state["movement_options"] = ShatteredReach::RulesEngine.legal_movement_actions(state, ship["id"])
    match = Match.create!(title: "Movement undo boundary", state: state)
    match.apply!(player: ship["player"], action: "move_ship", payload: { "ship_id" => ship["id"], "maneuver" => "forward" })

    assert match.state["movement_undo"]
    match.apply!(player: ship["player"], action: "finish_launches", payload: {})
    assert_nil match.state["movement_undo"]

    assert_raises(ShatteredReach::RulesEngine::IllegalAction) do
      match.apply!(player: ship["player"], action: "undo_movement", payload: {})
    end
  end

  test "solo lock runs a legal opponent allocation" do
    match = Match.create!(title: "Solo", state: ShatteredReach::RulesEngine.start(solo: true))
    ship = match.state["ships"].first
    match.apply!(player: "player_one", action: "allocate", payload: { "ship_id" => ship["id"], "speed" => 1, "shields" => 0 })
    match.apply!(player: "player_one", action: "lock_allocation", payload: {})

    assert_equal "impulse", match.state["phase"]
    assert match.state["ships"].last["locked"]
  end

  test "solo lock allocates every AI ship in a multi-ship fleet" do
    state = ShatteredReach::RulesEngine.start(solo: true, player_one_ships: %w[aurelian_frigate aurelian_cruiser], ai_match: "number")
    match = Match.create!(title: "Solo fleet", state: state)
    match.state["ships"].select { |ship| ship["player"] == "player_one" }.each do |ship|
      match.apply!(player: "player_one", action: "allocate", payload: { "ship_id" => ship["id"], "speed" => 1 })
    end

    match.apply!(player: "player_one", action: "lock_allocation", payload: {})

    assert_equal "impulse", match.state["phase"]
    ai_ships = match.state["ships"].select { |ship| ship["player"] == "player_two" }
    assert_equal 2, ai_ships.length
    assert ai_ships.all? { |ship| ship["locked"] && ship.dig("allocation", "speed").positive? }
  end

  test "solo opponent takes a legal combat action after an impulse" do
    match = Match.create!(title: "Solo combat", state: ShatteredReach::RulesEngine.start(solo: true))
    ship = match.state["ships"].first
    match.apply!(player: "player_one", action: "allocate", payload: { "ship_id" => ship["id"], "speed" => 1, "front_shields" => 0, "aft_shields" => 0 })
    match.apply!(player: "player_one", action: "lock_allocation", payload: {})
    ai_missiles = match.state["ships"].last["weapons"].select { |weapon| weapon["type"] == "missile" }
    ammo_before = ai_missiles.to_h { |weapon| [weapon["id"], weapon["ammo"]] }

    match.apply!(player: "player_one", action: "advance_impulse", payload: {})
    if match.state["activity_step"] == "movement"
      match.apply!(player: "player_one", action: "move_ship", payload: { "ship_id" => ship["id"], "maneuver" => "forward" })
    end

    ai_missiles = match.state["ships"].last["weapons"].select { |weapon| weapon["type"] == "missile" }
    assert ai_missiles.all? { |weapon| weapon["ammo"] == ammo_before.fetch(weapon["id"]) - 1 }
    assert_equal ai_missiles.length, match.state["missiles"].length
    assert match.state["missiles"].all? { |missile| missile["position"] == match.state["ships"].last["position"] }
    assert_match(/Kestrel Cruiser launches/, match.state["log"].last)
  end

  test "solo opponent records every autonomous weapon shot for presentation" do
    state = ShatteredReach::RulesEngine.start(solo: true)
    human, opponent = state["ships"]
    human["position"] = [0, 0, 0]
    opponent["position"] = [2, 0, 3]
    opponent["allocation"]["weapons"] = opponent["weapons"].select { |weapon| weapon["type"] == "beam" }.map { |weapon| weapon["id"] }
    state["phase"] = "impulse"
    state["impulse"] = 1
    state["activity_step"] = "launch"
    match = Match.create!(title: "Solo effects", state: state)

    match.apply!(player: "player_one", action: "finish_launches", payload: {})

    events = match.state["combat_events"]
    assert_operator events.length, :>=, 2
    assert events.all? { |event| event["attacker_id"] == opponent["id"] }
    assert_equal events.map { |event| event["id"] }.uniq, events.map { |event| event["id"] }
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

  test "solo command can resolve a complete multi-ship turn" do
    state = ShatteredReach::RulesEngine.start(solo: true, player_one_ships: %w[aurelian_frigate aurelian_cruiser], ai_match: "number")
    match = Match.create!(title: "Solo fleet turn", state: state)
    match.state["ships"].select { |ship| ship["player"] == "player_one" }.each do |ship|
      match.apply!(player: "player_one", action: "allocate", payload: { "ship_id" => ship["id"], "speed" => 1, "weapons" => [] })
    end
    match.apply!(player: "player_one", action: "lock_allocation", payload: {})

    12.times do
      break if match.state["winner"]

      match.apply!(player: "player_one", action: "advance_impulse", payload: {})
      while match.state["activity_step"] == "movement"
        moving_ship = match.state["ships"].find { |ship| ship["id"] == match.state["pending_movement"].first }
        assert_equal "player_one", moving_ship["player"], "AI movement should resolve automatically"
        match.apply!(player: "player_one", action: "move_ship", payload: { "ship_id" => moving_ship["id"], "maneuver" => match.state["movement_options"].first })
      end
      break if match.state["winner"]

      match.apply!(player: "player_one", action: "finish_launches", payload: {})
      break if match.state["winner"]

      match.apply!(player: "player_one", action: "finish_impulse", payload: {})
    end

    assert match.state["winner"] || (match.state["turn"] == 2 && match.state["phase"] == "allocation")
  end
end
