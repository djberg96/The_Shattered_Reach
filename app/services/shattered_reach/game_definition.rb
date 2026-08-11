# frozen_string_literal: true

module ShatteredReach
  # Data kept deliberately plain so it can later be exported for a client or API.
  module GameDefinition
    VERSION = "0.1.0"

    def self.ship(name, fleet, size, energy, hull, front, aft, weapons)
      { name: name, fleet: fleet, size: size.to_s, energy: energy, hull: hull, front_shields: front, aft_shields: aft, weapons: weapons }
    end
    private_class_method :ship

    WEAPONS = {
      "beam" => { label: "Lance beam", energy: 2, ranges: [3, 6, 9], to_hit: [2, 3, 4], damage: [3, 2, 1] },
      "driver" => { label: "Mass driver", energy: 1, ranges: [4, 8, 12], to_hit: [3, 4, 5], damage: [2, 2, 2] },
      "missile" => { label: "Seeker missile", energy: 0, ranges: [99], to_hit: [0], damage: [3] }
    }.freeze

    FLEETS = {
      "aurelian" => { name: "Aurelian Compact", color: "#f3bf62", description: "Luminous, disciplined fleet doctrine." },
      "veyr" => { name: "Veyr Dominion", color: "#77a7ff", description: "Angular warships built for decisive volleys." },
      "kestrel" => { name: "Kestrel Freeholds", color: "#e18d5d", description: "Independent industrial fleets with stubborn hulls." }
    }.freeze

    SHIPS = {
      "aurelian_frigate" => ship("Aurelian Frigate", "aurelian", :small, 8, 5, 4, 4, [{ type: "beam", arc: %w[F L R] }, { type: "driver", arc: %w[F] }]),
      "aurelian_cruiser" => ship("Aurelian Cruiser", "aurelian", :medium, 11, 7, 6, 5, [{ type: "beam", arc: %w[F L R] }, { type: "beam", arc: %w[A] }, { type: "driver", arc: %w[F] }]),
      "aurelian_battleship" => ship("Aurelian Battleship", "aurelian", :large, 15, 9, 9, 7, [{ type: "beam", arc: %w[F L R] }, { type: "beam", arc: %w[A] }, { type: "driver", arc: %w[F L R] }]),
      "veyr_frigate" => ship("Veyr Frigate", "veyr", :small, 7, 5, 3, 3, [{ type: "driver", arc: %w[F L R] }, { type: "missile", arc: %w[F L R A], ammo: 3 }]),
      "veyr_cruiser" => ship("Veyr Cruiser", "veyr", :medium, 10, 7, 5, 5, [{ type: "driver", arc: %w[F L R] }, { type: "driver", arc: %w[A] }, { type: "missile", arc: %w[F L R A], ammo: 3 }]),
      "veyr_battleship" => ship("Veyr Battleship", "veyr", :large, 14, 8, 8, 7, [{ type: "driver", arc: %w[F L R] }, { type: "driver", arc: %w[F L R] }, { type: "missile", arc: %w[F L R A], ammo: 4 }]),
      "kestrel_frigate" => ship("Kestrel Frigate", "kestrel", :small, 9, 4, 4, 5, [{ type: "beam", arc: %w[F] }, { type: "missile", arc: %w[F L R A], ammo: 3 }]),
      "kestrel_cruiser" => ship("Kestrel Cruiser", "kestrel", :medium, 12, 6, 6, 6, [{ type: "beam", arc: %w[F L R] }, { type: "driver", arc: %w[F] }, { type: "missile", arc: %w[F L R A], ammo: 3 }]),
      "kestrel_battleship" => ship("Kestrel Battleship", "kestrel", :large, 16, 8, 9, 8, [{ type: "beam", arc: %w[F L R] }, { type: "driver", arc: %w[F L R] }, { type: "driver", arc: %w[A] }, { type: "missile", arc: %w[F L R A], ammo: 4 }])
    }.freeze

    IMPULSE_DECKS = [
      [[1, 3, 5, 7, 9, 11], [2, 4, 6, 8, 10, 12], [1, 4, 6, 8, 10, 12], [2, 3, 5, 7, 9, 11]],
      [[1, 2, 5, 7, 9, 12], [3, 4, 6, 8, 10, 11], [1, 3, 6, 7, 10, 12], [2, 4, 5, 8, 9, 11]],
      [[1, 4, 5, 7, 10, 12], [2, 3, 6, 8, 9, 11], [1, 3, 5, 8, 10, 11], [2, 4, 6, 7, 9, 12]]
    ].freeze

  end
end
