# frozen_string_literal: true

class MatchesController < ApplicationController
  rescue_from ShatteredReach::RulesEngine::IllegalAction, with: :illegal_action

  def index
    @matches = Match.order(updated_at: :desc)
  end

  def create
    scenario = params[:scenario] == "tutorial" ? :tutorial : :skirmish
    match = Match.create!(title: scenario == :tutorial ? "First Light Tutorial" : "Shattered Reach Skirmish", state: ShatteredReach::RulesEngine.start(scenario: scenario, solo: params[:solo] == "true"))
    redirect_to match
  end

  def show
    @match = Match.find(params[:id])
  end

  def action
    match = Match.find(params[:id])
    match.apply!(player: action_params.fetch(:player, "player_one"), action: action_params.fetch(:action), payload: action_params.fetch(:payload, {}).to_h)
    render json: match.game_state
  end

  private

  def action_params
    params.permit(:player, :action, payload: {})
  end

  def illegal_action(error)
    render json: { error: error.message }, status: :unprocessable_entity
  end
end
