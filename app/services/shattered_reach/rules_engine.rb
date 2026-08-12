# frozen_string_literal: true

module ShatteredReach
  class RulesEngine
    BOARD_SIZES = [12, 15, 20].freeze
    DIRECTIONS = [[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]].freeze

    class IllegalAction < StandardError; end

    def self.start(scenario: :skirmish, solo: false, board_size: 15)
      board_size = board_size.to_i
      board_size = 15 unless BOARD_SIZES.include?(board_size)
      positions = starting_positions(board_size)
      blueprint = scenario == :tutorial ? [%w[aurelian_frigate veyr_frigate]] : [%w[aurelian_cruiser kestrel_cruiser]]
      ships = blueprint.first.each_with_index.map do |ship_key, index|
        build_ship(ship_key, index.zero? ? "player_one" : "player_two", positions[index])
      end
      {
        "version" => GameDefinition::VERSION, "scenario" => scenario.to_s, "solo" => solo, "board_size" => board_size, "turn" => 1,
        "phase" => "allocation", "impulse" => 0, "seed" => 17, "initiative" => nil,
        "ships" => ships, "missiles" => [], "next_missile_id" => 1,
        "log" => ["Battle stations. Allocate energy in secret."], "winner" => nil,
        "tutorial_step" => scenario == :tutorial ? 0 : nil
      }
    end

    def self.starting_positions(board_size)
      separation = (board_size - 3).clamp(10, 15)
      left_column = ((board_size - 1 - separation) / 2.0).floor
      right_column = left_column + separation
      row = board_size / 2

      [[left_column, row - (left_column / 2), 0], [right_column, row - (right_column / 2), 3]]
    end
    private_class_method :starting_positions

    def self.apply(state, player:, action:, payload: {})
      state = Marshal.load(Marshal.dump(state))
      normalize!(state)
      return state if state["winner"]

      case action.to_s
      when "allocate" then allocate!(state, player, payload)
      when "lock_allocation" then lock_allocation!(state, player)
      when "advance_impulse" then advance_impulse!(state)
      when "fire" then fire!(state, player, payload)
      when "special" then special!(state, player, payload)
      else raise IllegalAction, "Unknown action: #{action}"
      end
      state
    end

    def self.normalize!(state)
      unless state.key?("board_size")
        state["board_size"] = 15
        if state["turn"] == 1 && state["phase"] == "allocation" && state["impulse"].to_i.zero?
          starting_positions(15).each_with_index { |position, index| state["ships"][index]["position"] = position if state["ships"][index] }
        end
      end
      migrate_loadouts!(state) if state["version"] != GameDefinition::VERSION
      state["missiles"] ||= []
      state["next_missile_id"] ||= state["missiles"].length + 1

      state["ships"].each do |ship|
        spec = GameDefinition::SHIPS[ship["key"]]
        next unless spec

        ship["max_front_shields"] ||= spec[:front_shields]
        ship["max_aft_shields"] ||= spec[:aft_shields]
        allocation = ship["allocation"] ||= { "speed" => 0, "shields" => {}, "weapons" => [] }
        unless allocation["shields"].is_a?(Hash)
          allocation["shields"] = { "front" => allocation["shields"].to_i, "aft" => 0 }
        end
        allocation["shields"]["front"] ||= 0
        allocation["shields"]["aft"] ||= 0
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

    def self.build_ship(key, player, position)
      spec = GameDefinition::SHIPS.fetch(key)
      {
        "id" => "#{player}-#{key}", "key" => key, "player" => player, "name" => spec[:name], "fleet" => spec[:fleet],
        "size" => spec[:size], "position" => position, "energy" => spec[:energy], "hull" => spec[:hull], "max_hull" => spec[:hull],
        "shields" => { "front" => spec[:front_shields], "aft" => spec[:aft_shields] }, "max_front_shields" => spec[:front_shields], "max_aft_shields" => spec[:aft_shields],
        "allocation" => { "speed" => 0, "shields" => { "front" => 0, "aft" => 0 }, "weapons" => [] },
        "locked" => false, "special_available" => spec[:size] != "large", "weapons" => spec[:weapons].map.with_index { |w, i| w.stringify_keys.merge("id" => "w#{i}", "destroyed" => false, "fired" => false) },
        "damage" => { "engines" => 0, "weapons" => 0 }, "destroyed" => false
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
      weapons = Array(payload["weapons"]).map(&:to_s).uniq
      selected = ship["weapons"].select { |w| weapons.include?(w["id"]) && !w["destroyed"] }
      cost = speed + front_shields + aft_shields + selected.sum { |w| GameDefinition::WEAPONS.fetch(w[:type] || w["type"])[:energy] }
      raise IllegalAction, "Allocation needs #{cost} energy; ship has #{available_energy(ship)}" if cost > available_energy(ship)
      ship["allocation"] = { "speed" => speed, "shields" => { "front" => front_shields, "aft" => aft_shields }, "weapons" => selected.map { |w| w["id"] } }
      log!(state, "#{ship["name"]} has set its allocation.")
    end
    private_class_method :allocate!

    def self.lock_allocation!(state, player)
      require_phase!(state, "allocation")
      ships_for(state, player).each { |ship| ship["locked"] = true }
      log!(state, "#{player == "player_one" ? "Player One" : "Player Two"} locks allocation.")
      return unless state["ships"].all? { |ship| ship["locked"] || ship["destroyed"] }
      state["initiative"] = next_roll(state) >= next_roll(state) ? "player_one" : "player_two"
      state["phase"] = "impulse"
      state["tutorial_step"] = 1 if state["scenario"] == "tutorial"
      log!(state, "Initiative: #{label(state["initiative"])}. Draw the first impulse.")
    end
    private_class_method :lock_allocation!

    def self.advance_impulse!(state)
      require_phase!(state, "impulse")
      state["impulse"] += 1
      if state["impulse"] > 12
        finish_turn!(state)
        return
      end
      card = impulse_card(state)
      state["ships"].reject { |ship| ship["destroyed"] }.sort_by { |ship| ship["allocation"]["speed"] }.each do |ship|
        move_forward!(ship) if card.include?(ship["allocation"]["speed"])
      end
      state["tutorial_step"] = 2 if state["scenario"] == "tutorial" && state["impulse"] == 1
      log!(state, "Impulse #{state["impulse"]}: speeds #{card.join(", ")} move.")
      move_missiles!(state)
    end
    private_class_method :advance_impulse!

    def self.fire!(state, player, payload)
      require_phase!(state, "impulse")
      raise IllegalAction, "Draw an impulse card before launching or firing weapons" if state["impulse"].to_i.zero?
      attacker = owned_ship!(state, player, payload.fetch("ship_id"))
      target = state["ships"].find { |ship| ship["id"] == payload.fetch("target_id") && ship["player"] != player && !ship["destroyed"] }
      raise IllegalAction, "No legal target" unless target
      weapon = attacker["weapons"].find { |entry| entry["id"] == payload.fetch("weapon_id") }
      raise IllegalAction, "Weapon unavailable" unless weapon && !weapon["destroyed"] && !weapon["fired"]
      raise IllegalAction, "Missile launcher is empty" if weapon["type"] == "missile" && weapon["ammo"].to_i <= 0
      raise IllegalAction, "Weapon was not allocated energy" unless weapon["type"] == "missile" || attacker["allocation"]["weapons"].include?(weapon["id"])
      if weapon["type"] == "missile"
        launch_missile!(state, attacker, target, weapon)
        state["tutorial_step"] = 3 if state["scenario"] == "tutorial"
        return
      end

      range = distance(attacker["position"], target["position"])
      profile = GameDefinition::WEAPONS.fetch(weapon["type"].to_s)
      bracket = profile[:ranges].index { |limit| range <= limit }
      raise IllegalAction, "Target is out of range" unless bracket
      weapon["fired"] = true
      roll = next_roll(state)
      hit = roll >= profile[:to_hit][bracket]
      if hit
        apply_damage!(state, target, profile[:damage][bracket], attacker)
        log!(state, "#{attacker["name"]} hits #{target["name"]} with #{profile[:label]} (#{roll}).")
      else
        log!(state, "#{attacker["name"]} misses #{target["name"]} (#{roll}).")
      end
      state["tutorial_step"] = 3 if state["scenario"] == "tutorial"
      check_victory!(state)
    end
    private_class_method :fire!

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
          direction = DIRECTIONS.each_index.min_by do |index|
            delta = DIRECTIONS[index]
            distance([missile["position"][0] + delta[0], missile["position"][1] + delta[1]], target["position"])
          end
          delta = DIRECTIONS[direction]
          missile["position"][0] += delta[0]
          missile["position"][1] += delta[1]
          missile["position"][2] = direction
          next unless missile["position"].first(2) == target["position"].first(2)

          apply_damage!(state, target, 3, nil)
          log!(state, "Seeker missile hits #{target["name"]} for 3 damage.")
          check_victory!(state)
          impacted = true
          break
        end
        surviving << missile unless impacted
      end
      state["missiles"] = surviving
    end
    private_class_method :move_missiles!

    def self.special!(state, player, payload)
      require_phase!(state, "impulse")
      ship = owned_ship!(state, player, payload.fetch("ship_id"))
      raise IllegalAction, "Special maneuver unavailable" unless ship["special_available"]
      maneuver = payload.fetch("maneuver")
      case maneuver
      when "bootlegger" then ship["position"][2] = payload.fetch("direction").to_i % 6
      when "quick_stop" then ship["allocation"]["speed"] = 0
      when "emergency_power" then move_forward!(ship)
      else raise IllegalAction, "Unknown maneuver"
      end
      ship["special_available"] = false
      log!(state, "#{ship["name"]} executes #{maneuver.tr("_", " ")}.")
    end
    private_class_method :special!

    def self.apply_damage!(state, target, amount, _attacker)
      shield = target["shields"]["front"] > 0 ? "front" : "aft"
      reinforcement = target.dig("allocation", "shields", shield).to_i
      reinforced = [reinforcement, amount].min
      target["allocation"]["shields"][shield] -= reinforced
      amount -= reinforced
      absorbed = [target["shields"][shield], amount].min
      target["shields"][shield] -= absorbed
      remaining = amount - absorbed
      return if remaining.zero?
      remaining.times do
        case next_roll(state)
        when 1..3 then target["hull"] -= 1
        when 4..5 then target["damage"]["engines"] += 1
        else
          available = target["weapons"].find { |weapon| !weapon["destroyed"] }
          available ? available["destroyed"] = true : target["hull"] -= 1
        end
      end
      target["destroyed"] = true if target["hull"] <= 0
    end
    private_class_method :apply_damage!

    def self.finish_turn!(state)
      check_victory!(state)
      return if state["winner"]
      state["turn"] += 1; state["phase"] = "allocation"; state["impulse"] = 0
      state["ships"].each do |ship|
        next if ship["destroyed"]

        ship["locked"] = false
        ship["allocation"] = { "speed" => 0, "shields" => { "front" => 0, "aft" => 0 }, "weapons" => [] }
        ship["weapons"].each { |weapon| weapon["fired"] = false }
      end
      log!(state, "Turn #{state["turn"]}. Allocate energy in secret.")
    end
    private_class_method :finish_turn!

    def self.impulse_card(state)
      phase = (state["impulse"] - 1) / 4
      GameDefinition::IMPULSE_DECKS[phase][(state["turn"] - 1) % 4]
    end
    private_class_method :impulse_card
    def self.distance(a, b)
      ((a[0] - b[0]).abs + (a[1] - b[1]).abs + ((a[0] + a[1]) - (b[0] + b[1])).abs) / 2
    end
    def self.move_forward!(ship)
      delta = DIRECTIONS[ship["position"][2]]; ship["position"][0] += delta[0]; ship["position"][1] += delta[1]
    end
    private_class_method :move_forward!
    def self.next_roll(state)
      state["seed"] = (state["seed"].to_i * 1103515245 + 12345) % 2**31; (state["seed"] % 6) + 1
    end
    private_class_method :next_roll
    def self.ships_for(state, player) = state["ships"].select { |ship| ship["player"] == player && !ship["destroyed"] }
    def self.owned_ship!(state, player, id) = ships_for(state, player).find { |ship| ship["id"] == id } || raise(IllegalAction, "Ship is not under your command")
    def self.require_phase!(state, phase)
      return if state["phase"] == phase

      raise IllegalAction, "Action is only available during #{phase}"
    end
    def self.available_energy(ship) = [ship["energy"] - ship["damage"]["engines"], 0].max
    def self.shield_cap(ship) = { "small" => 1, "medium" => 2, "large" => 3 }.fetch(ship["size"])
    def self.label(player) = player == "player_one" ? "Player One" : "Player Two"
    def self.log!(state, entry) = state["log"] << entry
    def self.check_victory!(state)
      alive = state["ships"].reject { |ship| ship["destroyed"] }.map { |ship| ship["player"] }.uniq
      state["winner"] = alive.first if alive.length == 1
      log!(state, "#{label(state["winner"])} wins the battle!") if state["winner"]
    end
    private_class_method :ships_for, :owned_ship!, :require_phase!, :available_energy, :shield_cap, :label, :log!, :check_victory!
  end
end
