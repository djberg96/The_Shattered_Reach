# frozen_string_literal: true

require "test_helper"

class ShatteredReach::SaveGameTest < ActiveSupport::TestCase
  test "a match round trips through the portable save format" do
    match = Match.create!(title: "The Long Patrol", state: ShatteredReach::RulesEngine.start(solo: true, board_size: 20))
    ship = match.state["ships"].first
    match.apply!(player: "player_one", action: "allocate", payload: { "ship_id" => ship["id"], "speed" => 4, "front_shields" => 1, "aft_shields" => 0, "weapons" => [] })

    loaded = ShatteredReach::SaveGame.load(ShatteredReach::SaveGame.dump(match))

    assert_equal "The Long Patrol", loaded[:title]
    assert_equal 20, loaded[:state]["board_size"]
    assert loaded[:state]["solo"]
    assert_equal 4, loaded[:state].dig("ships", 0, "allocation", "speed")
  end

  test "loading discards transient effects and undo history" do
    match = Match.create!(title: "Clean Restore", state: ShatteredReach::RulesEngine.start)
    match.state["combat_events"] = [{ "id" => 9, "kind" => "weapon_fire" }]
    match.state["movement_undo"] = { "player" => "player_one", "state" => {} }
    match.save!

    state = ShatteredReach::SaveGame.load(ShatteredReach::SaveGame.dump(match))[:state]

    assert_empty state["combat_events"]
    assert_equal 1, state["next_combat_event_id"]
    assert_not state.key?("movement_undo")
  end

  test "loading rejects malformed and unrecognized files" do
    error = assert_raises(ShatteredReach::SaveGame::InvalidSave) { ShatteredReach::SaveGame.load("not json") }
    assert_match(/valid JSON/, error.message)

    error = assert_raises(ShatteredReach::SaveGame::InvalidSave) { ShatteredReach::SaveGame.load('{"format":"another-game"}') }
    assert_match(/not a Shattered Reach/, error.message)
  end

  test "loading restores canonical ship data instead of trusting display fields" do
    match = Match.create!(title: "Tampered", state: ShatteredReach::RulesEngine.start)
    document = JSON.parse(ShatteredReach::SaveGame.dump(match))
    document["title"] = "<script>bad()</script> Patrol"
    document["state"]["ships"][0]["name"] = "Impossibly Powerful"
    document["state"]["ships"][0]["energy"] = 99_999
    document["state"]["ships"][0]["hull"] = 99_999

    loaded = ShatteredReach::SaveGame.load(JSON.generate(document))
    ship = loaded[:state]["ships"].first

    assert_equal "bad() Patrol", loaded[:title]
    assert_equal "Aurelian Cruiser", ship["name"]
    assert_equal 11, ship["energy"]
    assert_equal 7, ship["hull"]
  end
end
