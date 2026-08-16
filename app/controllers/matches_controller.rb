# frozen_string_literal: true

require "securerandom"

class MatchesController < ApplicationController
  rescue_from ShatteredReach::RulesEngine::IllegalAction, with: :illegal_action

  def index
    @matches = Match.order(updated_at: :desc)
  end

  def create
    mode = params[:mode].presence
    scenario = mode == "tutorial" || params[:scenario] == "tutorial" ? :tutorial : :skirmish
    solo = mode == "solo" || params[:solo] == "true"
    state = ShatteredReach::RulesEngine.start(
      scenario: scenario,
      solo: solo,
      board_size: params[:board_size],
      player_one_ships: params[:player_one_ships],
      player_two_ships: params[:player_two_ships],
      ai_match: params[:ai_match],
      seed: new_match_seed
    )
    match = Match.create!(title: scenario == :tutorial ? "First Light Tutorial" : "Shattered Reach Skirmish", state: state)
    redirect_to match
  rescue ShatteredReach::RulesEngine::IllegalAction => error
    redirect_to matches_path, alert: error.message
  end

  def show
    @match = Match.find(params[:id])
  end

  def download
    match = Match.find(params[:id])
    filename = "shattered-reach-turn-#{match.game_state["turn"]}.json"
    send_data ShatteredReach::SaveGame.dump(match), filename: filename, type: "application/json", disposition: "attachment"
  end

  def reset
    match = Match.find(params[:id])
    match.update!(state: ShatteredReach::RulesEngine.restart(match.game_state, seed: new_match_seed))
    respond_to do |format|
      format.html { redirect_to match, notice: "Battle reset." }
      format.json { render json: match.game_state }
    end
  end

  def import
    upload = params[:save_file]
    raise ShatteredReach::SaveGame::InvalidSave, "Choose a save file to load" unless upload.respond_to?(:read)

    loaded = ShatteredReach::SaveGame.load(upload.read(ShatteredReach::SaveGame::MAX_BYTES + 1))
    match = Match.create!(title: loaded.fetch(:title), state: loaded.fetch(:state))
    redirect_to match, notice: "Game loaded."
  rescue ShatteredReach::SaveGame::InvalidSave => error
    redirect_to matches_path, alert: error.message
  end

  def action
    match = Match.find(params[:id])
    player = match.game_state["solo"] ? "player_one" : action_params.fetch(:player, "player_one")
    match.apply!(player: player, action: action_params.fetch(:command), payload: action_params.fetch(:payload, {}).to_h)
    render json: match.game_state
  end

  private

  def new_match_seed = SecureRandom.random_number(1...2**32)

  def action_params
    params.slice(:player, :command, :payload).permit(:player, :command, payload: {})
  end

  def illegal_action(error)
    render json: { error: error.message }, status: :unprocessable_entity
  end
end
