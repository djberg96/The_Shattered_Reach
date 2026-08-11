# frozen_string_literal: true

require "test_helper"

class ShatteredReach::RulesEngineTest < ActiveSupport::TestCase
  test "supported board sizes deploy ships ten to fifteen hexes apart facing each other" do
    [12, 15, 20].each do |board_size|
      state = ShatteredReach::RulesEngine.start(board_size: board_size)
      first, second = state["ships"]

      assert_equal board_size, state["board_size"]
      assert_operator ShatteredReach::RulesEngine.distance(first["position"], second["position"]), :>=, 10
      assert_operator ShatteredReach::RulesEngine.distance(first["position"], second["position"]), :<=, 15
      assert_equal 3, (second["position"][2] - first["position"][2]) % 6
    end
  end

  test "legacy initial matches are normalized onto the new board" do
    state = ShatteredReach::RulesEngine.start
    state.delete("board_size")
    state["ships"].first["position"] = [0, 0, 0]
    state["ships"].last["position"] = [8, -4, 3]

    ShatteredReach::RulesEngine.normalize!(state)

    assert_equal 15, state["board_size"]
    assert_equal 7, state["ships"].first["position"][1] + (state["ships"].first["position"][0] / 2)
    assert_equal 7, state["ships"].last["position"][1] + (state["ships"].last["position"][0] / 2)
  end

  test "ship state exposes maximum shield tracks for the live schematic" do
    state = ShatteredReach::RulesEngine.start
    ship = state["ships"].first

    assert_equal 6, ship["max_front_shields"]
    assert_equal 5, ship["max_aft_shields"]

    ship.delete("max_front_shields")
    ship.delete("max_aft_shields")
    ShatteredReach::RulesEngine.normalize!(state)

    assert_equal 6, ship["max_front_shields"]
    assert_equal 5, ship["max_aft_shields"]
  end

  test "allocations are limited by engine energy" do
    state = ShatteredReach::RulesEngine.start
    ship = state["ships"].first

    error = assert_raises(ShatteredReach::RulesEngine::IllegalAction) do
      ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "allocate", payload: { "ship_id" => ship["id"], "speed" => 12, "shields" => 2 })
    end

    assert_match(/energy/, error.message)
  end

  test "front and aft shield reinforcement are allocated independently" do
    state = ShatteredReach::RulesEngine.start
    ship = state["ships"].first

    state = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "allocate", payload: { "ship_id" => ship["id"], "speed" => 1, "front_shields" => 2, "aft_shields" => 1 })

    assert_equal({ "front" => 2, "aft" => 1 }, state["ships"].first.dig("allocation", "shields"))
  end

  test "a collapsed shield cannot be reinforced" do
    state = ShatteredReach::RulesEngine.start
    ship = state["ships"].first
    ship["shields"]["aft"] = 0

    error = assert_raises(ShatteredReach::RulesEngine::IllegalAction) do
      ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "allocate", payload: { "ship_id" => ship["id"], "aft_shields" => 1 })
    end

    assert_match(/collapsed/, error.message)
  end

  test "shield reinforcement absorbs damage before its shield track" do
    state = ShatteredReach::RulesEngine.start
    target = state["ships"].last
    target["allocation"]["shields"] = { "front" => 2, "aft" => 0 }
    before = target["shields"]["front"]

    ShatteredReach::RulesEngine.send(:apply_damage!, state, target, 2, state["ships"].first)

    assert_equal before, target["shields"]["front"]
    assert_equal 0, target.dig("allocation", "shields", "front")
  end

  test "both locked allocations begin the impulse phase" do
    state = ShatteredReach::RulesEngine.start
    state["ships"].each do |ship|
      state = ShatteredReach::RulesEngine.apply(state, player: ship["player"], action: "allocate", payload: { "ship_id" => ship["id"], "speed" => 1, "shields" => 0 })
      state = ShatteredReach::RulesEngine.apply(state, player: ship["player"], action: "lock_allocation", payload: {})
    end

    assert_equal "impulse", state["phase"]
    assert_includes %w[player_one player_two], state["initiative"]
  end

  test "an impulse moves ships whose speed appears on its card" do
    state = ShatteredReach::RulesEngine.start
    state["ships"].each do |ship|
      state = ShatteredReach::RulesEngine.apply(state, player: ship["player"], action: "allocate", payload: { "ship_id" => ship["id"], "speed" => 1, "shields" => 0 })
      state = ShatteredReach::RulesEngine.apply(state, player: ship["player"], action: "lock_allocation", payload: {})
    end
    before = state["ships"].first["position"].dup
    state = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "advance_impulse")

    assert_equal [before[0] + 1, before[1], before[2]], state["ships"].first["position"]
  end

  test "a fired beam depletes shields before hull" do
    state = ShatteredReach::RulesEngine.start
    attacker, target = state["ships"]
    target["position"] = [2, 0, 3]
    attacker["allocation"] = { "speed" => 0, "shields" => 0, "weapons" => [attacker["weapons"].first["id"]] }
    state["phase"] = "impulse"
    state["seed"] = 3
    before_shield = target["shields"]["front"]

    result = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "fire", payload: { "ship_id" => attacker["id"], "target_id" => target["id"], "weapon_id" => attacker["weapons"].first["id"] })

    assert_operator result["ships"].last["shields"]["front"], :<, before_shield
    assert_equal target["hull"], result["ships"].last["hull"]
  end
end
