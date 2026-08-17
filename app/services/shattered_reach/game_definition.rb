# frozen_string_literal: true

module ShatteredReach
  # Data kept deliberately plain so it can later be exported for a client or API.
  module GameDefinition
    VERSION = "0.2.0"

    def self.ship(name, fleet, size, energy, hull, front, aft, weapons, blurb)
      { name: name, fleet: fleet, size: size.to_s, energy: energy, hull: hull, front_shields: front, aft_shields: aft, weapons: weapons, blurb: blurb }
    end
    private_class_method :ship

    SETTING = {
      kicker: "Eighty-seven years after the Shattering",
      title: "The lanes are opening again.",
      paragraphs: [
        "For two centuries, the Meridian Gates bound the Reach into a single civilization. Then every gate fired at once. Worlds vanished behind walls of distorted space, fleets were cut in half, and the star maps became lies. The survivors remember that night simply as the Shattering.",
        "Now the dead lanes flicker back to life, opening brief corridors to abandoned arsenals, isolated colonies, and systems unseen for generations. Whoever holds the anchor stations can decide which worlds reconnect—and on whose terms.",
        "The Aurelian Compact claims a duty to restore the old union. The Veyr Dominion means to replace it with an order strong enough to survive the next collapse. The Kestrel Freeholds fight to keep the frontier unowned. Their wars are small by necessity: a handful of ships, minutes before a corridor closes, and entire systems in the balance."
      ]
    }.freeze

    WEAPONS = {
      "beam" => { label: "Lance beam", energy: 2, ranges: [3, 6, 9], to_hit: [2, 3, 4], damage: [3, 2, 1] },
      "driver" => { label: "Mass driver", energy: 1, ranges: [4, 8, 12], to_hit: [3, 4, 5], damage: [2, 2, 2] },
      "missile" => { label: "Seeker missile", energy: 0, ranges: [99], to_hit: [0], damage: [3] }
    }.freeze

    FLEETS = {
      "aurelian" => { name: "Aurelian Compact", color: "#f3bf62", description: "Heirs to the old gate authority, offering reunification at lance-point." },
      "veyr" => { name: "Veyr Dominion", color: "#77a7ff", description: "A fortress-state forged by isolation, trusting command and decisive force." },
      "kestrel" => { name: "Kestrel Freeholds", color: "#e18d5d", description: "Station clans and convoy captains fighting to keep the reopened frontier unowned." }
    }.freeze

    SHIPS = {
      # Each entry corresponds to one damage box on the legacy ship sheet.
      "aurelian_frigate" => ship("Aurelian Frigate", "aurelian", :small, 8, 5, 4, 4, [
        { type: "beam", mount: "B1", arc: %w[L] }, { type: "beam", mount: "B1", arc: %w[L] },
        { type: "beam", mount: "B2", arc: %w[R] }, { type: "beam", mount: "B2", arc: %w[R] },
        { type: "driver", mount: "MD", arc: %w[F] }
      ], "Swift Compact escorts race for the lane mouth, then rake intruders with disciplined crossing fire."),
      "aurelian_cruiser" => ship("Aurelian Cruiser", "aurelian", :medium, 11, 7, 6, 5, [
        { type: "beam", mount: "B1", arc: %w[L] }, { type: "beam", mount: "B1", arc: %w[L] },
        { type: "beam", mount: "B2", arc: %w[R] }, { type: "beam", mount: "B2", arc: %w[R] },
        { type: "driver", mount: "MD", arc: %w[F] }, { type: "driver", mount: "MD", arc: %w[F R A L] }
      ], "Compact cruisers broadcast terms of reunification while paired beam batteries make refusal expensive."),
      "aurelian_battleship" => ship("Aurelian Battleship", "aurelian", :large, 15, 9, 9, 7, [
        { type: "beam", mount: "B1", arc: %w[L] }, { type: "beam", mount: "B1", arc: %w[L] },
        { type: "beam", mount: "B1", arc: %w[R] }, { type: "beam", mount: "B1", arc: %w[R] },
        { type: "beam", mount: "B2", arc: %w[L A] }, { type: "beam", mount: "B2", arc: %w[L A] },
        { type: "beam", mount: "B2", arc: %w[R A] }, { type: "beam", mount: "B2", arc: %w[R A] },
        { type: "driver", mount: "MD", arc: %w[F] }, { type: "driver", mount: "MD", arc: %w[F R A L] }
      ], "A mobile fragment of the lost capital, built to make distant worlds remember Aurelian authority."),
      "veyr_frigate" => ship("Veyr Frigate", "veyr", :small, 7, 5, 3, 3, [
        { type: "beam", mount: "B1", arc: %w[L R A] }, { type: "beam", mount: "B1", arc: %w[L R A] },
        { type: "driver", mount: "MD", arc: %w[F] }, { type: "missile", mount: "M", arc: %w[F R A L], ammo: 3 }
      ], "A patient hunter that marks targets for the Dominion and closes only when escape is impossible."),
      "veyr_cruiser" => ship("Veyr Cruiser", "veyr", :medium, 10, 7, 5, 5, [
        { type: "beam", mount: "B1", arc: %w[L A] }, { type: "beam", mount: "B1", arc: %w[L A] },
        { type: "beam", mount: "B2", arc: %w[R A] }, { type: "beam", mount: "B2", arc: %w[R A] },
        { type: "driver", mount: "MD", arc: %w[F] }, { type: "missile", mount: "M", arc: %w[F R A L], ammo: 3 }
      ], "The workhorse of Veyr blockade lines, equally prepared to hold a corridor or break one open."),
      "veyr_battleship" => ship("Veyr Battleship", "veyr", :large, 14, 8, 8, 7, [
        { type: "driver", mount: "MD1", arc: %w[F L R] }, { type: "driver", mount: "MD2", arc: %w[F L R] },
        { type: "missile", mount: "M", arc: %w[F R A L], ammo: 4 }
      ], "The Dominion's answer to uncertainty: armored command, long-range fire, and no avenue of retreat."),
      "kestrel_frigate" => ship("Kestrel Frigate", "kestrel", :small, 9, 4, 4, 5, [
        { type: "beam", mount: "B1", arc: %w[F] }, { type: "beam", mount: "B2", arc: %w[F] },
        { type: "missile", mount: "M", arc: %w[F R A L], ammo: 3 }, { type: "missile", mount: "M", arc: %w[F R A L], ammo: 3 }
      ], "Courier frames turned raiders, fast enough to strike a claim beacon and vanish into the fracture lanes."),
      "kestrel_cruiser" => ship("Kestrel Cruiser", "kestrel", :medium, 12, 6, 6, 6, [
        { type: "beam", mount: "B1", arc: %w[F] }, { type: "beam", mount: "B1", arc: %w[F] },
        { type: "missile", mount: "M", arc: %w[F R A L], ammo: 3 }, { type: "missile", mount: "M", arc: %w[F R A L], ammo: 3 },
        { type: "missile", mount: "M", arc: %w[F R A L], ammo: 3 }
      ], "Freehold yards wrap stubborn shields around missile magazines built to outlast wealthier enemies."),
      "kestrel_battleship" => ship("Kestrel Battleship", "kestrel", :large, 16, 8, 9, 8, [
        { type: "beam", mount: "B1", arc: %w[F] }, { type: "beam", mount: "B1", arc: %w[F] },
        { type: "beam", mount: "B2", arc: %w[L A] }, { type: "beam", mount: "B2", arc: %w[L A] },
        { type: "beam", mount: "B3", arc: %w[R A] }, { type: "beam", mount: "B3", arc: %w[R A] },
        { type: "missile", mount: "M", arc: %w[F R A L], ammo: 3 }, { type: "missile", mount: "M", arc: %w[F R A L], ammo: 3 },
        { type: "missile", mount: "M", arc: %w[F R A L], ammo: 3 }
      ], "No two are identical; each is a shipyard covenant made armor, carrying a whole Freehold to war.")
    }.freeze

    IMPULSE_DECKS = [
      [[5, 7, 9, 10, 11, 12], [2, 6, 8, 10, 12], [4, 6, 8, 9, 11, 12], [3, 7, 9, 10, 11, 12]],
      [[3, 5, 7, 9, 10, 11, 12], [4, 6, 8, 9, 10, 11, 12], [4, 6, 7, 8, 9, 10, 11, 12], [1, 5, 7, 8, 10, 11, 12]],
      [[4, 6, 8, 10, 11, 12], [3, 6, 8, 9, 10, 11, 12], [2, 5, 7, 9, 11, 12], [5, 7, 8, 9, 10, 11, 12]]
    ].freeze
  end
end
