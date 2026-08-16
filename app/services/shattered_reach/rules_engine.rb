# frozen_string_literal: true

require "digest"

module ShatteredReach
  class RulesEngine
    BOARD_SIZES = [12, 15, 20].freeze
    DIRECTIONS = [[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]].freeze
    RNG_MASK = 0xffff_ffff
    RNG_ACCEPTANCE_LIMIT = ((RNG_MASK + 1) / 6) * 6
    RNG_STREAMS = %w[attack damage setup].freeze
    # A -1 die-roll penalty is equivalent to increasing the required result by 1.
    MISSILE_TARGET_TO_HIT_PENALTY = 1

    class IllegalAction < StandardError; end

    DEFAULT_FLEETS = {
      "player_one" => ["aurelian_cruiser"],
      "player_two" => ["kestrel_cruiser"]
    }.freeze
    SIZE_VALUES = { "small" => 2, "medium" => 3, "large" => 4 }.freeze

    def self.start(scenario: :skirmish, solo: false, board_size: 15, player_one_ships: nil, player_two_ships: nil, ai_match: "size", seed: 17)
      board_size = board_size.to_i
      board_size = 15 unless BOARD_SIZES.include?(board_size)
      fleets = if scenario == :tutorial
                 { "player_one" => ["aurelian_frigate"], "player_two" => ["veyr_frigate"] }
               else
                 human = normalize_fleet_selection(player_one_ships, DEFAULT_FLEETS["player_one"])
                 opponent = if solo
                              ai_fleet_for(human, ai_match)
                            else
                              normalize_fleet_selection(player_two_ships, DEFAULT_FLEETS["player_two"])
                            end
                 { "player_one" => human, "player_two" => opponent }
               end
      positions = starting_formations(board_size, fleets.transform_values(&:length))
      ships = fleets.flat_map do |player, ship_keys|
        ship_keys.each_with_index.map do |ship_key, index|
          build_ship(ship_key, player, positions.fetch(player).fetch(index), index + 1)
        end
      end
      {
        "version" => GameDefinition::VERSION, "scenario" => scenario.to_s, "solo" => solo, "board_size" => board_size, "turn" => 1,
        "phase" => "allocation", "impulse" => 0, "seed" => seed.to_i & RNG_MASK, "rng" => initial_rng, "initiative" => nil,
        "activity_step" => "allocation", "impulse_card" => nil, "impulse_phase" => nil, "impulse_card_number" => nil,
        "impulse_order" => nil, "pending_movement" => [], "movement_options" => [], "movement_stage" => nil,
        "ships" => ships, "missiles" => [], "next_missile_id" => 1,
        "combat_events" => [], "next_combat_event_id" => 1,
        "log" => ["Battle stations. Allocate energy in secret."], "winner" => nil,
        "tutorial_step" => scenario == :tutorial ? 0 : nil
      }
    end

    def self.restart(state, seed: state.fetch("seed", 17))
      current = Marshal.load(Marshal.dump(state))
      normalize!(current)
      fleets = current.fetch("ships").reject { |ship| ship["destroyed"] && ship["key"].blank? }
                      .group_by { |ship| ship.fetch("player") }
                      .transform_values { |ships| ships.sort_by { |ship| ship["fleet_index"].to_i }.map { |ship| ship.fetch("key") } }
      fresh = start(
        scenario: current.fetch("scenario", "skirmish").to_sym,
        solo: false,
        board_size: current.fetch("board_size", 15),
        player_one_ships: fleets["player_one"],
        player_two_ships: fleets["player_two"],
        seed: seed
      )
      fresh["solo"] = current["solo"] == true
      fresh
    end

    def self.normalize_fleet_selection(selection, fallback)
      selected = Array(selection).map(&:to_s).reject(&:blank?)
      selected = fallback if selected.empty?
      raise IllegalAction, "A skirmish fleet may contain no more than three ships" if selected.length > 3
      raise IllegalAction, "Unknown ship selection" unless selected.all? { |key| GameDefinition::SHIPS.key?(key) }

      selected
    end
    private_class_method :normalize_fleet_selection

    def self.ai_fleet_for(human_fleet, match_by)
      enemy_fleet = opposing_fleet_for(human_fleet)
      available = GameDefinition::SHIPS.select { |_key, spec| spec[:fleet] == enemy_fleet }
      if match_by.to_s == "number"
        cruiser = available.find { |_key, spec| spec[:size] == "medium" }.first
        return Array.new(human_fleet.length, cruiser)
      end

      target_value = human_fleet.sum { |key| SIZE_VALUES.fetch(GameDefinition::SHIPS.fetch(key)[:size]) }
      size_patterns = (1..3).flat_map { |count| %w[small medium large].repeated_permutation(count).to_a }
      pattern = size_patterns.select { |sizes| sizes.sum { |size| SIZE_VALUES.fetch(size) } == target_value }
                             .min_by { |sizes| [sizes.length, sizes.join] }
      pattern.map { |size| available.find { |_key, spec| spec[:size] == size }.first }
    end
    private_class_method :ai_fleet_for

    def self.opposing_fleet_for(human_fleet)
      counts = human_fleet.map { |key| GameDefinition::SHIPS.fetch(key)[:fleet] }.tally
      dominant = counts.max_by { |fleet, count| [count, fleet] }&.first || "aurelian"
      { "aurelian" => "kestrel", "kestrel" => "veyr", "veyr" => "aurelian" }.fetch(dominant)
    end
    private_class_method :opposing_fleet_for

    def self.starting_positions(board_size)
      formations = starting_formations(board_size, { "player_one" => 1, "player_two" => 1 })
      [formations["player_one"].first, formations["player_two"].first]
    end
    private_class_method :starting_positions

    def self.starting_formations(board_size, counts)
      separation = (board_size - 3).clamp(10, 13)
      left_column = ((board_size - 1 - separation) / 2.0).floor
      right_column = left_column + separation
      row = board_size / 2
      row_offsets = { 1 => [0], 2 => [-1, 1], 3 => [-1, 0, 1] }
      {
        "player_one" => row_offsets.fetch(counts.fetch("player_one")).map { |offset| [left_column, row + offset - (left_column / 2), 0] },
        "player_two" => row_offsets.fetch(counts.fetch("player_two")).map { |offset| [right_column, row + offset - (right_column / 2), 3] }
      }
    end
    private_class_method :starting_formations

    def self.apply(state, player:, action:, payload: {})
      state = Marshal.load(Marshal.dump(state))
      normalize!(state)
      return state if state["winner"]

      case action.to_s
      when "allocate" then allocate!(state, player, payload)
      when "lock_allocation" then lock_allocation!(state, player)
      when "advance_impulse" then draw_impulse!(state)
      when "move_ship" then move_ship!(state, player, payload)
      when "finish_movement" then finish_movement!(state, player, payload)
      when "launch_missile" then launch_missile_action!(state, player, payload)
      when "finish_launches" then finish_launches!(state)
      when "fire" then fire!(state, player, payload)
      when "finish_impulse" then finish_impulse!(state)
      when "special" then special!(state, player, payload)
      else raise IllegalAction, "Unknown action: #{action}"
      end
      state
    end

    def self.normalize!(state)
      state["seed"] = state.fetch("seed", 17).to_i & RNG_MASK
      state["rng"] = normalized_rng(state["rng"])
      unless state.key?("board_size")
        state["board_size"] = 15
        if state["turn"] == 1 && state["phase"] == "allocation" && state["impulse"].to_i.zero?
          starting_positions(15).each_with_index { |position, index| state["ships"][index]["position"] = position if state["ships"][index] }
        end
      end
      migrate_loadouts!(state) if state["version"] != GameDefinition::VERSION
      state["missiles"] ||= []
      state["next_missile_id"] ||= state["missiles"].length + 1
      state["combat_events"] ||= []
      state["next_combat_event_id"] ||= state["combat_events"].map { |event| event["id"].to_i }.max.to_i + 1
      state["activity_step"] ||= state["phase"] == "allocation" ? "allocation" : "fire"
      state["impulse_card"] ||= nil
      state["impulse_phase"] ||= nil
      state["impulse_card_number"] ||= nil
      if state["impulse_order"].nil? && state["phase"] == "impulse"
        state["impulse_order"] = Array.new(3) { shuffled_card_indices(state) }
      end
      state["pending_movement"] ||= []
      state["movement_options"] ||= []
      state["movement_stage"] = if state["activity_step"] == "movement" && state["pending_movement"].any?
                                  state["movement_stage"] == "after" ? "after" : "before"
                                end

      state["ships"].each do |ship|
        spec = GameDefinition::SHIPS[ship["key"]]
        next unless spec

        ship["fleet_index"] ||= state["ships"].select { |candidate| candidate["player"] == ship["player"] }.index(ship).to_i + 1
        ship["max_front_shields"] ||= spec[:front_shields]
        ship["max_aft_shields"] ||= spec[:aft_shields]
        allocation = ship["allocation"] ||= { "speed" => 0, "shields" => {}, "shield_repair" => nil, "weapons" => [] }
        unless allocation["shields"].is_a?(Hash)
          allocation["shields"] = { "front" => allocation["shields"].to_i, "aft" => 0 }
        end
        allocation["shields"]["front"] ||= 0
        allocation["shields"]["aft"] ||= 0
        allocation["shield_repair"] = nil unless %w[front aft].include?(allocation["shield_repair"])
        ship["allocation_set"] = ship["allocation_set"] == true
        ship["movement"] ||= { "hexes_since_turn" => 0, "last_action" => nil }
        ship["movement_path"] = [ship["position"].first(2)] unless ship["movement_path"].is_a?(Array) && ship["movement_path"].any?
      end
      state
    end

    def self.migrate_loadouts!(state)
      state["ships"].each do |ship|
        spec = GameDefinition::SHIPS[ship["key"]]
        next unless spec

        old_weapons = Array(ship["weapons"])
        destroyed_count = old_weapons.count { |weapon| weapon["destroyed"] }
        fired_count = old_weapons.count { |weapon| weapon["fired"] && !weapon["destroyed"] }
        ship["weapons"] = spec[:weapons].map.with_index do |weapon, index|
          weapon.stringify_keys.merge("id" => "w#{index}", "destroyed" => index < destroyed_count, "fired" => false)
        end
        ship["weapons"].reject { |weapon| weapon["destroyed"] }.first(fired_count).each { |weapon| weapon["fired"] = true }
        ship["allocation"]["weapons"] = [] if ship["allocation"]
        ship["locked"] = false if state["phase"] == "allocation"
      end
      state["version"] = GameDefinition::VERSION
      state["log"] << "Fleet registry updated: original weapon batteries restored." if state["log"]
    end
    private_class_method :migrate_loadouts!

    def self.build_ship(key, player, position, fleet_index = 1)
      spec = GameDefinition::SHIPS.fetch(key)
      {
        "id" => "#{player}-#{key}-#{fleet_index}", "key" => key, "player" => player, "name" => spec[:name], "fleet_index" => fleet_index, "fleet" => spec[:fleet],
        "size" => spec[:size], "position" => position, "energy" => spec[:energy], "hull" => spec[:hull], "max_hull" => spec[:hull],
        "shields" => { "front" => spec[:front_shields], "aft" => spec[:aft_shields] }, "max_front_shields" => spec[:front_shields], "max_aft_shields" => spec[:aft_shields],
        "allocation" => { "speed" => 0, "shields" => { "front" => 0, "aft" => 0 }, "shield_repair" => nil, "weapons" => [] },
        "allocation_set" => false, "locked" => false, "special_available" => spec[:size] != "large", "weapons" => spec[:weapons].map.with_index { |w, i| w.stringify_keys.merge("id" => "w#{i}", "destroyed" => false, "fired" => false) },
        "damage" => { "engines" => 0, "weapons" => 0 }, "movement" => { "hexes_since_turn" => 0, "last_action" => nil },
        "movement_path" => [position.first(2)], "destroyed" => false
      }
    end
    private_class_method :build_ship

    def self.allocate!(state, player, payload)
      require_phase!(state, "allocation")
      ship = owned_ship!(state, player, payload.fetch("ship_id"))
      raise IllegalAction, "Allocation is already locked" if ship["locked"]
      speed = payload.fetch("speed", 0).to_i.clamp(0, 12)
      legacy_shields = payload.fetch("shields", 0)
      front_shields = payload.fetch("front_shields", legacy_shields.is_a?(Hash) ? legacy_shields.fetch("front", 0) : legacy_shields).to_i.clamp(0, shield_cap(ship))
      aft_shields = payload.fetch("aft_shields", legacy_shields.is_a?(Hash) ? legacy_shields.fetch("aft", 0) : 0).to_i.clamp(0, shield_cap(ship))
      raise IllegalAction, "Forward shield is collapsed and cannot be reinforced" if front_shields.positive? && ship.dig("shields", "front").to_i.zero?
      raise IllegalAction, "Aft shield is collapsed and cannot be reinforced" if aft_shields.positive? && ship.dig("shields", "aft").to_i.zero?
      shield_repair = payload["shield_repair"].presence
      raise IllegalAction, "Choose the forward or aft shield for repair" if shield_repair && !%w[front aft].include?(shield_repair)
      if shield_repair && ship.dig("shields", shield_repair).to_i >= maximum_shields(ship, shield_repair)
        raise IllegalAction, "#{shield_repair.capitalize} shield is already at full strength"
      end
      weapons = Array(payload["weapons"]).map(&:to_s).uniq
      selected = ship["weapons"].select { |w| weapons.include?(w["id"]) && !w["destroyed"] }
      cost = speed + front_shields + aft_shields + (shield_repair ? 2 : 0) + selected.sum { |w| GameDefinition::WEAPONS.fetch(w[:type] || w["type"])[:energy] }
      raise IllegalAction, "Allocation needs #{cost} energy; ship has #{available_energy(ship)}" if cost > available_energy(ship)
      ship["allocation"] = { "speed" => speed, "shields" => { "front" => front_shields, "aft" => aft_shields }, "shield_repair" => shield_repair, "weapons" => selected.map { |w| w["id"] } }
      ship["allocation_set"] = true
      log!(state, "#{ship["name"]} has set its allocation.")
    end
    private_class_method :allocate!

    def self.lock_allocation!(state, player)
      require_phase!(state, "allocation")
      unallocated = ships_for(state, player).reject { |ship| ship["allocation_set"] }
      raise IllegalAction, "Set an allocation for every ship before committing the fleet" if unallocated.any?

      ships_for(state, player).each { |ship| ship["locked"] = true }
      log!(state, "#{player == "player_one" ? "Player One" : "Player Two"} locks allocation.")
      return unless state["ships"].all? { |ship| ship["locked"] || ship["destroyed"] }
      state["initiative"] = next_roll(state, stream: "setup") >= next_roll(state, stream: "setup") ? "player_one" : "player_two"
      state["phase"] = "impulse"
      state["activity_step"] = "draw"
      state["impulse_order"] = Array.new(3) { shuffled_card_indices(state) }
      state["tutorial_step"] = 1 if state["scenario"] == "tutorial"
      log!(state, "Initiative: #{label(state["initiative"])}. Draw the first impulse.")
    end
    private_class_method :lock_allocation!

    def self.draw_impulse!(state)
      require_phase!(state, "impulse")
      require_activity_step!(state, "draw")
      state["impulse"] += 1
      phase = (state["impulse"] - 1) / 4
      draw = (state["impulse"] - 1) % 4
      card_index = state.fetch("impulse_order")[phase][draw]
      card = GameDefinition::IMPULSE_DECKS[phase][card_index]
      state["impulse_card"] = card
      state["impulse_phase"] = phase + 1
      state["impulse_card_number"] = (phase * 4) + card_index + 1
      movers = state["ships"].reject { |ship| ship["destroyed"] || !card.include?(ship.dig("allocation", "speed")) }
      state["pending_movement"] = movers.sort_by do |ship|
        initiative_order = ship["player"] == state["initiative"] ? 0 : 1
        [ship.dig("allocation", "speed"), initiative_order]
      end.map { |ship| ship["id"] }
      state["activity_step"] = "movement"
      state["movement_stage"] = state["pending_movement"].any? ? "before" : nil
      log!(state, "Impulse #{state["impulse"]}: speeds #{card.join(", ")} may move.")
      if state["pending_movement"].empty?
        complete_movement!(state)
      else
        update_movement_options!(state)
      end
    end
    private_class_method :draw_impulse!

    def self.move_ship!(state, player, payload)
      require_phase!(state, "impulse")
      require_activity_step!(state, "movement")
      ship = owned_ship!(state, player, payload.fetch("ship_id"))
      raise IllegalAction, "Another ship moves first" unless state["pending_movement"].first == ship["id"]

      maneuver = payload.fetch("maneuver").to_s
      raise IllegalAction, "That movement is not legal" unless state["movement_options"].include?(maneuver)

      case maneuver
      when "forward"
        translate_ship!(state, ship, ship["position"][2], "moves forward")
      when "sideslip_left"
        translate_ship!(state, ship, (ship["position"][2] + 1) % 6, "side-slips port", sideslip: true)
      when "sideslip_right"
        translate_ship!(state, ship, (ship["position"][2] - 1) % 6, "side-slips starboard", sideslip: true)
      when "turn_left"
        ship["position"][2] = (ship["position"][2] + 1) % 6
        ship["movement"] = { "hexes_since_turn" => 0, "last_action" => "turn" }
        log!(state, "#{ship["name"]} turns sixty degrees to port.")
      when "turn_right"
        ship["position"][2] = (ship["position"][2] - 1) % 6
        ship["movement"] = { "hexes_since_turn" => 0, "last_action" => "turn" }
        log!(state, "#{ship["name"]} turns sixty degrees to starboard.")
      when "lose_movement"
        log!(state, "#{ship["name"]} has no legal maneuver and loses its movement.")
      end
      if ship["destroyed"] || !ship["special_available"] || payload["offer_special_after"] != true
        resolve_pending_movement!(state, ship)
      else
        state["movement_stage"] = "after"
        state["movement_options"] = []
        log!(state, "#{ship["name"]} may use its special maneuver after moving or complete movement.")
      end
    end
    private_class_method :move_ship!

    def self.finish_movement!(state, player, payload)
      require_phase!(state, "impulse")
      require_activity_step!(state, "movement")
      ship = owned_ship!(state, player, payload.fetch("ship_id"))
      raise IllegalAction, "Another ship moves first" unless state["pending_movement"].first == ship["id"]
      raise IllegalAction, "This ship has not completed its normal movement" unless state["movement_stage"] == "after"

      log!(state, "#{ship["name"]} completes movement without using its special maneuver.")
      resolve_pending_movement!(state, ship)
    end
    private_class_method :finish_movement!

    def self.legal_movement_actions(state, ship_id)
      ship = state["ships"].find { |entry| entry["id"] == ship_id && !entry["destroyed"] }
      return [] unless ship

      actions = []
      actions << "forward" if translation_open?(state, ship, ship["position"][2])
      if ship.dig("movement", "last_action") != "sideslip"
        actions << "sideslip_left" if translation_open?(state, ship, (ship["position"][2] + 1) % 6)
        actions << "sideslip_right" if translation_open?(state, ship, (ship["position"][2] - 1) % 6)
      end
      if ship.dig("movement", "hexes_since_turn").to_i >= turn_mode(ship)
        actions.concat(%w[turn_left turn_right])
      end
      actions.empty? ? ["lose_movement"] : actions
    end

    def self.turn_mode(ship)
      speed_band = case ship.dig("allocation", "speed").to_i
                   when 1..4 then 0
                   when 5..8 then 1
                   else 2
                   end
      { "small" => 0, "medium" => 1, "large" => 2 }.fetch(ship["size"]) + speed_band
    end

    def self.translation_open?(state, ship, direction)
      delta = DIRECTIONS[direction]
      destination = [ship["position"][0] + delta[0], ship["position"][1] + delta[1]]
      state["ships"].none? { |other| other["id"] != ship["id"] && !other["destroyed"] && other["position"].first(2) == destination }
    end
    private_class_method :translation_open?

    def self.translate_ship!(state, ship, direction, description, sideslip: false)
      delta = DIRECTIONS[direction]
      ship["position"][0] += delta[0]
      ship["position"][1] += delta[1]
      ship["movement_path"] << ship["position"].first(2)
      ship["movement"]["hexes_since_turn"] = ship.dig("movement", "hexes_since_turn").to_i + 1
      ship["movement"]["last_action"] = sideslip ? "sideslip" : "forward"
      unless on_board?(state, ship["position"])
        ship["destroyed"] = true
        log!(state, "#{ship["name"]} leaves the battle map and is destroyed.")
        check_victory!(state)
        return
      end
      log!(state, "#{ship["name"]} #{description}.")
    end
    private_class_method :translate_ship!

    def self.on_board?(state, position)
      column = position[0]
      row = position[1] + (column / 2)
      column.between?(0, state["board_size"] - 1) && row.between?(0, state["board_size"] - 1)
    end
    private_class_method :on_board?

    def self.resolve_pending_movement!(state, ship)
      state["pending_movement"].shift if state["pending_movement"].first == ship["id"]
      state["pending_movement"].reject! { |ship_id| state["ships"].find { |entry| entry["id"] == ship_id }&.dig("destroyed") }
      return if state["winner"]

      if state["pending_movement"].empty?
        complete_movement!(state)
      else
        state["movement_stage"] = "before"
        update_movement_options!(state)
      end
    end
    private_class_method :resolve_pending_movement!

    def self.update_movement_options!(state)
      state["movement_options"] = legal_movement_actions(state, state["pending_movement"].first)
    end
    private_class_method :update_movement_options!

    def self.complete_movement!(state)
      state["pending_movement"] = []
      state["movement_options"] = []
      state["movement_stage"] = nil
      state["activity_step"] = "launch"
      state["tutorial_step"] = 2 if state["scenario"] == "tutorial" && state["impulse"] == 1
      move_missiles!(state)
    end
    private_class_method :complete_movement!

    def self.launch_missile_action!(state, player, payload)
      require_phase!(state, "impulse")
      require_activity_step!(state, "launch")
      attacker = owned_ship!(state, player, payload.fetch("ship_id"))
      target = state["ships"].find { |ship| ship["id"] == payload.fetch("target_id") && ship["player"] != player && !ship["destroyed"] }
      raise IllegalAction, "No legal target" unless target
      weapon = attacker["weapons"].find { |entry| entry["id"] == payload.fetch("weapon_id") }
      raise IllegalAction, "Missile launcher unavailable" unless weapon && weapon["type"] == "missile" && !weapon["destroyed"] && !weapon["fired"]
      raise IllegalAction, "Missile launcher is empty" if weapon["ammo"].to_i <= 0

      launch_missile!(state, attacker, target, weapon)
    end
    private_class_method :launch_missile_action!

    def self.finish_launches!(state)
      require_phase!(state, "impulse")
      require_activity_step!(state, "launch")
      state["activity_step"] = "fire"
      log!(state, "Missile launches complete. Resolve direct weapons fire.")
    end
    private_class_method :finish_launches!

    def self.fire!(state, player, payload)
      require_phase!(state, "impulse")
      require_activity_step!(state, "fire")
      attacker = owned_ship!(state, player, payload.fetch("ship_id"))
      target_id = payload.fetch("target_id")
      target = state["ships"].find { |ship| ship["id"] == target_id && ship["player"] != player && !ship["destroyed"] }
      target_type = :ship
      unless target
        target = state["missiles"].find { |missile| missile["id"] == target_id && missile["owner"] != player }
        target_type = :missile
      end
      raise IllegalAction, "No legal target" unless target
      weapon = attacker["weapons"].find { |entry| entry["id"] == payload.fetch("weapon_id") }
      raise IllegalAction, "Weapon unavailable" unless weapon && !weapon["destroyed"] && !weapon["fired"]
      raise IllegalAction, "Missiles must be launched before direct weapons fire" if weapon["type"] == "missile"
      raise IllegalAction, "Weapon was not allocated energy" unless attacker["allocation"]["weapons"].include?(weapon["id"])

      range = distance(attacker["position"], target["position"])
      profile = GameDefinition::WEAPONS.fetch(weapon["type"].to_s)
      bracket = profile[:ranges].index { |limit| range <= limit }
      raise IllegalAction, "Target is out of range" unless bracket
      raise IllegalAction, "Target is outside this weapon's firing arc" unless target_in_arc?(attacker, target, weapon["arc"])
      weapon["fired"] = true
      roll = next_roll(state)
      to_hit = profile[:to_hit][bracket]
      to_hit += MISSILE_TARGET_TO_HIT_PENALTY if target_type == :missile
      hit = roll >= to_hit
      damage = nil
      if hit
        if target_type == :missile
          state["missiles"].delete_if { |missile| missile["id"] == target["id"] }
          log!(state, "#{attacker["name"]} destroys a seeker missile with #{profile[:label]} (#{roll}).")
        else
          damage = apply_damage!(state, target, profile[:damage][bracket], attacker["position"])
          log!(state, "#{attacker["name"]} hits #{target["name"]} with #{profile[:label]} (#{roll}).")
        end
      else
        target_name = target_type == :missile ? "a seeker missile" : target["name"]
        log!(state, "#{attacker["name"]} misses #{target_name} (#{roll}).")
      end
      record_combat_event!(state, attacker:, target:, target_type:, weapon:, profile:, roll:, to_hit:, hit:, damage:)
      state["tutorial_step"] = 3 if state["scenario"] == "tutorial"
      check_victory!(state)
    end
    private_class_method :fire!

    def self.record_combat_event!(state, attacker:, target:, target_type:, weapon:, profile:, roll:, to_hit:, hit:, damage: nil)
      event_id = state["next_combat_event_id"]
      state["next_combat_event_id"] += 1
      state["combat_events"] << {
        "id" => event_id,
        "kind" => "weapon_fire",
        "weapon_type" => weapon["type"],
        "weapon_label" => profile[:label],
        "attacker_id" => attacker["id"],
        "attacker_name" => attacker["name"],
        "target_id" => target["id"],
        "target_name" => target_type == :missile ? "Seeker missile" : target["name"],
        "target_type" => target_type.to_s,
        "origin" => attacker["position"].dup,
        "target_position" => target["position"].dup,
        "roll" => roll,
        "to_hit" => to_hit,
        "hit" => hit,
        "damage" => damage
      }
      state["combat_events"] = state["combat_events"].last(24)
    end
    private_class_method :record_combat_event!

    def self.target_in_arc?(attacker, target, arcs)
      bearing = DIRECTIONS.each_index.select do |direction|
        delta = DIRECTIONS[direction]
        distance([attacker["position"][0] + delta[0], attacker["position"][1] + delta[1]], target["position"]) < distance(attacker["position"], target["position"])
      end
      facing = attacker["position"][2]
      permitted = Array(arcs).flat_map do |arc|
        offsets = { "F" => [-1, 0, 1], "L" => [1, 2, 3], "A" => [2, 3, 4], "R" => [3, 4, 5] }.fetch(arc, [])
        offsets.map { |offset| (facing + offset) % 6 }
      end
      (bearing & permitted).any?
    end
    private_class_method :target_in_arc?

    def self.launch_missile!(state, attacker, target, weapon)
      missile_id = state["next_missile_id"]
      state["next_missile_id"] += 1
      state["missiles"] << {
        "id" => "missile-#{missile_id}", "owner" => attacker["player"], "fleet" => attacker["fleet"],
        "launcher_ship_id" => attacker["id"], "target_id" => target["id"], "position" => attacker["position"].dup,
        "launched_turn" => state["turn"], "launched_impulse" => state["impulse"]
      }
      weapon["fired"] = true
      weapon["ammo"] -= 1
      log!(state, "#{attacker["name"]} launches a seeker missile at #{target["name"]}.")
    end
    private_class_method :launch_missile!

    def self.move_missiles!(state)
      surviving = []
      state["missiles"].each do |missile|
        target = state["ships"].find { |ship| ship["id"] == missile["target_id"] && !ship["destroyed"] }
        unless target
          log!(state, "A seeker missile loses its target and burns out.")
          next
        end

        impacted = false
        2.times do
          origin = missile["position"].dup
          direction = DIRECTIONS.each_index.min_by do |index|
            delta = DIRECTIONS[index]
            distance([missile["position"][0] + delta[0], missile["position"][1] + delta[1]], target["position"])
          end
          delta = DIRECTIONS[direction]
          missile["position"][0] += delta[0]
          missile["position"][1] += delta[1]
          missile["position"][2] = direction
          next unless missile["position"].first(2) == target["position"].first(2)

          damage = apply_damage!(state, target, 3, origin)
          log!(state, "Seeker missile hits #{target["name"]} for 3 damage.")
          record_missile_impact!(state, missile, target, origin, damage)
          check_victory!(state)
          impacted = true
          break
        end
        surviving << missile unless impacted
      end
      state["missiles"] = surviving
    end
    private_class_method :move_missiles!

    def self.record_missile_impact!(state, missile, target, origin, damage)
      event_id = state["next_combat_event_id"]
      state["next_combat_event_id"] += 1
      state["combat_events"] << {
        "id" => event_id,
        "kind" => "missile_impact",
        "missile_id" => missile["id"],
        "weapon_type" => "missile",
        "weapon_label" => "Seeker missile",
        "attacker_id" => missile["launcher_ship_id"],
        "attacker_name" => "Seeker missile",
        "target_id" => target["id"],
        "target_name" => target["name"],
        "target_type" => "ship",
        "origin" => origin,
        "target_position" => target["position"].dup,
        "roll" => "AUTO",
        "to_hit" => 0,
        "hit" => true,
        "damage" => damage
      }
      state["combat_events"] = state["combat_events"].last(24)
    end
    private_class_method :record_missile_impact!

    def self.special!(state, player, payload)
      require_phase!(state, "impulse")
      require_activity_step!(state, "movement")
      ship = owned_ship!(state, player, payload.fetch("ship_id"))
      raise IllegalAction, "Another ship moves first" unless state["pending_movement"].first == ship["id"]
      raise IllegalAction, "Special maneuver unavailable" unless ship["special_available"]
      movement_stage = state["movement_stage"]
      maneuver = payload.fetch("maneuver")
      case maneuver
      when "bootlegger"
        ship["position"][2] = payload.fetch("direction").to_i % 6
        ship["movement"] = { "hexes_since_turn" => 0, "last_action" => "turn" }
      when "quick_stop"
        ship["allocation"]["speed"] = 0
      when "emergency_power"
        raise IllegalAction, "The hex ahead is occupied" unless translation_open?(state, ship, ship["position"][2])
        translate_ship!(state, ship, ship["position"][2], "surges forward on emergency power")
      else raise IllegalAction, "Unknown maneuver"
      end
      ship["special_available"] = false
      log!(state, "#{ship["name"]} executes #{maneuver.tr("_", " ")}.")
      if maneuver == "quick_stop" || ship["destroyed"] || movement_stage == "after"
        resolve_pending_movement!(state, ship)
      else
        update_movement_options!(state)
      end
    end
    private_class_method :special!

    def self.finish_impulse!(state)
      require_phase!(state, "impulse")
      require_activity_step!(state, "fire")
      if state["impulse"] >= 12
        finish_turn!(state)
      else
        state["activity_step"] = "draw"
        state["impulse_card"] = nil
        state["impulse_phase"] = nil
        state["impulse_card_number"] = nil
        log!(state, "Impulse #{state["impulse"]} complete. Draw the next movement card.")
      end
    end
    private_class_method :finish_impulse!

    def self.apply_damage!(state, target, amount, source_position)
      result = {
        "amount" => amount,
        "shield_bank" => nil,
        "reinforcement_absorbed" => 0,
        "shield_absorbed" => 0,
        "hull" => 0,
        "engines" => 0,
        "weapons" => [],
        "destroyed" => false,
        "before" => damage_snapshot(target)
      }
      shield = shield_bank_for(target, source_position)
      result["shield_bank"] = shield
      reinforcement = target.dig("allocation", "shields", shield).to_i
      reinforced = [reinforcement, amount].min
      result["reinforcement_absorbed"] = reinforced
      target["allocation"]["shields"][shield] -= reinforced
      amount -= reinforced
      absorbed = [target["shields"][shield], amount].min
      result["shield_absorbed"] = absorbed
      target["shields"][shield] -= absorbed
      remaining = amount - absorbed
      if remaining.positive?
        remaining.times do
          case next_roll(state, stream: "damage")
          when 1..3
            target["hull"] -= 1
            result["hull"] += 1
          when 4..5
            target["damage"]["engines"] += 1
            result["engines"] += 1
          else
            available = target["weapons"].find { |weapon| !weapon["destroyed"] }
            if available
              available["destroyed"] = true
              result["weapons"] << { "id" => available["id"], "mount" => available["mount"], "type" => available["type"] }
            else
              target["hull"] -= 1
              result["hull"] += 1
            end
          end
        end
      end
      target["destroyed"] = true if target["hull"] <= 0
      result["destroyed"] = target["destroyed"]
      result["after"] = damage_snapshot(target)
      result
    end
    private_class_method :apply_damage!

    def self.shield_bank_for(target, source_position)
      range = distance(target["position"], source_position)
      incoming_directions = DIRECTIONS.each_index.select do |direction|
        delta = DIRECTIONS[direction]
        distance([target["position"][0] + delta[0], target["position"][1] + delta[1]], source_position) < range
      end
      forward_directions = [-1, 0, 1].map { |offset| (target["position"][2] + offset) % 6 }
      (incoming_directions & forward_directions).any? ? "front" : "aft"
    end
    private_class_method :shield_bank_for

    def self.damage_snapshot(ship)
      {
        "shields" => ship["shields"].dup,
        "shield_reinforcement" => ship.dig("allocation", "shields").dup,
        "hull" => ship["hull"],
        "engines" => ship.dig("damage", "engines").to_i,
        "destroyed_weapon_ids" => ship["weapons"].select { |weapon| weapon["destroyed"] }.map { |weapon| weapon["id"] },
        "destroyed" => ship["destroyed"]
      }
    end
    private_class_method :damage_snapshot

    def self.finish_turn!(state)
      check_victory!(state)
      return if state["winner"]
      state["turn"] += 1; state["phase"] = "allocation"; state["impulse"] = 0
      state["activity_step"] = "allocation"; state["impulse_card"] = nil; state["impulse_phase"] = nil; state["impulse_card_number"] = nil
      state["impulse_order"] = nil; state["pending_movement"] = []; state["movement_options"] = []
      state["ships"].each do |ship|
        next if ship["destroyed"]

        repair_shield!(state, ship)
        ship["allocation_set"] = false
        ship["locked"] = false
        ship["allocation"] = { "speed" => 0, "shields" => { "front" => 0, "aft" => 0 }, "shield_repair" => nil, "weapons" => [] }
        ship["weapons"].each { |weapon| weapon["fired"] = false }
        ship["movement"] = { "hexes_since_turn" => 0, "last_action" => nil }
        ship["movement_path"] = [ship["position"].first(2)]
      end
      log!(state, "Turn #{state["turn"]}. Allocate energy in secret.")
    end
    private_class_method :finish_turn!

    def self.repair_shield!(state, ship)
      bank = ship.dig("allocation", "shield_repair")
      return unless %w[front aft].include?(bank)

      maximum = maximum_shields(ship, bank)
      return if ship.dig("shields", bank).to_i >= maximum

      ship["shields"][bank] += 1
      log!(state, "#{ship["name"]} repairs one #{bank} shield box.")
    end
    private_class_method :repair_shield!

    def self.shuffled_card_indices(state)
      indices = [0, 1, 2, 3]
      3.downto(1) do |index|
        swap = (next_roll(state, stream: "setup") - 1) % (index + 1)
        indices[index], indices[swap] = indices[swap], indices[index]
      end
      indices
    end
    private_class_method :shuffled_card_indices
    def self.distance(a, b)
      ((a[0] - b[0]).abs + (a[1] - b[1]).abs + ((a[0] + a[1]) - (b[0] + b[1])).abs) / 2
    end
    def self.initial_rng
      {
        "algorithm" => "sha256-counter-v1",
        "streams" => RNG_STREAMS.index_with { 0 }
      }
    end
    private_class_method :initial_rng

    def self.normalized_rng(rng)
      defaults = initial_rng
      streams = rng.is_a?(Hash) && rng["streams"].is_a?(Hash) ? rng["streams"] : {}
      defaults["streams"].each_key do |stream|
        defaults["streams"][stream] = streams[stream].to_i.clamp(0, RNG_MASK)
      end
      defaults
    end
    private_class_method :normalized_rng

    def self.next_roll(state, stream: "attack")
      raise ArgumentError, "Unknown random stream" unless RNG_STREAMS.include?(stream)

      unless state["rng"].is_a?(Hash) && state.dig("rng", "streams").is_a?(Hash) && state["rng"]["streams"].key?(stream)
        state["rng"] = normalized_rng(state["rng"])
      end
      loop do
        counter = state.dig("rng", "streams", stream).to_i & RNG_MASK
        # Hashing seed, stream, and counter gives each subsystem an independent,
        # reproducible sequence. Rejecting the four values above this boundary
        # removes the tiny modulo bias that `% 6` would otherwise introduce.
        value = Digest::SHA256.digest("#{state.fetch("seed", 17)}:#{stream}:#{counter}").unpack1("L>")
        state["rng"]["streams"][stream] = (counter + 1) & RNG_MASK
        return (value % 6) + 1 if value < RNG_ACCEPTANCE_LIMIT
      end
    end
    private_class_method :next_roll
    def self.ships_for(state, player) = state["ships"].select { |ship| ship["player"] == player && !ship["destroyed"] }
    def self.owned_ship!(state, player, id) = ships_for(state, player).find { |ship| ship["id"] == id } || raise(IllegalAction, "Ship is not under your command")
    def self.require_phase!(state, phase)
      return if state["phase"] == phase

      raise IllegalAction, "Action is only available during #{phase}"
    end
    def self.require_activity_step!(state, step)
      return if state["activity_step"] == step

      raise IllegalAction, "Finish the #{state["activity_step"].to_s.tr("_", " ")} step first"
    end
    def self.available_energy(ship) = [ship["energy"] - ship["damage"]["engines"], 0].max
    def self.shield_cap(ship) = { "small" => 1, "medium" => 2, "large" => 3 }.fetch(ship["size"])
    def self.maximum_shields(ship, bank) = ship.fetch("max_#{bank}_shields")
    def self.label(player) = player == "player_one" ? "Player One" : "Player Two"
    def self.log!(state, entry) = state["log"] << entry
    def self.check_victory!(state)
      alive = state["ships"].reject { |ship| ship["destroyed"] }.map { |ship| ship["player"] }.uniq
      state["winner"] = alive.first if alive.length == 1
      log!(state, "#{label(state["winner"])} wins the battle!") if state["winner"]
    end
    private_class_method :ships_for, :owned_ship!, :require_phase!, :require_activity_step!, :available_energy, :shield_cap, :maximum_shields, :label, :log!, :check_victory!
  end
end
