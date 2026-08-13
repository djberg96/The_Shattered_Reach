# frozen_string_literal: true

require "json"

module ShatteredReach
  class SaveGame
    FORMAT = "the-shattered-reach-save"
    FORMAT_VERSION = 1
    MAX_BYTES = 2.megabytes

    class InvalidSave < StandardError; end

    def self.dump(match)
      JSON.pretty_generate(
        "format" => FORMAT,
        "format_version" => FORMAT_VERSION,
        "saved_at" => Time.current.iso8601,
        "title" => match.title,
        "game_definition_version" => GameDefinition::VERSION,
        "state" => match.game_state
      )
    end

    def self.load(contents)
      raise InvalidSave, "Save file is too large" if contents.bytesize > MAX_BYTES

      document = JSON.parse(contents)
      raise InvalidSave, "This is not a Shattered Reach save file" unless document.is_a?(Hash) && document["format"] == FORMAT
      raise InvalidSave, "Unsupported save-file version" unless document["format_version"] == FORMAT_VERSION

      state = document["state"]
      validate_state!(state)
      state = RulesEngine.normalize!(state.deep_dup)
      canonicalize!(state)

      {
        title: sanitized_title(document["title"]),
        state: state
      }
    rescue JSON::ParserError
      raise InvalidSave, "Save file is not valid JSON"
    rescue KeyError, NoMethodError, TypeError, ArgumentError
      raise InvalidSave, "Save file contains invalid game data"
    end

    def self.validate_state!(state)
      raise InvalidSave, "Save file has no game state" unless state.is_a?(Hash)
      raise InvalidSave, "Save file has an invalid battlefield size" unless RulesEngine::BOARD_SIZES.include?(state["board_size"].to_i)
      raise InvalidSave, "Save file has an invalid scenario" unless %w[skirmish tutorial].include?(state["scenario"])
      raise InvalidSave, "Save file has invalid ships" unless state["ships"].is_a?(Array) && state["ships"].length.between?(1, 20)

      ids = state["ships"].map do |ship|
        raise InvalidSave, "Save file contains an unknown ship" unless ship.is_a?(Hash) && GameDefinition::SHIPS.key?(ship["key"])
        raise InvalidSave, "Save file contains an invalid commander" unless %w[player_one player_two].include?(ship["player"])
        raise InvalidSave, "Save file contains an invalid ship identifier" unless ship["id"].to_s.match?(/\A[a-z0-9_-]{1,80}\z/)
        raise InvalidSave, "Save file contains an invalid ship position" unless valid_position?(ship["position"])
        raise InvalidSave, "Save file contains an invalid allocation" unless ship["allocation"].is_a?(Hash)

        ship["id"]
      end
      raise InvalidSave, "Save file contains duplicate ships" unless ids.uniq.length == ids.length
    end
    private_class_method :validate_state!

    def self.canonicalize!(state)
      state["version"] = GameDefinition::VERSION
      state["solo"] = state["solo"] == true
      state["turn"] = state["turn"].to_i.clamp(1, 100_000)
      state["impulse"] = state["impulse"].to_i.clamp(0, 12)
      state["phase"] = %w[allocation impulse].include?(state["phase"]) ? state["phase"] : "allocation"
      allowed_steps = state["phase"] == "allocation" ? %w[allocation] : %w[draw movement launch fire]
      state["activity_step"] = allowed_steps.include?(state["activity_step"]) ? state["activity_step"] : allowed_steps.first
      state["initiative"] = nil unless %w[player_one player_two].include?(state["initiative"])
      state["winner"] = nil unless %w[player_one player_two].include?(state["winner"])
      state["seed"] = state["seed"].to_i
      state["impulse_card"] = valid_impulse_card?(state["impulse_card"]) ? state["impulse_card"] : nil
      state["impulse_phase"] = state["impulse_phase"].to_i.clamp(1, 3) if state["impulse_phase"].present?
      state["impulse_card_number"] = state["impulse_card_number"].to_i.clamp(1, 12) if state["impulse_card_number"].present?
      state["tutorial_step"] = state["tutorial_step"].to_i.clamp(0, 3) if state["scenario"] == "tutorial"
      state["impulse_order"] = valid_impulse_order?(state["impulse_order"]) ? state["impulse_order"] : Array.new(3) { [0, 1, 2, 3] }
      state.delete("movement_undo")
      state["combat_events"] = []
      state["next_combat_event_id"] = 1
      state["log"] = Array(state["log"]).last(500).map { |entry| ActionView::Base.full_sanitizer.sanitize(entry.to_s).first(500) }

      state["ships"].each do |ship|
        spec = GameDefinition::SHIPS.fetch(ship["key"])
        ship["name"] = spec[:name]
        ship["fleet"] = spec[:fleet]
        ship["size"] = spec[:size]
        ship["energy"] = spec[:energy]
        ship["max_hull"] = spec[:hull]
        ship["max_front_shields"] = spec[:front_shields]
        ship["max_aft_shields"] = spec[:aft_shields]
        ship["position"][2] %= 6
        ship["hull"] = ship["hull"].to_i.clamp(0, spec[:hull])
        ship["shields"] = {
          "front" => ship.dig("shields", "front").to_i.clamp(0, spec[:front_shields]),
          "aft" => ship.dig("shields", "aft").to_i.clamp(0, spec[:aft_shields])
        }
        allocation = ship["allocation"]
        shield_cap = { "small" => 1, "medium" => 2, "large" => 3 }.fetch(spec[:size])
        allocation["speed"] = allocation["speed"].to_i.clamp(0, 12)
        allocation["shields"] = {
          "front" => allocation.dig("shields", "front").to_i.clamp(0, shield_cap),
          "aft" => allocation.dig("shields", "aft").to_i.clamp(0, shield_cap)
        }
        repair = allocation["shield_repair"]
        allocation["shield_repair"] = if %w[front aft].include?(repair) && ship.dig("shields", repair) < spec.fetch("#{repair}_shields".to_sym)
                                          repair
                                        end
        ship["damage"] = {
          "engines" => ship.dig("damage", "engines").to_i.clamp(0, spec[:energy]),
          "weapons" => ship.dig("damage", "weapons").to_i.clamp(0, spec[:weapons].length)
        }
        ship["locked"] = ship["locked"] == true
        ship["destroyed"] = ship["destroyed"] == true || ship["hull"].zero?
        ship["special_available"] = ship["special_available"] == true && spec[:size] != "large"
        ship["movement"] = {
          "hexes_since_turn" => ship.dig("movement", "hexes_since_turn").to_i.clamp(0, 12),
          "last_action" => %w[forward sideslip turn].include?(ship.dig("movement", "last_action")) ? ship.dig("movement", "last_action") : nil
        }
        path = Array(ship["movement_path"]).select { |position| valid_coordinate?(position) }.first(13).map(&:dup)
        ship["movement_path"] = path.presence || [ship["position"].first(2)]
        canonicalize_weapons!(ship, spec)
      end

      canonicalize_missiles!(state)
      ship_ids = state["ships"].map { |ship| ship["id"] }
      state["pending_movement"] = Array(state["pending_movement"]).select { |id| ship_ids.include?(id) }.uniq
      state["movement_options"] = Array(state["movement_options"]) & %w[forward sideslip_left sideslip_right turn_left turn_right lose_movement]
      state
    end
    private_class_method :canonicalize!

    def self.canonicalize_weapons!(ship, spec)
      saved_weapons = Array(ship["weapons"])
      ship["weapons"] = spec[:weapons].map.with_index do |definition, index|
        saved = saved_weapons.find { |weapon| weapon.is_a?(Hash) && weapon["id"] == "w#{index}" } || {}
        weapon = definition.stringify_keys.merge(
          "id" => "w#{index}",
          "destroyed" => saved["destroyed"] == true,
          "fired" => saved["fired"] == true
        )
        weapon["ammo"] = saved.fetch("ammo", definition[:ammo]).to_i.clamp(0, definition[:ammo]) if definition.key?(:ammo)
        weapon
      end
      valid_weapon_ids = ship["weapons"].reject { |weapon| weapon["destroyed"] }.map { |weapon| weapon["id"] }
      allocation = ship["allocation"]
      allocation["weapons"] = Array(allocation["weapons"]).select { |id| valid_weapon_ids.include?(id) }.uniq
    end
    private_class_method :canonicalize_weapons!

    def self.canonicalize_missiles!(state)
      ships_by_id = state["ships"].index_by { |ship| ship["id"] }
      state["missiles"] = Array(state["missiles"]).filter_map do |missile|
        next unless missile.is_a?(Hash) && missile["id"].to_s.match?(/\Amissile-\d+\z/) && valid_position?(missile["position"])

        launcher = ships_by_id[missile["launcher_ship_id"]]
        target = ships_by_id[missile["target_id"]]
        next unless launcher && target && launcher["player"] != target["player"]

        missile.slice("id", "launcher_ship_id", "target_id", "position", "launched_turn", "launched_impulse").merge(
          "owner" => launcher["player"],
          "fleet" => launcher["fleet"]
        )
      end
    end
    private_class_method :canonicalize_missiles!

    def self.valid_position?(position)
      position.is_a?(Array) && position.length == 3 && position.all? { |value| value.is_a?(Integer) } && position.first(2).all? { |value| value.abs <= 1_000 }
    end
    private_class_method :valid_position?

    def self.valid_coordinate?(position)
      position.is_a?(Array) && position.length == 2 && position.all? { |value| value.is_a?(Integer) } && position.all? { |value| value.abs <= 1_000 }
    end
    private_class_method :valid_coordinate?

    def self.valid_impulse_card?(card)
      card.nil? || (card.is_a?(Array) && card.length.between?(1, 12) && card.uniq.length == card.length && card.all? { |speed| speed.is_a?(Integer) && speed.between?(1, 12) })
    end
    private_class_method :valid_impulse_card?

    def self.valid_impulse_order?(order)
      order.is_a?(Array) && order.length == 3 && order.all? { |phase| phase.is_a?(Array) && phase.sort == [0, 1, 2, 3] }
    end
    private_class_method :valid_impulse_order?

    def self.sanitized_title(title)
      clean = ActionView::Base.full_sanitizer.sanitize(title.to_s).squish.first(100)
      clean.presence || "Loaded Shattered Reach Battle"
    end
    private_class_method :sanitized_title
  end
end
