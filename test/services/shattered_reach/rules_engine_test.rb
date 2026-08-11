# frozen_string_literal: true

require "test_helper"

class ShatteredReach::RulesEngineTest < ActiveSupport::TestCase
  test "allocations are limited by engine energy" do
    state = ShatteredReach::RulesEngine.start
    ship = state["ships"].first

    error = assert_raises(ShatteredReach::RulesEngine::IllegalAction) do
      ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "allocate", payload: { "ship_id" => ship["id"], "speed" => 12, "shields" => 2 })
    end

    assert_match(/energy/, error.message)
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
