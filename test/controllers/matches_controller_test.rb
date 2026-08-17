# frozen_string_literal: true

require "test_helper"

class MatchesControllerTest < ActionDispatch::IntegrationTest
  test "landing page renders" do
    get root_url
    assert_response :success
    assert_select "h1", /SHATTERED/
    assert_select "button[data-open-dialog='new-game-dialog']", text: "New game"
    assert_select "button[data-open-dialog='load-game-dialog']", text: "Load game"
    assert_select "button[data-open-dialog='ship-catalog-dialog']", text: "View ships"
    assert_select "a[href='/the-shattered-reach-ship-cards.pdf']", text: "Print ship cards"
    assert_equal "%PDF", Rails.root.join("public/the-shattered-reach-ship-cards.pdf").binread(4)
    assert_select "dialog#new-game-dialog [data-setup-step='1']"
    assert_select "dialog#new-game-dialog [data-setup-step='2'][hidden]"
    assert_select "dialog#new-game-dialog .setup-options-menu input[type='checkbox']", count: 3
    assert_select "[data-ai-options][hidden] input", count: 2
    assert_select "dialog#load-game-dialog form.load-game-form"
    ShatteredReach::GameDefinition::SHIPS.each_value do |ship|
      assert_select "option", text: /#{Regexp.escape(ship[:name].split.last)}/
    end
    assert_select "dialog#ship-catalog-dialog [data-catalog-ship]", count: 9
    assert_select "dialog#ship-catalog-dialog [data-catalog-panel]", count: 9
    assert_select "dialog#ship-catalog-dialog [data-catalog-panel]:not([hidden])", count: 1
    assert_select ".setting-intro #setting-title", text: "The lanes are opening again."
    assert_select "[data-ship-lore]", count: 9
  end

  test "a hot-seat skirmish accepts duplicate three-ship fleets" do
    post matches_url, params: {
      mode: "hotseat",
      player_one_ships: %w[aurelian_frigate aurelian_frigate kestrel_battleship],
      player_two_ships: %w[veyr_frigate veyr_cruiser veyr_battleship]
    }

    assert_response :redirect
    assert_equal 6, Match.last.state["ships"].length
    assert_equal 2, Match.last.state["ships"].count { |ship| ship["key"] == "aurelian_frigate" }
  end

  test "a new battle records selected optional rules" do
    post matches_url, params: {
      mode: "hotseat",
      rules_options: { acceleration_limits: "1", fast_turns: "1" }
    }

    assert_response :redirect
    assert_equal({
      "acceleration_limits" => true,
      "weapon_repair" => false,
      "fast_turns" => true
    }, Match.last.state["rules_options"])
  end

  test "a solo skirmish balances the selected fleet by total size" do
    post matches_url, params: { mode: "solo", player_one_ships: %w[aurelian_frigate aurelian_battleship], ai_match: "size" }

    assert_response :redirect
    values = ShatteredReach::RulesEngine::SIZE_VALUES
    fleets = Match.last.state["ships"].group_by { |ship| ship["player"] }
    assert_equal fleets["player_one"].sum { |ship| values.fetch(ship["size"]) }, fleets["player_two"].sum { |ship| values.fetch(ship["size"]) }
  end

  test "a tutorial can be created" do
    post matches_url, params: { mode: "tutorial", board_size: 20 }
    assert_response :redirect
    assert_equal "tutorial", Match.last.state["scenario"]
    assert_equal 20, Match.last.state["board_size"]
  end

  test "new battles receive unique random seeds" do
    post matches_url, params: { mode: "solo" }
    first = Match.last.state.slice("seed", "rng")
    post matches_url, params: { mode: "solo" }
    second = Match.last.state.slice("seed", "rng")

    assert_not_equal first, second
  end

  test "match page exposes tactical artwork for every ship class" do
    match = Match.create!(title: "Tactical artwork", state: ShatteredReach::RulesEngine.start(solo: true))

    get match_url(match)

    assert_response :success
    manifest = JSON.parse(css_select("[data-tactical-art]").first["data-tactical-art"])
    assert_equal ShatteredReach::GameDefinition::SHIPS.keys.map(&:to_s).sort, manifest.keys.sort
    assert manifest.values.all? { |path| path.include?("/assets/ships/tactical/") }
    assert_includes css_select("[data-missile-art]").first["data-missile-art"], "/assets/ships/tactical/seeker_missile"
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

  test "a match can be downloaded as a portable save" do
    match = Match.create!(title: "Save test", state: ShatteredReach::RulesEngine.start(solo: true))

    get download_match_url(match)

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_match(/attachment/, response.headers["content-disposition"])
    document = JSON.parse(response.body)
    assert_equal ShatteredReach::SaveGame::FORMAT, document["format"]
    assert_equal match.state["ships"].map { |ship| ship["id"] }, document.dig("state", "ships").map { |ship| ship["id"] }
  end

  test "a battle can be reset with its original mode map and exact fleets" do
    state = ShatteredReach::RulesEngine.start(solo: true, board_size: 20, player_one_ships: %w[aurelian_frigate aurelian_cruiser], ai_match: "number", rules_options: { fast_turns: true })
    match = Match.create!(title: "Reset test", state: state)
    original_fleets = state["ships"].group_by { |ship| ship["player"] }.transform_values { |ships| ships.map { |ship| ship["key"] } }
    match.state["turn"] = 3
    match.state["ships"].first["hull"] -= 1
    match.save!

    post reset_match_url(match), as: :json

    assert_response :success
    reset_state = response.parsed_body
    assert reset_state["solo"]
    assert_equal 20, reset_state["board_size"]
    assert_equal 1, reset_state["turn"]
    assert_equal "allocation", reset_state["phase"]
    assert_not_equal state["seed"], reset_state["seed"]
    assert_equal original_fleets, reset_state["ships"].group_by { |ship| ship["player"] }.transform_values { |ships| ships.map { |ship| ship["key"] } }
    assert reset_state.dig("rules_options", "fast_turns")
    assert reset_state["ships"].all? { |ship| ship["hull"] == ship["max_hull"] }
  end

  test "a portable save can be loaded into a new match" do
    original = Match.create!(title: "Imported patrol", state: ShatteredReach::RulesEngine.start(solo: true, board_size: 20))
    upload = Tempfile.new(["shattered-reach", ".json"])
    upload.write(ShatteredReach::SaveGame.dump(original))
    upload.rewind

    assert_difference("Match.count", 1) do
      post import_matches_url, params: { save_file: Rack::Test::UploadedFile.new(upload.path, "application/json") }
    end

    assert_redirected_to Match.order(:created_at).last
    assert_equal 20, Match.order(:created_at).last.state["board_size"]
  ensure
    upload&.close!
  end

  test "an invalid portable save returns to the archive with an error" do
    upload = Tempfile.new(["invalid", ".json"])
    upload.write("not a save")
    upload.rewind

    assert_no_difference("Match.count") do
      post import_matches_url, params: { save_file: Rack::Test::UploadedFile.new(upload.path, "application/json") }
    end

    assert_redirected_to matches_url
    follow_redirect!
    assert_select ".flash-message.error", /valid JSON/
  ensure
    upload&.close!
  end
end
