# frozen_string_literal: true

class Match < ApplicationRecord
  validates :state, presence: true

  def game_state = state.deep_dup

  def apply!(player:, action:, payload: {})
    self.state = ShatteredReach::RulesEngine.apply(game_state, player: player, action: action, payload: payload)
    run_solo_opponent! if state["solo"] && player == "player_one" && action.to_s == "lock_allocation" && state["phase"] == "allocation"
    save!
  end

  private

  def run_solo_opponent!
    allocation = ShatteredReach::BaselinePilot.allocation(state, "player_two")
    self.state = ShatteredReach::RulesEngine.apply(state, player: "player_two", action: "allocate", payload: allocation)
    self.state = ShatteredReach::RulesEngine.apply(state, player: "player_two", action: "lock_allocation", payload: {})
  end
end
