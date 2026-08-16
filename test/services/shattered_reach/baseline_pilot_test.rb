# frozen_string_literal: true

require "test_helper"

class ShatteredReach::BaselinePilotTest < ActiveSupport::TestCase
  test "beam weapons ignore missiles beyond close range" do
    state, attacker, target = combat_state("kestrel_cruiser")
    attacker["position"] = [6, 0, 3]
    target["position"] = [0, 0, 0]
    arm_only!(attacker, "beam")
    state["missiles"] = [hostile_missile(position: [2, 0, 0], target: attacker)]

    action = ShatteredReach::BaselinePilot.combat_action(state, "player_one")

    assert_equal target["id"], action.dig(:payload, "target_id")
  end

  test "beam weapons intercept missiles at close range" do
    state, attacker, target = combat_state("kestrel_cruiser")
    attacker["position"] = [6, 0, 3]
    target["position"] = [0, 0, 0]
    arm_only!(attacker, "beam")
    state["missiles"] = [hostile_missile(position: [3, 0, 0], target: attacker)]

    action = ShatteredReach::BaselinePilot.combat_action(state, "player_one")

    assert_equal "missile-test", action.dig(:payload, "target_id")
  end

  test "mass drivers ignore missiles beyond close range" do
    state, attacker, target = combat_state("aurelian_cruiser")
    attacker["position"] = [0, 0, 0]
    target["position"] = [6, 0, 3]
    arm_only!(attacker, "driver")
    state["missiles"] = [hostile_missile(position: [5, 0, 0], target: attacker)]

    action = ShatteredReach::BaselinePilot.combat_action(state, "player_one")

    assert_equal target["id"], action.dig(:payload, "target_id")
  end

  test "mass drivers intercept missiles at close range" do
    state, attacker, target = combat_state("aurelian_cruiser")
    attacker["position"] = [0, 0, 0]
    target["position"] = [6, 0, 3]
    arm_only!(attacker, "driver")
    state["missiles"] = [hostile_missile(position: [4, 0, 0], target: attacker)]

    action = ShatteredReach::BaselinePilot.combat_action(state, "player_one")

    assert_equal "missile-test", action.dig(:payload, "target_id")
  end

  private

  def combat_state(ship_key)
    state = ShatteredReach::RulesEngine.start(player_one_ships: [ship_key])
    [state, state["ships"].first, state["ships"].last]
  end

  def arm_only!(ship, weapon_type)
    weapon_ids = ship["weapons"].select { |weapon| weapon["type"] == weapon_type }.map { |weapon| weapon["id"] }
    ship["allocation"]["weapons"] = weapon_ids
  end

  def hostile_missile(position:, target:)
    {
      "id" => "missile-test", "owner" => "player_two", "fleet" => "veyr",
      "target_id" => target["id"], "position" => position
    }
  end
end
