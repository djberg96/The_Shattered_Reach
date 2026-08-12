# frozen_string_literal: true

class Match < ApplicationRecord
  validates :state, presence: true

  def game_state = ShatteredReach::RulesEngine.normalize!(state.deep_dup)

  def apply!(player:, action:, payload: {})
    current_state = game_state
    if action.to_s == "undo_movement"
      restore_movement_checkpoint!(current_state, player)
      save!
      return
    end

    movement_checkpoint = movement_action?(action) ? build_movement_checkpoint(current_state, player) : nil
    current_state.delete("movement_undo")
    self.state = ShatteredReach::RulesEngine.apply(current_state, player: player, action: action, payload: payload)
    if state["solo"] && player == "player_one"
      run_solo_opponent! if action.to_s == "lock_allocation" && state["phase"] == "allocation"
      if %w[advance_impulse move_ship special].include?(action.to_s) && state["phase"] == "impulse" && !state["winner"]
        run_solo_movement!
        run_solo_launch! if state["activity_step"] == "launch"
      end
      run_solo_combat! if action.to_s == "finish_launches" && state["activity_step"] == "fire" && !state["winner"]
    end
    state["movement_undo"] = movement_checkpoint if movement_checkpoint
    save!
  end

  private

  def movement_action?(action) = %w[move_ship special].include?(action.to_s)

  def build_movement_checkpoint(current_state, player)
    snapshot = current_state.deep_dup
    snapshot.delete("movement_undo")
    { "player" => player, "state" => snapshot }
  end

  def restore_movement_checkpoint!(current_state, player)
    checkpoint = current_state["movement_undo"]
    unless checkpoint && checkpoint["player"] == player && checkpoint["state"].is_a?(Hash)
      raise ShatteredReach::RulesEngine::IllegalAction, "No movement is available to undo"
    end

    restored = checkpoint["state"].deep_dup
    restored.delete("movement_undo")
    restored["log"] << "#{player == "player_one" ? "Player One" : "Player Two"} undoes the last movement decision."
    self.state = ShatteredReach::RulesEngine.normalize!(restored)
  end

  def run_solo_opponent!
    allocation = ShatteredReach::BaselinePilot.allocation(state, "player_two")
    self.state = ShatteredReach::RulesEngine.apply(state, player: "player_two", action: "allocate", payload: allocation)
    self.state = ShatteredReach::RulesEngine.apply(state, player: "player_two", action: "lock_allocation", payload: {})
  end

  def run_solo_combat!
    while (decision = ShatteredReach::BaselinePilot.combat_action(state, "player_two"))
      self.state = ShatteredReach::RulesEngine.apply(state, player: "player_two", action: decision.fetch(:action), payload: decision.fetch(:payload))
      break if state["winner"]
    end
  end

  def run_solo_movement!
    while state["activity_step"] == "movement" && state["pending_movement"].any?
      moving_ship = state["ships"].find { |ship| ship["id"] == state["pending_movement"].first }
      break unless moving_ship && moving_ship["player"] == "player_two"

      decision = ShatteredReach::BaselinePilot.movement_action(state, "player_two")
      break unless decision

      self.state = ShatteredReach::RulesEngine.apply(state, player: "player_two", action: decision.fetch(:action), payload: decision.fetch(:payload))
    end
  end

  def run_solo_launch!
    decision = ShatteredReach::BaselinePilot.missile_action(state, "player_two")
    return unless decision

    self.state = ShatteredReach::RulesEngine.apply(state, player: "player_two", action: decision.fetch(:action), payload: decision.fetch(:payload))
  end
end
