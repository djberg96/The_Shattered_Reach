# frozen_string_literal: true

require_relative "../../app/services/shattered_reach/game_definition"

module ShipCards
  HARDPOINTS = {
    "aurelian_frigate" => [[-20, 5], [-20, 14], [20, 5], [20, 14], [0, -22]],
    "aurelian_cruiser" => [[-26, 5], [-26, 14], [26, 5], [26, 14], [0, -22], [0, 7]],
    "aurelian_battleship" => [[-28, 2], [-28, 12], [28, 2], [28, 12], [-8.5, 22], [-8.5, 31], [8.5, 22], [8.5, 31], [0, -22], [0, 7]],
    "veyr_frigate" => [[0, 10], [0, 19], [22, -9], [-23, -10]],
    "veyr_cruiser" => [[-12, 10], [-12, 19], [12, 10], [12, 19], [24, -10], [-24, -10]],
    "veyr_battleship" => [[-18, -21], [18, -21], [0, 10]],
    "kestrel_frigate" => [[0, -22], [0, -13], [-17, 18], [17, 18]],
    "kestrel_cruiser" => [[0, -24], [0, -15], [-18, 20], [0, 7], [18, 20]],
    "kestrel_battleship" => [[0, -25], [0, -16], [-14, 12], [-15, 21], [14, 12], [15, 21], [-31, 20], [0, 1], [31, 20]]
  }.freeze

  TURN_MODES = {
    "small" => [0, 1, 2],
    "medium" => [1, 2, 3],
    "large" => [2, 3, 4]
  }.freeze

  FLEET_COLORS = {
    "aurelian" => "aurelian",
    "veyr" => "veyr",
    "kestrel" => "kestrel"
  }.freeze

  WEAPON_LABELS = {
    "beam" => "LANCE",
    "driver" => "DRIVER",
    "missile" => "SEEKER"
  }.freeze

  module_function

  def tex(value)
    value.to_s.gsub(/([%&_#{}])/, '\\\\1')
  end

  def arc_label(arcs)
    arcs.length == 4 ? '360\\textdegree' : arcs.join('/')
  end

  def grouped_weapons(ship)
    ship[:weapons].group_by { |weapon| [weapon[:type], weapon[:mount], weapon[:arc], weapon[:ammo]] }
  end

  def hardpoint_commands(key, ship)
    HARDPOINTS.fetch(key).zip(ship[:weapons]).map do |(x, y), weapon|
      label = tex(weapon[:mount])
      px = 1.10 + (x * 1.72 / 88.0)
      py = 3.38 - (y * 1.72 / 88.0)
      "\\Hardpoint{#{format('%.3f', px)}}{#{format('%.3f', py)}}{#{label}}"
    end.join("\n")
  end

  def weapon_commands(ship)
    grouped = grouped_weapons(ship).to_a
    cursor = 2.24
    grouped.map do |((type, mount, arcs, ammo), weapons)|
      y = cursor
      resource = if type == 'missile'
                   "#{ammo} EA"
                 else
                   "#{ShatteredReach::GameDefinition::WEAPONS.fetch(type)[:energy]}E"
                 end
      commands = ["\\WeaponRow{#{format('%.3f', y)}}{#{tex(mount)}}{#{WEAPON_LABELS.fetch(type)}}{#{arc_label(arcs)}}{#{resource}}{#{weapons.length}}"]
      cursor -= 0.245
      if type == 'missile'
        commands << "\\AmmoRow{#{format('%.3f', y - 0.145)}}{#{weapons.length}}{#{ammo}}"
        cursor -= 0.155
      end
      commands.join("\n")
    end.join("\n")
  end

  def ship_card(key, ship)
    fleet = ShatteredReach::GameDefinition::FLEETS.fetch(ship[:fleet])
    turns = TURN_MODES.fetch(ship[:size])
    <<~TEX
      \\begin{shipcard}
      \\CardFrame{#{FLEET_COLORS.fetch(ship[:fleet])}}
      \\CardHeader{#{tex(fleet[:name])}}{#{tex(ship[:name])}}{#{ship[:size].upcase}}{#{ship[:energy]}}
      \\CardArt{#{key}.png}
      #{hardpoint_commands(key, ship)}
      \\DamageTrack{4.050}{HULL}{#{ship[:hull]}}{hulltrack}
      \\DamageTrack{3.710}{FORWARD SHIELD}{#{ship[:front_shields]}}{shieldtrack}
      \\DamageTrack{3.370}{AFT SHIELD}{#{ship[:aft_shields]}}{shieldtrack}
      \\ReactorTrack{#{ship[:energy]}}
      \\WeaponHeader
      #{weapon_commands(ship)}
      \\ShipBlurb{#{tex(ship[:blurb])}}
      \\TurnStrip{#{turns[0]}}{#{turns[1]}}{#{turns[2]}}{#{ship[:size] == 'large' ? 'CAPITAL HULL' : 'SPECIAL MANEUVER $\\square$'}}
      \\end{shipcard}
    TEX
  end

  cards = ShatteredReach::GameDefinition::SHIPS.map { |key, ship| ship_card(key, ship) }
  cards.concat(['\\WeaponReferenceCard', '\\MovementReferenceCard', '\\DamageReferenceCard'])

  cards.each_slice(4).with_index do |page_cards, page|
    puts page_cards[0]
    puts '\\hfill'
    puts page_cards[1]
    puts '\\par\\vspace{0.22in}\\noindent'
    puts page_cards[2]
    puts '\\hfill'
    puts page_cards[3]
    puts '\\newpage' unless page == 2
  end
end
