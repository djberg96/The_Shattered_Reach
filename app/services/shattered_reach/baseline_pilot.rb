# frozen_string_literal: true

module ShatteredReach
  # A deliberately transparent first-pass opponent: it spends energy on closing
  # distance, then charges weapons it can plausibly bring to bear.
  class BaselinePilot
    def self.allocation(state, player)
      ship = state.fetch("ships").find { |entry| entry["player"] == player && !entry["destroyed"] }
      enemy = state.fetch("ships").find { |entry| entry["player"] != player && !entry["destroyed"] }
      return {} unless ship && enemy

      range = RulesEngine.send(:distance, ship["position"], enemy["position"])
      speed = range > 6 ? [4, ship["energy"]].min : 2
      budget = [ship["energy"] - ship.dig("damage", "engines").to_i - speed, 0].max
      weapons = ship["weapons"].reject { |weapon| weapon["destroyed"] || weapon["type"] == "missile" }.each_with_object([]) do |weapon, selected|
        cost = GameDefinition::WEAPONS.fetch(weapon["type"])[:energy]
        next if cost > budget

        selected << weapon["id"]
        budget -= cost
      end
      { "ship_id" => ship["id"], "speed" => speed, "front_shields" => 0, "aft_shields" => 0, "weapons" => weapons }
    end

    def self.combat_action(state, player)
      ship = state.fetch("ships").find { |entry| entry["player"] == player && !entry["destroyed"] }
      ship_target = state.fetch("ships").find { |entry| entry["player"] != player && !entry["destroyed"] }
      return unless ship && ship_target

      weapons = ship["weapons"].select do |candidate|
        next if candidate["destroyed"] || candidate["fired"] || candidate["type"] == "missile"
        next unless ship.dig("allocation", "weapons").include?(candidate["id"])

        true
      end

      targets = state.fetch("missiles").select { |missile| missile["owner"] != player }.sort_by do |missile|
        RulesEngine.distance(ship["position"], missile["position"])
      end
      targets << ship_target

      targets.each do |target|
        range = RulesEngine.distance(ship["position"], target["position"])
        weapon = weapons.find do |candidate|
          GameDefinition::WEAPONS.fetch(candidate["type"])[:ranges].any? { |limit| range <= limit } &&
            RulesEngine.send(:target_in_arc?, ship, target, candidate["arc"])
        end
        next unless weapon

        return { action: "fire", payload: { "ship_id" => ship["id"], "target_id" => target["id"], "weapon_id" => weapon["id"] } }
      end

      nil
    end

    def self.missile_action(state, player)
      ship = state.fetch("ships").find { |entry| entry["player"] == player && !entry["destroyed"] }
      target = state.fetch("ships").find { |entry| entry["player"] != player && !entry["destroyed"] }
      return unless ship && target

      weapon = ship["weapons"].find do |candidate|
        candidate["type"] == "missile" && !candidate["destroyed"] && !candidate["fired"] && candidate["ammo"].to_i.positive?
      end
      return unless weapon

      { action: "launch_missile", payload: { "ship_id" => ship["id"], "target_id" => target["id"], "weapon_id" => weapon["id"] } }
    end

    def self.movement_action(state, player)
      ship_id = state.fetch("pending_movement").first
      ship = state.fetch("ships").find { |entry| entry["id"] == ship_id && entry["player"] == player && !entry["destroyed"] }
      target = state.fetch("ships").find { |entry| entry["player"] != player && !entry["destroyed"] }
      return unless ship && target

      options = state.fetch("movement_options")
      translations = options & %w[forward sideslip_left sideslip_right]
      maneuver = translations.min_by do |candidate|
        direction = case candidate
                    when "sideslip_left" then (ship["position"][2] + 1) % 6
                    when "sideslip_right" then (ship["position"][2] - 1) % 6
                    else ship["position"][2]
                    end
        delta = RulesEngine::DIRECTIONS[direction]
        RulesEngine.distance([ship["position"][0] + delta[0], ship["position"][1] + delta[1]], target["position"])
      end
      maneuver ||= (options & %w[turn_left turn_right]).min_by do |candidate|
        facing = (ship["position"][2] + (candidate == "turn_left" ? 1 : -1)) % 6
        delta = RulesEngine::DIRECTIONS[facing]
        RulesEngine.distance([ship["position"][0] + delta[0], ship["position"][1] + delta[1]], target["position"])
      end
      maneuver ||= options.first
      return unless maneuver

      { action: "move_ship", payload: { "ship_id" => ship["id"], "maneuver" => maneuver } }
    end
  end
end
