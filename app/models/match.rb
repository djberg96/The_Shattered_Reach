# frozen_string_literal: true

class Match < ApplicationRecord
  validates :state, presence: true

  def game_state = ShatteredReach::RulesEngine.normalize!(state.deep_dup)

  def apply!(player:, action:, payload: {})
    self.state = ShatteredReach::RulesEngine.apply(game_state, player: player, action: action, payload: payload)
    if state["solo"] && player == "player_one"
      run_solo_opponent! if action.to_s == "lock_allocation" && state["phase"] == "allocation"
      run_solo_combat! if action.to_s == "advance_impulse" && state["phase"] == "impulse" && !state["winner"]
    end
    save!
  end

  private

  def run_solo_opponent!
    allocation = ShatteredReach::BaselinePilot.allocation(state, "player_two")
    self.state = ShatteredReach::RulesEngine.apply(state, player: "player_two", action: "allocate", payload: allocation)
    self.state = ShatteredReach::RulesEngine.apply(state, player: "player_two", action: "lock_allocation", payload: {})
  end

  def run_solo_combat!
    decision = ShatteredReach::BaselinePilot.combat_action(state, "player_two")
    return unless decision

    self.state = ShatteredReach::RulesEngine.apply(state, player: "player_two", action: decision.fetch(:action), payload: decision.fetch(:payload))
  end
end
