# frozen_string_literal: true

class MatchesController < ApplicationController
  rescue_from ShatteredReach::RulesEngine::IllegalAction, with: :illegal_action

  def index
    @matches = Match.order(updated_at: :desc)
  end

  def create
    mode = params[:mode].presence
    scenario = mode == "tutorial" || params[:scenario] == "tutorial" ? :tutorial : :skirmish
    solo = mode == "solo" || params[:solo] == "true"
    match = Match.create!(title: scenario == :tutorial ? "First Light Tutorial" : "Shattered Reach Skirmish", state: ShatteredReach::RulesEngine.start(scenario: scenario, solo: solo, board_size: params[:board_size]))
    redirect_to match
  end

  def show
    @match = Match.find(params[:id])
  end

  def action
    match = Match.find(params[:id])
    player = match.game_state["solo"] ? "player_one" : action_params.fetch(:player, "player_one")
    match.apply!(player: player, action: action_params.fetch(:command), payload: action_params.fetch(:payload, {}).to_h)
    render json: match.game_state
  end

  private

  def action_params
    params.slice(:player, :command, :payload).permit(:player, :command, payload: {})
  end

  def illegal_action(error)
    render json: { error: error.message }, status: :unprocessable_entity
  end
end
