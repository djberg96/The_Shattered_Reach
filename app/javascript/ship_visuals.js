const FLEETS = {
  aurelian: "Aurelian Compact",
  veyr: "Veyr Dominion",
  kestrel: "Kestrel Freeholds"
};

const HULLS = {
  // Aurelian hulls echo the original Mastafarian split-nacelle silhouettes.
  aurelian_frigate: "M0 -35L9 -23L9 -10L18 8L27 -17L35 -8L28 5L34 24L17 23L9 10L6 32L-6 32L-9 10L-17 23L-34 24L-28 5L-35 -8L-27 -17L-18 8L-9 -10L-9 -23Z",
  aurelian_cruiser: "M0 -37L10 -25L10 -11L19 7L29 -20L38 -10L30 6L37 27L18 26L10 12L7 34L-7 34L-10 12L-18 26L-37 27L-30 6L-38 -10L-29 -20L-19 7L-10 -11L-10 -25Z",
  aurelian_battleship: "M0 -38L12 -27L12 -12L21 5L31 -22L40 -12L32 7L39 29L19 29L11 14L8 36L-8 36L-11 14L-19 29L-39 29L-32 7L-40 -12L-31 -22L-21 5L-12 -12L-12 -27Z",

  // Veyr hulls inherit the old Mocha broad, armored wing plan.
  veyr_frigate: "M0 -32L8 -23L14 -10L28 -24L37 -14L31 2L19 9L18 26L9 34L0 27L-9 34L-18 26L-19 9L-31 2L-37 -14L-28 -24L-14 -10L-8 -23Z",
  veyr_cruiser: "M0 -34L9 -25L15 -10L30 -26L40 -15L33 4L20 10L21 29L10 36L0 28L-10 36L-21 29L-20 10L-33 4L-40 -15L-30 -26L-15 -10L-9 -25Z",
  veyr_battleship: "M0 -35L10 -26L17 -10L32 -27L41 -16L35 5L22 11L23 30L11 38L0 29L-11 38L-23 30L-22 11L-35 5L-41 -16L-32 -27L-17 -10L-10 -26Z",

  // Kestrel hulls descend from the original Talapian spear-and-pod family.
  kestrel_frigate: "M0 -38L14 -23L9 -14L9 5L25 14L25 28L11 28L5 16L0 34L-5 16L-11 28L-25 28L-25 14L-9 5L-9 -14L-14 -23Z",
  kestrel_cruiser: "M0 -39L16 -23L10 -13L10 5L29 14L29 30L12 30L5 16L0 36L-5 16L-12 30L-29 30L-29 14L-10 5L-10 -13L-16 -23Z",
  kestrel_battleship: "M0 -40L17 -24L11 -12L11 3L22 10L38 8L41 25L33 33L14 31L6 17L0 38L-6 17L-14 31L-33 33L-41 25L-38 8L-22 10L-11 3L-11 -12L-17 -24Z"
};

const WEAPONS = {
  beam: {
    label: "Lance beam",
    short: "1–3",
    medium: "4–6",
    long: "7–9",
    hit: ["2+", "3+", "4+"],
    damage: [3, 2, 1],
    energy: 2
  },
  driver: {
    label: "Mass driver",
    short: "1–4",
    medium: "5–8",
    long: "9–12",
    hit: ["3+", "4+", "5+"],
    damage: [2, 2, 2],
    energy: 1
  },
  missile: {
    label: "Seeker missile",
    short: "Contact",
    medium: "—",
    long: "—",
    hit: ["Auto", "—", "—"],
    damage: [3, "—", "—"],
    energy: 0
  }
};

export const fleetName = (fleet) => FLEETS[fleet] || fleet;

export function shipHull(ship) {
  const path = HULLS[ship.key] || HULLS[`${ship.fleet}_${ship.size}`] || HULLS.aurelian_cruiser;
  const detail = {
    aurelian: "M0 -27V24M-19 10L-8 4M19 10L8 4M-7 20H7",
    veyr: "M0 -25V25M-27 -11L-13 2M27 -11L13 2M-12 19H12",
    kestrel: "M0 -30V28M-19 13L-8 9M19 13L8 9M-7 -12H7"
  }[ship.fleet];
  return `<path class="hull" d="${path}"/><path class="spine" d="${detail}"/><circle class="engine" cy="28" r="3.5"/>`;
}

export function shipGlyph(ship, className = "") {
  return `<svg class="ship-glyph ${className}" viewBox="-44 -44 88 88" aria-hidden="true"><g class="ship-token fleet-${ship.fleet}">${shipHull(ship)}</g></svg>`;
}

const trackBoxes = (count, active, kind, startAt = 1) => Array.from({ length: count }, (_, index) => {
  const online = index < active;
  return `<span class="track-box ${online ? "online" : "spent"} ${kind}">${index + startAt}</span>`;
}).join("");

const systemTrack = (label, count, active, kind, note = "", alignedColumns = null) => {
  const boxWidth = alignedColumns ? ` style="--shield-box-width:calc(${(100 / alignedColumns).toFixed(4)}% - ${(((alignedColumns - 1) * 3) / alignedColumns).toFixed(2)}px)"` : "";
  return `
  <section class="system-track ${kind}"${boxWidth}>
    <header><h3>${label}</h3><span>${active}/${count}${note ? ` · ${note}` : ""}</span></header>
    <div class="track-boxes">${trackBoxes(count, active, kind)}</div>
  </section>`;
};

const movementTrack = (speed, hidden) => `
  <section class="system-track movement-track">
    <header><h3>Movement order</h3><span>${hidden ? "Allocation concealed" : `Speed ${speed}`}</span></header>
    <div class="track-boxes">${Array.from({ length: 13 }, (_, value) => `<span class="track-box movement ${!hidden && value === speed ? "selected" : ""}">${value}</span>`).join("")}</div>
  </section>`;

const turnModes = (size) => {
  const values = { small: [0, 1, 2], medium: [1, 2, 3], large: [2, 3, 4] }[size];
  return `<section class="turn-mode"><h3>Turn mode</h3><div><span>Speed</span><b>1–4</b><b>5–8</b><b>9–12</b></div><div><span>Hexes</span>${values.map((value) => `<strong>${value}</strong>`).join("")}</div></section>`;
};

const weaponModule = (weapon, ship, hidden) => {
  const profile = WEAPONS[weapon.type];
  const charged = !hidden && (weapon.type === "missile" || ship.allocation.weapons.includes(weapon.id));
  const state = weapon.destroyed ? "destroyed" : weapon.fired ? "fired" : charged ? "charged" : "standby";
  const resource = weapon.type === "missile" ? `${weapon.ammo ?? 0} missiles` : `${profile.energy} energy`;
  return `<article class="weapon-module ${state}">
    <div class="hardpoint"><span>${weapon.type === "beam" ? "LB" : weapon.type === "driver" ? "MD" : "SM"}</span></div>
    <div><h4>${profile.label}</h4><p>Arc ${weapon.arc.join(" · ")} <i>${resource}</i></p></div>
    <strong>${hidden ? "UNREVEALED" : state.toUpperCase()}</strong>
  </article>`;
};

const weaponChart = (type) => {
  const weapon = WEAPONS[type];
  return `<section class="weapon-chart"><h3>${weapon.label}</h3><table>
    <thead><tr><th></th><th>Short</th><th>Medium</th><th>Long</th></tr></thead>
    <tbody><tr><th>Range</th><td>${weapon.short}</td><td>${weapon.medium}</td><td>${weapon.long}</td></tr>
    <tr><th>To hit</th>${weapon.hit.map((value) => `<td>${value}</td>`).join("")}</tr>
    <tr><th>Damage</th>${weapon.damage.map((value) => `<td>${value}</td>`).join("")}</tr></tbody>
  </table></section>`;
};

export function shipSchematic(ship, state, player) {
  const privateAllocation = state.phase === "allocation" && ship.player !== player;
  const availableEnergy = Math.max(ship.energy - ship.damage.engines, 0);
  const maxFrontShields = ship.max_front_shields || ship.shields.front;
  const maxAftShields = ship.max_aft_shields || ship.shields.aft;
  const shieldColumns = Math.max(maxFrontShields, maxAftShields);
  const weaponTypes = [...new Set(ship.weapons.map((weapon) => weapon.type))];
  const owner = ship.player === "player_one" ? "Player One" : "Player Two";
  const maneuver = ship.size === "large" ? "Capital ships have no special maneuver" : ship.special_available ? "Special maneuver ready" : "Special maneuver expended";

  return `<div class="schematic-backdrop" role="presentation">
    <section class="ship-schematic fleet-${ship.fleet}" role="dialog" aria-modal="true" aria-labelledby="schematic-title">
      <header class="schematic-header">
        <div><p class="eyebrow">${fleetName(ship.fleet)} · ${ship.size} hull · ${owner}</p><h2 id="schematic-title">${ship.name}</h2></div>
        <div class="schematic-condition"><span>${ship.destroyed ? "DESTROYED" : "COMBAT READY"}</span><b>${Math.max(ship.hull, 0)} HULL</b></div>
        <button class="schematic-close" aria-label="Close ship schematic">×</button>
      </header>
      <div class="schematic-grid">
        <div class="schematic-systems">
          ${movementTrack(ship.allocation.speed, privateAllocation)}
          ${systemTrack("Reactor / engines", ship.energy, availableEnergy, "energy", `${ship.damage.engines} damaged`)}
          ${systemTrack("Hull integrity", ship.max_hull, Math.max(ship.hull, 0), "hull")}
          ${turnModes(ship.size)}
          <section class="maneuver-status ${ship.special_available ? "ready" : "spent"}"><span></span><div><h3>Special maneuver</h3><p>${maneuver}</p></div></section>
        </div>
        <div class="schematic-vessel">
          ${systemTrack("Forward shield", maxFrontShields, ship.shields.front, "shield", "forward hemisphere", shieldColumns)}
          <div class="schematic-hull"><div class="bearing bearing-front">FORWARD</div>${shipGlyph(ship, "ship-glyph-schematic")}<div class="scan-ring ring-one"></div><div class="scan-ring ring-two"></div></div>
          ${systemTrack("Aft shield", maxAftShields, ship.shields.aft, "shield", "aft hemisphere", shieldColumns)}
          <div class="weapon-rack">${ship.weapons.map((weapon) => weaponModule(weapon, ship, privateAllocation)).join("")}</div>
        </div>
        <div class="schematic-reference">
          <section class="ship-readout"><h3>Live readout</h3><dl><div><dt>Facing</dt><dd>${ship.position[2]}</dd></div><div><dt>Hex</dt><dd>${ship.position[1] + Math.floor(ship.position[0] / 2) + 1}${String(ship.position[0] + 1).padStart(2, "0")}</dd></div><div><dt>Impulse</dt><dd>${state.impulse}</dd></div><div><dt>Energy</dt><dd>${availableEnergy}</dd></div></dl></section>
          ${weaponTypes.map(weaponChart).join("")}
          <section class="arc-legend"><h3>Firing arcs</h3><div><span>F</span>Forward <span>L</span>Port <span>R</span>Starboard <span>A</span>Aft</div></section>
        </div>
      </div>
    </section>
  </div>`;
}
