# frozen_string_literal: true

require "test_helper"

class ShatteredReach::GameDefinitionTest < ActiveSupport::TestCase
  ORIGINAL_IMPULSE_CARDS = [
    [[5, 7, 9, 10, 11, 12], [2, 6, 8, 10, 12], [4, 6, 8, 9, 11, 12], [3, 7, 9, 10, 11, 12]],
    [[3, 5, 7, 9, 10, 11, 12], [4, 6, 8, 9, 10, 11, 12], [4, 6, 7, 8, 9, 10, 12], [1, 5, 7, 8, 10, 11, 12]],
    [[4, 6, 8, 10, 11, 12], [3, 6, 8, 9, 10, 11, 12], [2, 5, 7, 9, 11, 12], [5, 7, 8, 9, 10, 11, 12]]
  ].freeze

  test "digital impulse data preserves the original cards with the corrected card seven" do
    expected = Marshal.load(Marshal.dump(ORIGINAL_IMPULSE_CARDS))
    expected[1][2] = [4, 6, 7, 8, 9, 10, 11, 12]

    assert_equal expected, ShatteredReach::GameDefinition::IMPULSE_DECKS
  end

  test "each speed receives exactly that many movement opportunities per turn" do
    appearances = ShatteredReach::GameDefinition::IMPULSE_DECKS.flatten.tally

    (1..12).each do |speed|
      assert_equal speed, appearances.fetch(speed, 0), "speed #{speed} should appear on #{speed} cards"
    end
  end

  EXPECTED_LOADOUTS = {
    "aurelian_frigate" => { beam: 4, driver: 1, missile: 0 },
    "aurelian_cruiser" => { beam: 4, driver: 2, missile: 0 },
    "aurelian_battleship" => { beam: 8, driver: 2, missile: 0 },
    "veyr_frigate" => { beam: 2, driver: 1, missile: 1 },
    "veyr_cruiser" => { beam: 4, driver: 1, missile: 1 },
    "veyr_battleship" => { beam: 0, driver: 2, missile: 1 },
    "kestrel_frigate" => { beam: 2, driver: 0, missile: 2 },
    "kestrel_cruiser" => { beam: 2, driver: 0, missile: 3 },
    "kestrel_battleship" => { beam: 6, driver: 0, missile: 3 }
  }.freeze

  test "digital loadouts preserve every weapon box from the original ship sheets" do
    EXPECTED_LOADOUTS.each do |ship_key, expected|
      actual = ShatteredReach::GameDefinition::SHIPS.fetch(ship_key)[:weapons].map { |weapon| weapon[:type].to_sym }.tally
      assert_equal expected, { beam: actual.fetch(:beam, 0), driver: actual.fetch(:driver, 0), missile: actual.fetch(:missile, 0) }, ship_key
    end
  end

  test "Mastafarian cruiser batteries retain their printed arcs" do
    weapons = ShatteredReach::GameDefinition::SHIPS.fetch("aurelian_cruiser")[:weapons]

    assert_equal [%w[L], %w[L], %w[R], %w[R], %w[F], %w[F R A L]], weapons.map { |weapon| weapon[:arc] }
    assert_equal %w[B1 B1 B2 B2 MD MD], weapons.map { |weapon| weapon[:mount] }
  end

  test "legacy match states receive the restored loadout" do
    state = ShatteredReach::RulesEngine.start
    state["version"] = "0.1.0"
    state["ships"].first["weapons"] = state["ships"].first["weapons"].first(3)

    ShatteredReach::RulesEngine.normalize!(state)

    assert_equal ShatteredReach::GameDefinition::VERSION, state["version"]
    assert_equal 6, state["ships"].first["weapons"].length
    assert_empty state["ships"].first.dig("allocation", "weapons")
  end

  test "baseline pilot selects an affordable subset of a restored battery" do
    state = ShatteredReach::RulesEngine.start(solo: true)
    allocation = ShatteredReach::BaselinePilot.allocation(state, "player_two")
    ship = state["ships"].last
    weapon_cost = allocation["weapons"].sum do |weapon_id|
      weapon = ship["weapons"].find { |entry| entry["id"] == weapon_id }
      ShatteredReach::GameDefinition::WEAPONS.fetch(weapon["type"])[:energy]
    end

    assert_operator allocation["weapons"].length, :>, 0
    assert_operator allocation["speed"] + weapon_cost, :<=, ship["energy"]
  end
end
