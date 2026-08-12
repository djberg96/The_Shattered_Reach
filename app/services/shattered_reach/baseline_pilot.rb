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
      target = state.fetch("ships").find { |entry| entry["player"] != player && !entry["destroyed"] }
      return unless ship && target

      range = RulesEngine.distance(ship["position"], target["position"])
      weapon = ship["weapons"].find do |candidate|
        next if candidate["destroyed"] || candidate["fired"]
        next if candidate["type"] == "missile" && candidate["ammo"].to_i <= 0
        next unless candidate["type"] == "missile" || ship.dig("allocation", "weapons").include?(candidate["id"])

        GameDefinition::WEAPONS.fetch(candidate["type"])[:ranges].any? { |limit| range <= limit }
      end
      if weapon
        return { action: "fire", payload: { "ship_id" => ship["id"], "target_id" => target["id"], "weapon_id" => weapon["id"] } }
      end

      return unless ship["special_available"]

      { action: "special", payload: { "ship_id" => ship["id"], "maneuver" => "emergency_power" } }
    end
  end
end
