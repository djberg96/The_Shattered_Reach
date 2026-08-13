# frozen_string_literal: true

require "test_helper"

class ShatteredReach::RulesEngineTest < ActiveSupport::TestCase
  test "a skirmish can deploy up to three ships per player with duplicates" do
    state = ShatteredReach::RulesEngine.start(
      player_one_ships: %w[aurelian_frigate aurelian_frigate kestrel_battleship],
      player_two_ships: %w[veyr_cruiser veyr_battleship]
    )

    assert_equal %w[aurelian_frigate aurelian_frigate kestrel_battleship], state["ships"].select { |ship| ship["player"] == "player_one" }.map { |ship| ship["key"] }
    assert_equal %w[veyr_cruiser veyr_battleship], state["ships"].select { |ship| ship["player"] == "player_two" }.map { |ship| ship["key"] }
    assert_equal state["ships"].length, state["ships"].map { |ship| ship["id"] }.uniq.length
    assert_equal state["ships"].length, state["ships"].map { |ship| ship["position"].first(2) }.uniq.length
  end

  test "a skirmish rejects more than three ships or unknown classes" do
    error = assert_raises(ShatteredReach::RulesEngine::IllegalAction) do
      ShatteredReach::RulesEngine.start(player_one_ships: Array.new(4, "aurelian_frigate"))
    end
    assert_match(/no more than three/, error.message)

    error = assert_raises(ShatteredReach::RulesEngine::IllegalAction) do
      ShatteredReach::RulesEngine.start(player_one_ships: ["space_waffle"])
    end
    assert_match(/Unknown ship/, error.message)
  end

  test "solo size balancing matches fleet value using no more than three ships" do
    state = ShatteredReach::RulesEngine.start(solo: true, player_one_ships: %w[aurelian_frigate aurelian_battleship], ai_match: "size")
    values = ShatteredReach::RulesEngine::SIZE_VALUES
    human_value = state["ships"].select { |ship| ship["player"] == "player_one" }.sum { |ship| values.fetch(ship["size"]) }
    ai_ships = state["ships"].select { |ship| ship["player"] == "player_two" }

    assert_equal human_value, ai_ships.sum { |ship| values.fetch(ship["size"]) }
    assert_operator ai_ships.length, :<=, 3
    assert ai_ships.all? { |ship| ship["fleet"] != "aurelian" }
  end

  test "solo number balancing matches ship count" do
    state = ShatteredReach::RulesEngine.start(solo: true, player_one_ships: %w[aurelian_frigate kestrel_battleship kestrel_frigate], ai_match: "number")

    assert_equal 3, state["ships"].count { |ship| ship["player"] == "player_one" }
    assert_equal 3, state["ships"].count { |ship| ship["player"] == "player_two" }
    assert state["ships"].select { |ship| ship["player"] == "player_two" }.all? { |ship| ship["size"] == "medium" }
  end

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

  test "ship movement paths begin at the turn-start hex and record translations" do
    state = ShatteredReach::RulesEngine.start
    ship = state["ships"].first
    origin = ship["position"].first(2)
    ship["allocation"]["speed"] = 5
    state["phase"] = "impulse"
    state["activity_step"] = "movement"
    state["pending_movement"] = [ship["id"]]
    state["movement_options"] = ShatteredReach::RulesEngine.legal_movement_actions(state, ship["id"])

    result = ShatteredReach::RulesEngine.apply(state, player: ship["player"], action: "move_ship", payload: { "ship_id" => ship["id"], "maneuver" => "forward" })

    assert_equal [origin, result["ships"].first["position"].first(2)], result["ships"].first["movement_path"]
  end

  test "turning in place does not add a false movement-path segment" do
    state = ShatteredReach::RulesEngine.start
    ship = state["ships"].first
    ship["allocation"]["speed"] = 1
    ship["movement"]["hexes_since_turn"] = 1
    state["phase"] = "impulse"
    state["activity_step"] = "movement"
    state["pending_movement"] = [ship["id"]]
    state["movement_options"] = ShatteredReach::RulesEngine.legal_movement_actions(state, ship["id"])

    result = ShatteredReach::RulesEngine.apply(state, player: ship["player"], action: "move_ship", payload: { "ship_id" => ship["id"], "maneuver" => "turn_left" })

    assert_equal [ship["position"].first(2)], result["ships"].first["movement_path"]
  end

  test "movement paths reset to each ship's current hex at the start of a new turn" do
    state = ShatteredReach::RulesEngine.start
    ship = state["ships"].first
    ship["position"] = [4, 3, 0]
    ship["movement_path"] = [[1, 7], [2, 7], [3, 6], [4, 3]]

    ShatteredReach::RulesEngine.send(:finish_turn!, state)

    assert_equal 2, state["turn"]
    assert_equal [[4, 3]], state["ships"].first["movement_path"]
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

    ShatteredReach::RulesEngine.send(:apply_damage!, state, target, 2, state["ships"].first["position"])

    assert_equal before, target["shields"]["front"]
    assert_equal 0, target.dig("allocation", "shields", "front")
  end

  test "shield repair costs two energy and restores one box at end of turn" do
    state = ShatteredReach::RulesEngine.start
    ship = state["ships"].first
    ship["shields"]["front"] -= 2

    state = ShatteredReach::RulesEngine.apply(state, player: ship["player"], action: "allocate", payload: { "ship_id" => ship["id"], "speed" => 9, "shield_repair" => "front" })
    assert_equal "front", state["ships"].first.dig("allocation", "shield_repair")

    ShatteredReach::RulesEngine.send(:finish_turn!, state)

    repaired = state["ships"].first
    assert_equal repaired["max_front_shields"] - 1, repaired.dig("shields", "front")
    assert_nil repaired.dig("allocation", "shield_repair")
    assert_includes state["log"], "#{repaired["name"]} repairs one front shield box."
  end

  test "a fully collapsed shield can be repaired" do
    state = ShatteredReach::RulesEngine.start
    ship = state["ships"].first
    ship["shields"]["aft"] = 0

    state = ShatteredReach::RulesEngine.apply(state, player: ship["player"], action: "allocate", payload: { "ship_id" => ship["id"], "shield_repair" => "aft" })
    ShatteredReach::RulesEngine.send(:finish_turn!, state)

    assert_equal 1, state["ships"].first.dig("shields", "aft")
  end

  test "shield repair cannot target a full bank or exceed available energy" do
    state = ShatteredReach::RulesEngine.start
    ship = state["ships"].first

    full_error = assert_raises(ShatteredReach::RulesEngine::IllegalAction) do
      ShatteredReach::RulesEngine.apply(state, player: ship["player"], action: "allocate", payload: { "ship_id" => ship["id"], "shield_repair" => "front" })
    end
    assert_match(/full strength/, full_error.message)

    ship["shields"]["front"] -= 1
    energy_error = assert_raises(ShatteredReach::RulesEngine::IllegalAction) do
      ShatteredReach::RulesEngine.apply(state, player: ship["player"], action: "allocate", payload: { "ship_id" => ship["id"], "speed" => 10, "shield_repair" => "front" })
    end
    assert_match(/12 energy/, energy_error.message)
  end

  test "both locked allocations begin the impulse phase" do
    state = ShatteredReach::RulesEngine.start
    state["ships"].each do |ship|
      state = ShatteredReach::RulesEngine.apply(state, player: ship["player"], action: "allocate", payload: { "ship_id" => ship["id"], "speed" => 10, "shields" => 0 })
      state = ShatteredReach::RulesEngine.apply(state, player: ship["player"], action: "lock_allocation", payload: {})
    end

    assert_equal "impulse", state["phase"]
    assert_includes %w[player_one player_two], state["initiative"]
    assert_equal 3, state["impulse_order"].length
    state["impulse_order"].each { |phase| assert_equal [0, 1, 2, 3], phase.sort }
  end

  test "a player must allocate every surviving ship before locking a fleet" do
    state = ShatteredReach::RulesEngine.start(player_one_ships: %w[aurelian_frigate aurelian_cruiser])
    ships = state["ships"].select { |ship| ship["player"] == "player_one" }
    state = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "allocate", payload: { "ship_id" => ships.first["id"], "speed" => 0 })

    error = assert_raises(ShatteredReach::RulesEngine::IllegalAction) do
      ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "lock_allocation")
    end
    assert_match(/every ship/, error.message)

    state = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "allocate", payload: { "ship_id" => ships.last["id"], "speed" => 0 })
    state = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "lock_allocation")
    assert state["ships"].select { |ship| ship["player"] == "player_one" }.all? { |ship| ship["locked"] }
  end

  test "each phase draws all four original impulse cards without replacement" do
    state = ShatteredReach::RulesEngine.start
    state["ships"].each do |ship|
      state = ShatteredReach::RulesEngine.apply(state, player: ship["player"], action: "allocate", payload: { "ship_id" => ship["id"], "speed" => 0, "weapons" => [] })
      state = ShatteredReach::RulesEngine.apply(state, player: ship["player"], action: "lock_allocation")
    end

    drawn = []
    12.times do
      state = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "advance_impulse")
      drawn << [state["impulse_phase"], state["impulse_card_number"], state["impulse_card"]]
      state = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "finish_launches")
      state = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "finish_impulse")
    end

    drawn.each_slice(4).with_index do |phase_draws, phase_index|
      assert_equal [1, 2, 3, 4].map { |card| (phase_index * 4) + card }, phase_draws.map { |draw| draw[1] }.sort
      assert_equal ShatteredReach::GameDefinition::IMPULSE_DECKS[phase_index].sort, phase_draws.map { |draw| draw[2] }.sort
    end
  end

  test "an impulse offers legal movement to ships whose speed appears on its card" do
    state = ShatteredReach::RulesEngine.start
    state["ships"].each do |ship|
      state = ShatteredReach::RulesEngine.apply(state, player: ship["player"], action: "allocate", payload: { "ship_id" => ship["id"], "speed" => 10, "shields" => 0 })
      state = ShatteredReach::RulesEngine.apply(state, player: ship["player"], action: "lock_allocation", payload: {})
    end
    before = state["ships"].first["position"].dup
    state = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "advance_impulse")

    assert_equal "movement", state["activity_step"]
    assert_includes state["movement_options"], "forward"
    while state["activity_step"] == "movement"
      moving_ship = state["ships"].find { |ship| ship["id"] == state["pending_movement"].first }
      state = ShatteredReach::RulesEngine.apply(state, player: moving_ship["player"], action: "move_ship", payload: { "ship_id" => moving_ship["id"], "maneuver" => "forward" })
    end

    assert_equal [before[0] + 1, before[1], before[2]], state["ships"].first["position"]
    assert_equal "launch", state["activity_step"]
  end

  test "a fired beam depletes shields before hull" do
    state = ShatteredReach::RulesEngine.start
    attacker, target = state["ships"]
    target["position"] = [2, 0, 3]
    attacker["allocation"] = { "speed" => 0, "shields" => 0, "weapons" => [attacker["weapons"].first["id"]] }
    state["phase"] = "impulse"
    state["impulse"] = 1
    state["activity_step"] = "fire"
    state["impulse_order"] = Array.new(3) { [0, 1, 2, 3] }
    state["seed"] = 3
    before_shield = target["shields"]["front"]

    result = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "fire", payload: { "ship_id" => attacker["id"], "target_id" => target["id"], "weapon_id" => attacker["weapons"].first["id"] })

    assert_operator result["ships"].last["shields"]["front"], :<, before_shield
    assert_equal target["hull"], result["ships"].last["hull"]
    assert_equal({
      "weapon_type" => "beam", "attacker_id" => attacker["id"], "target_id" => target["id"],
      "origin" => attacker["position"], "target_position" => target["position"], "roll" => 5,
      "to_hit" => 4, "hit" => true
    }, result["combat_events"].last.slice("weapon_type", "attacker_id", "target_id", "origin", "target_position", "roll", "to_hit", "hit"))
    assert_equal({
      "amount" => 1, "shield_bank" => "front", "reinforcement_absorbed" => 0,
      "shield_absorbed" => 1, "hull" => 0, "engines" => 0, "weapons" => [], "destroyed" => false
    }, result["combat_events"].last["damage"].except("before", "after"))
    assert_equal before_shield, result["combat_events"].last.dig("damage", "before", "shields", "front")
    assert_equal before_shield - 1, result["combat_events"].last.dig("damage", "after", "shields", "front")
  end

  test "damage strikes the shield hemisphere facing the attacker" do
    state = ShatteredReach::RulesEngine.start
    target = state["ships"].first
    target["position"] = [5, 5, 0]
    target["shields"] = { "front" => 6, "aft" => 5 }

    front = ShatteredReach::RulesEngine.send(:apply_damage!, state, target, 1, [7, 5, 3])
    aft = ShatteredReach::RulesEngine.send(:apply_damage!, state, target, 2, [3, 5, 0])

    assert_equal "front", front["shield_bank"]
    assert_equal 5, target.dig("shields", "front")
    assert_equal "aft", aft["shield_bank"]
    assert_equal 3, target.dig("shields", "aft")
  end

  test "a collapsed struck shield does not divert damage to the opposite bank" do
    state = ShatteredReach::RulesEngine.start
    target = state["ships"].first
    target["position"] = [5, 5, 0]
    target["shields"] = { "front" => 0, "aft" => 5 }
    target["hull"] = 7
    state["seed"] = 1

    damage = ShatteredReach::RulesEngine.send(:apply_damage!, state, target, 1, [7, 5, 3])

    assert_equal "front", damage["shield_bank"]
    assert_equal 0, damage["shield_absorbed"]
    assert_equal 5, target.dig("shields", "aft")
    assert_equal 1, damage.values_at("hull", "engines").sum + damage["weapons"].length
  end

  test "sequential impacts preserve the state after each hit" do
    state = ShatteredReach::RulesEngine.start
    target = state["ships"].first
    target["position"] = [5, 5, 0]
    target["shields"] = { "front" => 5, "aft" => 5 }
    target["allocation"]["shields"] = { "front" => 0, "aft" => 0 }
    state["seed"] = 1

    first = ShatteredReach::RulesEngine.send(:apply_damage!, state, target, 3, [7, 5, 3])
    second = ShatteredReach::RulesEngine.send(:apply_damage!, state, target, 3, [7, 5, 3])

    assert_equal 5, first.dig("before", "shields", "front")
    assert_equal 2, first.dig("after", "shields", "front")
    assert_equal 2, second.dig("before", "shields", "front")
    assert_equal 0, second.dig("after", "shields", "front")
    assert_equal 1, second.values_at("hull", "engines").sum + second["weapons"].length
  end

  test "a penetrating hit records each damaged system for presentation" do
    state = ShatteredReach::RulesEngine.start
    attacker, target = state["ships"]
    attacker["position"] = [0, 0, 0]
    target["position"] = [1, 0, 3]
    target["shields"] = { "front" => 0, "aft" => 0 }
    weapon = attacker["weapons"].find { |entry| entry["type"] == "beam" }
    weapon["arc"] = ["F"]
    attacker["allocation"]["weapons"] = [weapon["id"]]
    state["phase"] = "impulse"
    state["impulse"] = 1
    state["activity_step"] = "fire"
    state["impulse_order"] = Array.new(3) { [0, 1, 2, 3] }
    state["seed"] = 6

    result = ShatteredReach::RulesEngine.apply(state, player: attacker["player"], action: "fire", payload: { "ship_id" => attacker["id"], "target_id" => target["id"], "weapon_id" => weapon["id"] })
    damage = result["combat_events"].last["damage"]

    assert_equal 3, damage["amount"]
    assert_equal 0, damage["shield_absorbed"]
    assert_equal 1, damage["hull"]
    assert_equal 1, damage["engines"]
    assert_equal 1, damage["weapons"].length
    assert_equal target["weapons"].first["id"], damage["weapons"].first["id"]
  end

  test "a killing hit marks its combat event for the destruction animation" do
    state = ShatteredReach::RulesEngine.start
    attacker, target = state["ships"]
    attacker["position"] = [0, 0, 0]
    target["position"] = [1, 0, 3]
    target["shields"] = { "front" => 0, "aft" => 0 }
    target["hull"] = 1
    target["weapons"].each { |weapon| weapon["destroyed"] = true }
    weapon = attacker["weapons"].find { |entry| entry["type"] == "beam" }
    weapon["arc"] = ["F"]
    attacker["allocation"]["weapons"] = [weapon["id"]]
    state["phase"] = "impulse"
    state["impulse"] = 1
    state["activity_step"] = "fire"
    state["impulse_order"] = Array.new(3) { [0, 1, 2, 3] }
    state["seed"] = 3

    result = ShatteredReach::RulesEngine.apply(state, player: attacker["player"], action: "fire", payload: { "ship_id" => attacker["id"], "target_id" => target["id"], "weapon_id" => weapon["id"] })

    assert result["ships"].last["destroyed"]
    assert result["combat_events"].last.dig("damage", "destroyed")
  end

  test "a missile launches after movement without immediately damaging its target" do
    state = ShatteredReach::RulesEngine.start
    target, attacker = state["ships"]
    missile_launcher = attacker["weapons"].find { |weapon| weapon["type"] == "missile" }
    state["phase"] = "impulse"
    state["impulse"] = 1
    state["activity_step"] = "launch"
    shields_before = target["shields"].dup
    launch_position = attacker["position"].dup

    result = ShatteredReach::RulesEngine.apply(state, player: attacker["player"], action: "launch_missile", payload: { "ship_id" => attacker["id"], "target_id" => target["id"], "weapon_id" => missile_launcher["id"] })

    assert_equal shields_before, result["ships"].first["shields"]
    assert_equal launch_position, result["missiles"].first["position"]
    assert_equal target["id"], result["missiles"].first["target_id"]
    assert_match(/launches a seeker missile/, result["log"].last)
  end

  test "a launched missile moves two hexes on the following impulse" do
    state = ShatteredReach::RulesEngine.start
    target, attacker = state["ships"]
    missile_launcher = attacker["weapons"].find { |weapon| weapon["type"] == "missile" }
    state["phase"] = "impulse"
    state["impulse"] = 1
    state["activity_step"] = "launch"
    state = ShatteredReach::RulesEngine.apply(state, player: attacker["player"], action: "launch_missile", payload: { "ship_id" => attacker["id"], "target_id" => target["id"], "weapon_id" => missile_launcher["id"] })
    before = state["missiles"].first["position"].dup
    state = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "finish_launches")
    state = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "finish_impulse")
    result = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "advance_impulse")

    assert_equal 2, ShatteredReach::RulesEngine.distance(before, result["missiles"].first["position"])
  end

  test "a direct weapon can target and destroy an enemy missile" do
    state = ShatteredReach::RulesEngine.start
    attacker = state["ships"].first
    weapon = attacker["weapons"].find { |entry| entry["type"] == "driver" && entry["arc"] == ["F"] }
    attacker["position"] = [0, 0, 0]
    attacker["allocation"]["weapons"] = [weapon["id"]]
    state["phase"] = "impulse"
    state["impulse"] = 1
    state["activity_step"] = "fire"
    state["impulse_order"] = Array.new(3) { [0, 1, 2, 3] }
    state["seed"] = 4
    state["missiles"] = [{
      "id" => "missile-1", "owner" => "player_two", "fleet" => "kestrel",
      "launcher_ship_id" => state["ships"].last["id"], "target_id" => attacker["id"],
      "position" => [2, 0, 3], "launched_turn" => 1, "launched_impulse" => 1
    }]

    result = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "fire", payload: { "ship_id" => attacker["id"], "target_id" => "missile-1", "weapon_id" => weapon["id"] })

    assert_empty result["missiles"]
    assert result["ships"].all? { |ship| ship["hull"] == ship["max_hull"] }
    assert_match(/destroys a seeker missile/, result["log"].last)
  end

  test "the minus one missile penalty makes a normal hit miss" do
    state = ShatteredReach::RulesEngine.start
    attacker = state["ships"].first
    weapon = attacker["weapons"].find { |entry| entry["type"] == "driver" && entry["arc"] == ["F"] }
    attacker["position"] = [0, 0, 0]
    attacker["allocation"]["weapons"] = [weapon["id"]]
    state["phase"] = "impulse"
    state["impulse"] = 1
    state["activity_step"] = "fire"
    state["impulse_order"] = Array.new(3) { [0, 1, 2, 3] }
    state["seed"] = 5
    state["missiles"] = [{ "id" => "missile-1", "owner" => "player_two", "fleet" => "kestrel", "target_id" => attacker["id"], "position" => [2, 0, 3] }]

    result = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "fire", payload: { "ship_id" => attacker["id"], "target_id" => "missile-1", "weapon_id" => weapon["id"] })

    assert_equal ["missile-1"], result["missiles"].map { |missile| missile["id"] }
    assert_match(/misses a seeker missile \(3\)/, result["log"].last)
    assert_equal false, result["combat_events"].last["hit"]
    assert_equal 4, result["combat_events"].last["to_hit"]
    assert_equal "missile", result["combat_events"].last["target_type"]
  end

  test "a ship cannot fire on its own missile" do
    state = ShatteredReach::RulesEngine.start
    attacker = state["ships"].first
    weapon = attacker["weapons"].find { |entry| entry["type"] == "driver" && entry["arc"] == ["F"] }
    attacker["allocation"]["weapons"] = [weapon["id"]]
    state["phase"] = "impulse"
    state["activity_step"] = "fire"
    state["missiles"] = [{ "id" => "missile-1", "owner" => "player_one", "fleet" => "aurelian", "target_id" => state["ships"].last["id"], "position" => [2, 0, 0] }]

    error = assert_raises(ShatteredReach::RulesEngine::IllegalAction) do
      ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "fire", payload: { "ship_id" => attacker["id"], "target_id" => "missile-1", "weapon_id" => weapon["id"] })
    end

    assert_match(/No legal target/, error.message)
  end

  test "a missile impacts for three damage and is removed from the board" do
    state = ShatteredReach::RulesEngine.start
    target, attacker = state["ships"]
    attacker["position"] = [2, 0, 3]
    target["position"] = [0, 0, 0]
    missile_launcher = attacker["weapons"].find { |weapon| weapon["type"] == "missile" }
    state["phase"] = "impulse"
    state["impulse"] = 1
    state["activity_step"] = "launch"
    state = ShatteredReach::RulesEngine.apply(state, player: attacker["player"], action: "launch_missile", payload: { "ship_id" => attacker["id"], "target_id" => target["id"], "weapon_id" => missile_launcher["id"] })
    shields_before = state["ships"].first.dig("shields", "front")
    state = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "finish_launches")
    state = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "finish_impulse")
    result = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "advance_impulse")

    assert_empty result["missiles"]
    assert_equal shields_before - 3, result["ships"].first.dig("shields", "front")
    assert_match(/hits .* for 3 damage/, result["log"].last)
    event = result["combat_events"].last
    assert_equal "missile_impact", event["kind"]
    assert_equal target["id"], event["target_id"]
    assert_equal 3, event.dig("damage", "shield_absorbed")
  end

  test "weapons fire once per turn rather than once per impulse" do
    state = ShatteredReach::RulesEngine.start
    target, attacker = state["ships"]
    missile_launcher = attacker["weapons"].find { |weapon| weapon["type"] == "missile" }
    state["phase"] = "impulse"
    state["impulse"] = 1
    state["activity_step"] = "launch"
    state = ShatteredReach::RulesEngine.apply(state, player: attacker["player"], action: "launch_missile", payload: { "ship_id" => attacker["id"], "target_id" => target["id"], "weapon_id" => missile_launcher["id"] })
    state = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "finish_launches")
    state = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "finish_impulse")
    state = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "advance_impulse")

    assert_raises(ShatteredReach::RulesEngine::IllegalAction) do
      ShatteredReach::RulesEngine.apply(state, player: attacker["player"], action: "launch_missile", payload: { "ship_id" => attacker["id"], "target_id" => target["id"], "weapon_id" => missile_launcher["id"] })
    end
  end

  test "movement must resolve before launches and direct fire" do
    state = ShatteredReach::RulesEngine.start
    state["ships"].each do |ship|
      state = ShatteredReach::RulesEngine.apply(state, player: ship["player"], action: "allocate", payload: { "ship_id" => ship["id"], "speed" => 10, "weapons" => [] })
      state = ShatteredReach::RulesEngine.apply(state, player: ship["player"], action: "lock_allocation")
    end
    state = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "advance_impulse")

    assert_raises(ShatteredReach::RulesEngine::IllegalAction) do
      ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "finish_launches")
    end

    while state["activity_step"] == "movement"
      moving_ship = state["ships"].find { |ship| ship["id"] == state["pending_movement"].first }
      state = ShatteredReach::RulesEngine.apply(state, player: moving_ship["player"], action: "move_ship", payload: { "ship_id" => moving_ship["id"], "maneuver" => state["movement_options"].first })
    end
    assert_equal "launch", state["activity_step"]
    state = ShatteredReach::RulesEngine.apply(state, player: "player_one", action: "finish_launches")
    assert_equal "fire", state["activity_step"]
  end

  test "turn mode and consecutive side-slip restrictions are enforced" do
    state = ShatteredReach::RulesEngine.start
    ship = state["ships"].first
    ship["allocation"]["speed"] = 5
    state["phase"] = "impulse"
    state["activity_step"] = "movement"
    state["pending_movement"] = [ship["id"]]
    state["movement_options"] = ShatteredReach::RulesEngine.legal_movement_actions(state, ship["id"])

    assert_equal 2, ShatteredReach::RulesEngine.turn_mode(ship)
    refute_includes state["movement_options"], "turn_left"
    state = ShatteredReach::RulesEngine.apply(state, player: ship["player"], action: "move_ship", payload: { "ship_id" => ship["id"], "maneuver" => "sideslip_left" })
    ship = state["ships"].first

    assert_equal "sideslip", ship.dig("movement", "last_action")
    refute_includes ShatteredReach::RulesEngine.legal_movement_actions(state, ship["id"]), "sideslip_left"
    refute_includes ShatteredReach::RulesEngine.legal_movement_actions(state, ship["id"]), "sideslip_right"
  end

  test "direct fire enforces the weapon's firing arc" do
    state = ShatteredReach::RulesEngine.start
    attacker, target = state["ships"]
    attacker["position"] = [0, 0, 0]
    target["position"] = [2, 0, 3]
    port_beam = attacker["weapons"].find { |weapon| weapon["type"] == "beam" && weapon["arc"] == ["L"] }
    attacker["allocation"]["weapons"] = [port_beam["id"]]
    state["phase"] = "impulse"
    state["activity_step"] = "fire"
    state["impulse"] = 1

    error = assert_raises(ShatteredReach::RulesEngine::IllegalAction) do
      ShatteredReach::RulesEngine.apply(state, player: attacker["player"], action: "fire", payload: { "ship_id" => attacker["id"], "target_id" => target["id"], "weapon_id" => port_beam["id"] })
    end

    assert_match(/firing arc/, error.message)
  end
end
