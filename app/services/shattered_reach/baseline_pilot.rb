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
      weapons = ship["weapons"].reject { |weapon| weapon["destroyed"] || weapon["type"] == "missile" }.map { |weapon| weapon["id"] }
      energy_cost = weapons.sum { |id| GameDefinition::WEAPONS.fetch(ship["weapons"].find { |weapon| weapon["id"] == id }["type"])[ :energy ] }
      weapons = [] if speed + energy_cost > ship["energy"]
      { "ship_id" => ship["id"], "speed" => speed, "shields" => 0, "weapons" => weapons }
    end
  end
end
