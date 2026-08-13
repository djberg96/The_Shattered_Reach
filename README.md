# The Shattered Reach

A private Ruby on Rails prototype for tactical, turn-based space combat. It is a faithful digital refresh of the original tabletop design: players secretly allocate energy, resolve twelve semi-random movement impulses, and fight over a hex map with shields, firing arcs, weapons, missiles, and subsystem damage.

This was a prototype I created in 2014 or so that I decided to dust off. It is loosely based on games like Star Fleet Battles and Galactic Civilizations. It was originally called "Micro Space Empire Battles" as a nod to Robert Bartelli's game "Micro Space Empire", with the idea that it would be based in his universe, though nothing ever came of it.

These days I would probably just play Starmada or SFB if you're in the mood for something deeper, but this can be fun if you're looking for something quick and light.

## Installation
You will need to install the Ruby programming language and the Rails web framework.

## Run it

Requires your rbenv-managed Ruby and Bundler.

```sh
bundle install
bin/rails db:prepare
bin/rails server
```

Open `http://localhost:3000`. Start a hot-seat skirmish, a solo match against the baseline command AI, or the guided tutorial.

## Verification

```sh
bin/rails test
make -C docs/rulebook
```

The latter command generates `docs/rulebook/build/the-shattered-reach-rulebook.pdf` from the canonical XeLaTeX source.

## Structure

- `app/services/shattered_reach/` contains the versioned game definition, deterministic rules engine, and baseline AI.
- `app/javascript/` renders the SVG tactical board and command controls.
- `docs/rulebook/main.tex` is the authoritative printable rulebook source.
- `app/assets/images/shattered_reach/` contains cinematic fleet and key-art illustrations.

The prototype deliberately excludes accounts, remote multiplayer, payments, and mobile layouts.

## Author
Daniel J. Berger

## Copyright
Copright 2026, All Rights Reserved

## License
MIT
