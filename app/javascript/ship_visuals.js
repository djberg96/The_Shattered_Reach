const FLEETS = {
  aurelian: "Aurelian Compact",
  veyr: "Veyr Dominion",
  kestrel: "Kestrel Freeholds"
};

const HULLS = {
  // Aurelian hulls echo the original Mastafarian split-nacelle silhouettes.
  aurelian_frigate: {
    path: "M0 -37L8 -26L8 -13L15 2L24 -18L33 -9L26 6L31 23L16 22L9 11L5 32L-5 32L-9 11L-16 22L-31 23L-26 6L-33 -9L-24 -18L-15 2L-8 -13L-8 -26Z",
    detail: "M0 -29V24M-21 9L-10 4M21 9L10 4M-6 21H6",
    engines: [[0, 28, 3.2]]
  },
  aurelian_cruiser: {
    path: "M0 -40L12 -28L12 -13L20 3L30 -23L40 -12L32 6L38 28L21 29L13 18L11 38L3 38L3 22L-3 22L-3 38L-11 38L-13 18L-21 29L-38 28L-32 6L-40 -12L-30 -23L-20 3L-12 -13L-12 -28Z",
    detail: "M0 -32V25M-27 8L-13 2M27 8L13 2M-9 19H9M-8 29V35M8 29V35",
    engines: [[-7, 34, 2.8], [7, 34, 2.8]]
  },
  aurelian_battleship: {
    path: "M0 -43L15 -31L16 -15L23 0L34 -27L44 -15L37 7L43 31L28 35L19 26L18 41L7 41L7 23L3 18L-3 18L-7 23L-7 41L-18 41L-19 26L-28 35L-43 31L-37 7L-44 -15L-34 -27L-23 0L-16 -15L-16 -31Z",
    detail: "M0 -35V14M-31 7L-18 1M31 7L18 1M-31 26L-21 22M31 26L21 22M-13 20V36M13 20V36M-7 13H7",
    engines: [[-12, 37, 2.8], [0, 34, 3.6], [12, 37, 2.8]]
  },

  // Veyr hulls inherit the old Mocha broad, armored wing plan.
  veyr_frigate: {
    path: "M0 -36L7 -27L11 -15L23 -24L33 -15L28 -3L18 3L22 17L13 30L4 23L0 34L-4 23L-13 30L-22 17L-18 3L-28 -3L-33 -15L-23 -24L-11 -15L-7 -27Z",
    detail: "M0 -29V25M-25 -11L-12 1M25 -11L12 1M-10 18H10",
    engines: [[0, 29, 3.2]]
  },
  veyr_cruiser: {
    path: "M0 -39L10 -30L16 -13L31 -27L41 -16L35 4L23 11L29 28L15 38L0 29L-15 38L-29 28L-23 11L-35 4L-41 -16L-31 -27L-16 -13L-10 -30Z",
    detail: "M0 -32V27M-32 -13L-16 2M32 -13L16 2M-19 22L-8 17M19 22L8 17M-10 29H10",
    engines: [[-8, 32, 2.7], [8, 32, 2.7]]
  },
  veyr_battleship: {
    path: "M-16 -40H16L23 -31L38 -27L44 -13L37 2L29 8L39 25L28 38L13 31L0 42L-13 31L-28 38L-39 25L-29 8L-37 2L-44 -13L-38 -27L-23 -31Z",
    detail: "M0 -35V32M-33 -20L-18 -9M33 -20L18 -9M-29 21L-13 14M29 21L13 14M-13 29H13M-10 -29H10",
    engines: [[-10, 35, 3], [10, 35, 3]]
  },

  // Kestrel hulls descend from the original Talapian spear-and-pod family.
  kestrel_frigate: {
    path: "M0 -39L10 -28L13 -15L9 -7L10 5L24 13L28 26L18 31L8 26L4 17L0 35L-4 17L-8 26L-18 31L-28 26L-24 13L-10 5L-9 -7L-13 -15L-10 -28Z",
    detail: "M0 -32V28M-17 17L-7 10M17 17L7 10M-7 -11H7",
    engines: [[0, 30, 3.2]]
  },
  kestrel_cruiser: {
    path: "M0 -42L13 -30L16 -15L11 -5L12 7L27 12L34 24L28 34L14 33L6 20L0 39L-6 20L-14 33L-28 34L-34 24L-27 12L-12 7L-11 -5L-16 -15L-13 -30Z",
    detail: "M0 -35V31M-23 20L-9 12M23 20L9 12M-9 -12H9M-10 28L-5 32M10 28L5 32",
    engines: [[-7, 32, 2.7], [7, 32, 2.7]]
  },
  kestrel_battleship: {
    path: "M0 -44L16 -32L18 -17L13 -6L20 5L37 2L44 15L41 30L29 38L14 34L6 20L0 42L-6 20L-14 34L-29 38L-41 30L-44 15L-37 2L-20 5L-13 -6L-18 -17L-16 -32Z",
    detail: "M0 -37V34M-34 12L-17 9M34 12L17 9M-31 27L-15 21M31 27L15 21M-11 -13H11M-13 31L-7 35M13 31L7 35",
    engines: [[-11, 35, 2.8], [0, 38, 3.5], [11, 35, 2.8]]
  }
};

// Coordinates deliberately place each weapon on a visible part of its hull.
// Array order matches the weapon order in GameDefinition.
const HARDPOINTS = {
  aurelian_frigate: [[-20, 5], [-20, 14], [20, 5], [20, 14], [0, -22]],
  aurelian_cruiser: [[-26, 5], [-26, 14], [26, 5], [26, 14], [0, -22], [0, 7]],
  aurelian_battleship: [[-28, 2], [-28, 12], [28, 2], [28, 12], [-8.5, 22], [-8.5, 31], [8.5, 22], [8.5, 31], [0, -22], [0, 7]],
  veyr_frigate: [[0, 10], [0, 19], [22, -9], [-23, -10]],
  veyr_cruiser: [[-12, 10], [-12, 19], [12, 10], [12, 19], [24, -10], [-24, -10]],
  veyr_battleship: [[-18, -21], [18, -21], [0, 10]],
  kestrel_frigate: [[0, -22], [0, -13], [-17, 18], [17, 18]],
  kestrel_cruiser: [[0, -24], [0, -15], [-18, 20], [0, 7], [18, 20]],
  kestrel_battleship: [[0, -25], [0, -16], [-14, 12], [-15, 21], [14, 12], [15, 21], [-31, 20], [0, 1], [31, 20]]
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
  const hull = HULLS[ship.key] || HULLS[`${ship.fleet}_${ship.size}`] || HULLS.aurelian_cruiser;
  const engines = hull.engines.map(([cx, cy, radius]) => `<circle class="engine" cx="${cx}" cy="${cy}" r="${radius}"/>`).join("");
  return `<path class="hull" d="${hull.path}"/><path class="spine" d="${hull.detail}"/>${engines}`;
}

const weaponState = (weapon, ship, hidden) => {
  if (weapon.destroyed) return "destroyed";
  if (weapon.repaired_this_turn) return "repairing";
  if (weapon.fired) return "fired";
  if (hidden) return "hidden";
  return weapon.type === "missile" || ship.allocation.weapons.includes(weapon.id) ? "charged" : "standby";
};

const weaponAbbreviation = (weapon) => weapon.mount || ({ beam: "LB", driver: "MD", missile: "M" })[weapon.type];

export const weaponHint = (weapon) => {
  const profile = WEAPONS[weapon.type];
  const resource = weapon.type === "missile" ? `${weapon.ammo ?? 0} rounds` : `${profile.energy} energy`;
  if (weapon.type === "missile") {
    return `<div class="weapon-hint-heading"><span><i>${weaponAbbreviation(weapon)}</i></span><div><b>${profile.label}</b><small>Arc ${weapon.arc.join("/")} · ${resource}</small></div></div>
      <div class="weapon-hint-contact"><span>Speed</span><b>24 · 2 hexes / impulse</b><span>Contact</span><b>3 damage</b></div>`;
  }
  const bands = [["S", profile.short, profile.hit[0], profile.damage[0]], ["M", profile.medium, profile.hit[1], profile.damage[1]], ["L", profile.long, profile.hit[2], profile.damage[2]]];
  return `<div class="weapon-hint-heading"><span><i>${weaponAbbreviation(weapon)}</i></span><div><b>${profile.label}</b><small>Arc ${weapon.arc.join("/")} · ${resource}</small></div></div>
    <div class="weapon-hint-matrix"><span>Band</span><span>Range</span><span>Hit</span><span>Dmg</span>${bands.map(([band, range, hit, damage]) => `<b>${band}</b><i>${range}</i><i>${hit}</i><i>${damage}</i>`).join("")}</div>`;
};

const weaponHardpoints = (ship, hidden, damagedWeaponIds = []) => {
  const mounts = HARDPOINTS[ship.key] || [];
  const selectedId = (ship.weapons.find((weapon) => !weapon.destroyed) || ship.weapons[0])?.id;
  return ship.weapons.map((weapon, index) => {
    const [x, y] = mounts[index] || [0, (index * 14) - 14];
    const state = weaponState(weapon, ship, hidden);
    const profile = WEAPONS[weapon.type];
    const pipCount = weapon.type === "missile" ? Math.min(weapon.ammo || 0, 4) : profile.energy;
    const pips = Array.from({ length: pipCount }, (_, pip) => `<circle class="hardpoint-pip" cx="${x - ((pipCount - 1) * .8) + (pip * 1.6)}" cy="${y + 2.55}" r=".4"/>`).join("");
    return `<g class="weapon-hardpoint ${state} ${weapon.id === selectedId ? "selected" : ""} ${damagedWeaponIds.includes(weapon.id) ? "recent-damage" : ""}" data-weapon-id="${weapon.id}" data-arcs="${weapon.arc.join(" ")}" data-weapon-label="${profile.label}" tabindex="0" role="button" aria-label="${profile.label}, ${state}">
      <title>${profile.label} · ${weapon.arc.join("/")} · ${state}</title><rect class="hardpoint-bay" x="${x - 4.2}" y="${y - 4.2}" width="8.4" height="8.4" rx="1.1"/><rect class="hardpoint-control" x="${x - 3.2}" y="${y - 3.2}" width="6.4" height="6.4" rx=".5"/><text x="${x}" y="${y + .8}">${weaponAbbreviation(weapon)}</text>${pips}<path class="hardpoint-damage" d="M${x - 2.4} ${y - 2.4}L${x + 2.4} ${y + 2.4}M${x + 2.4} ${y - 2.4}L${x - 2.4} ${y + 2.4}"/>
    </g>`;
  }).join("");
};

export function shipGlyph(ship, className = "", options = {}) {
  const hardpoints = options.hardpoints ? weaponHardpoints(ship, options.hidden, options.damagedWeaponIds) : "";
  const accessibility = options.hardpoints ? `role="group" aria-label="${ship.name} weapon hardpoints"` : "aria-hidden=\"true\"";
  const hull = options.art
    ? `<image class="engineering-hull-art" href="${options.art}" x="-44" y="-44" width="88" height="88" preserveAspectRatio="xMidYMid meet"/>`
    : `<g class="ship-token fleet-${ship.fleet}">${shipHull(ship)}</g>`;
  return `<svg class="ship-glyph ${className} ${options.art ? "art-backed" : ""}" viewBox="-44 -44 88 88" ${accessibility}>${hull}${hardpoints}</svg>`;
}

const hexPoints = (x, y, size = 45) => Array.from({ length: 6 }, (_, index) => {
  const angle = (60 * index) * Math.PI / 180;
  return `${(x + size * Math.cos(angle)).toFixed(1)},${(y + size * Math.sin(angle)).toFixed(1)}`;
}).join(" ");

const arcHexCluster = (ship) => {
  const weapon = ship.weapons.find((entry) => !entry.destroyed) || ship.weapons[0];
  const selectedArcs = weapon?.arc || [];
  const cells = [
    { x: 0, y: -78, arcs: ["F"], label: "F" },
    { x: 67.5, y: -39, arcs: ["F", "R"], label: "F/R" },
    { x: 67.5, y: 39, arcs: ["R", "A"], label: "R/A" },
    { x: 0, y: 78, arcs: ["A"], label: "A" },
    { x: -67.5, y: 39, arcs: ["A", "L"], label: "A/L" },
    { x: -67.5, y: -39, arcs: ["L", "F"], label: "L/F" }
  ];
  const outerHexes = cells.map((cell) => {
    const active = cell.arcs.some((arc) => selectedArcs.includes(arc));
    return `<g class="arc-hex ${active ? "active" : ""}" data-arcs="${cell.arcs.join(" ")}"><polygon points="${hexPoints(cell.x, cell.y)}"/><text x="${cell.x}" y="${cell.y + 3}">${cell.label}</text></g>`;
  }).join("");

  return `<div class="arc-vignette" aria-hidden="true"><div class="arc-readout"><span>Firing solution</span><b>${weapon ? `${WEAPONS[weapon.type].label} · ${selectedArcs.join("/")}` : "No weapons online"}</b></div><svg class="arc-hex-cluster" viewBox="-125 -130 250 260" aria-label="Firing arc diagram"><g class="arc-hex center"><polygon points="${hexPoints(0, 0)}"/></g>${outerHexes}</svg></div>`;
};

const trackBoxes = (count, active, kind, startAt = 1) => Array.from({ length: count }, (_, index) => {
  const online = index < active;
  return `<span class="track-box ${online ? "online" : "spent"} ${kind}">${index + startAt}</span>`;
}).join("");

const systemTrack = (label, count, active, kind, note = "", recentDamage = false) => {
  return `
  <section class="system-track ${kind} ${recentDamage ? "recent-damage" : ""}">
    <header><h3>${label}</h3><span>${active}/${count}${note ? ` · ${note}` : ""}</span></header>
    <div class="track-boxes">${trackBoxes(count, active, kind)}</div>
  </section>`;
};

const shieldBank = (label, count, active, columns, recentDamage = false) => {
  const boxWidth = `calc(${(100 / columns).toFixed(4)}% - ${(((columns - 1) * 2) / columns).toFixed(2)}px)`;
  return `<div class="compact-shield-bank ${recentDamage ? "recent-damage" : ""}">
    <div><span>${label}</span><b>${active}/${count}</b></div>
    <div class="compact-shield-boxes" style="--shield-box-width:${boxWidth}">${trackBoxes(count, active, "shield")}</div>
  </div>`;
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
  const state = weaponState(weapon, ship, hidden);
  const selectedId = (ship.weapons.find((entry) => !entry.destroyed) || ship.weapons[0])?.id;
  const resource = weapon.type === "missile" ? `${weapon.ammo ?? 0} missiles` : `${profile.energy} energy`;
  return `<article class="weapon-module ${state} ${weapon.id === selectedId ? "selected" : ""}" data-weapon-id="${weapon.id}" data-arcs="${weapon.arc.join(" ")}" data-weapon-label="${profile.label}" tabindex="0">
    <div class="hardpoint"><span>${weaponAbbreviation(weapon)}</span></div>
    <div><h4>${profile.label} <small>${weapon.mount || ""}</small></h4><p>Arc ${weapon.arc.join(" · ")} <i>${resource}</i></p></div>
    <strong>${state === "destroyed" ? "DESTROYED" : hidden ? "UNREVEALED" : state.toUpperCase()}</strong>
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

const damageReport = (event) => {
  if (!event?.damage) return "";
  const damage = event.damage;
  const before = damage.before || {};
  const after = damage.after || {};
  const details = [];
  if (damage.reinforcement_absorbed > 0) details.push(`${damage.shield_bank} reinforcement ${before.shield_reinforcement?.[damage.shield_bank] ?? "?"} → ${after.shield_reinforcement?.[damage.shield_bank] ?? "?"}`);
  if (damage.shield_absorbed > 0) details.push(`${damage.shield_bank} shield ${before.shields?.[damage.shield_bank] ?? "?"} → ${after.shields?.[damage.shield_bank] ?? "?"}`);
  if (damage.hull > 0) details.push(`hull ${before.hull ?? "?"} → ${after.hull ?? "?"}`);
  if (damage.engines > 0) details.push(`engine damage ${before.engines ?? "?"} → ${after.engines ?? "?"}`);
  (damage.weapons || []).forEach((weapon) => details.push(`${weapon.mount || weaponAbbreviation(weapon)} ${WEAPONS[weapon.type]?.label || "weapon"} destroyed`));
  if (damage.destroyed) details.push("ship destroyed");
  const summary = details.length ? details : ["impact fully absorbed"];
  return `<aside class="damage-report" role="status" aria-live="assertive"><div><span>Damage report</span><b>${event.weapon_label} impact · ${damage.amount} damage</b></div><ul>${summary.map((detail) => `<li>${detail}</li>`).join("")}</ul></aside>`;
};

const shipAtDamageSnapshot = (ship, damageEvent) => {
  const snapshot = damageEvent?.damage?.after;
  if (!snapshot) return ship;
  const destroyedWeaponIds = snapshot.destroyed_weapon_ids || [];
  return {
    ...ship,
    shields: { ...ship.shields, ...snapshot.shields },
    hull: snapshot.hull,
    destroyed: snapshot.destroyed,
    allocation: {
      ...ship.allocation,
      shields: { ...ship.allocation.shields, ...snapshot.shield_reinforcement }
    },
    damage: { ...ship.damage, engines: snapshot.engines },
    weapons: ship.weapons.map((weapon) => ({ ...weapon, destroyed: destroyedWeaponIds.includes(weapon.id) }))
  };
};

export function shipSchematic(ship, state, player, damageEvent = null, tacticalArt = null) {
  ship = shipAtDamageSnapshot(ship, damageEvent);
  const privateAllocation = state.phase === "allocation" && ship.player !== player;
  const availableEnergy = Math.max(ship.energy - ship.damage.engines, 0);
  const maxFrontShields = ship.max_front_shields || ship.shields.front;
  const maxAftShields = ship.max_aft_shields || ship.shields.aft;
  const weaponTypes = [...new Set(ship.weapons.map((weapon) => weapon.type))];
  const owner = ship.player === "player_one" ? "Player One" : "Player Two";
  const maneuver = ship.size === "large" ? "Capital ships have no special maneuver" : ship.special_available ? "Special maneuver ready" : "Special maneuver expended";
  const hexColumn = ship.position[0] + 1;
  const hexRow = ship.position[1] + Math.floor(ship.position[0] / 2) + 1;
  const hexReference = `${String(hexColumn).padStart(2, "0")}${String(hexRow).padStart(2, "0")}`;
  const recentDamage = damageEvent?.damage || {};
  const damagedWeaponIds = (recentDamage.weapons || []).map((weapon) => weapon.id);
  const shieldColumns = Math.max(maxFrontShields, maxAftShields);
  const frontShieldDamaged = recentDamage.shield_bank === "front" && (recentDamage.shield_absorbed > 0 || recentDamage.reinforcement_absorbed > 0);
  const aftShieldDamaged = recentDamage.shield_bank === "aft" && (recentDamage.shield_absorbed > 0 || recentDamage.reinforcement_absorbed > 0);

  return `<div class="schematic-backdrop" role="presentation">
    <section class="ship-schematic fleet-${ship.fleet} ${damageEvent ? "damage-review" : ""}" role="dialog" aria-modal="true" aria-labelledby="schematic-title">
      <header class="schematic-header">
        <div><p class="eyebrow">${fleetName(ship.fleet)} · ${ship.size} hull · ${owner}</p><h2 id="schematic-title">${ship.name}</h2></div>
        <dl class="header-readout"><div><dt>Hex</dt><dd>${hexReference}</dd></div><div><dt>Facing</dt><dd>${ship.position[2]}</dd></div><div><dt>Turn</dt><dd>${state.turn}</dd></div><div><dt>Impulse</dt><dd>${state.impulse}</dd></div><div><dt>Energy</dt><dd>${availableEnergy}</dd></div></dl>
        <button class="schematic-close" aria-label="Close ship schematic">×</button>
      </header>
      ${damageReport(damageEvent)}
      <div class="schematic-grid">
        <div class="schematic-systems">
          ${movementTrack(ship.allocation.speed, privateAllocation)}
          ${systemTrack("Reactor / engines", ship.energy, availableEnergy, "energy", `${ship.damage.engines} damaged`, recentDamage.engines > 0)}
          ${systemTrack("Hull integrity", ship.max_hull, Math.max(ship.hull, 0), "hull", "", recentDamage.hull > 0)}
          ${turnModes(ship.size)}
          <section class="maneuver-status ${ship.special_available ? "ready" : "spent"}"><span></span><div><h3>Special maneuver</h3><p>${maneuver}</p></div></section>
        </div>
        <div class="schematic-vessel">
          <div class="schematic-hull">
            <div class="schematic-view-controls"><span>Engineering view</span><button class="toggle-arcs" type="button" aria-pressed="false">Show firing arcs</button></div>
            ${arcHexCluster(ship)}
            <div class="engineering-shield-bank forward" aria-hidden="false">${shieldBank("Forward shield", maxFrontShields, ship.shields.front, shieldColumns, frontShieldDamaged)}</div>
            ${shipGlyph(ship, `ship-glyph-schematic fleet-${ship.fleet} ship-${ship.key}`, { hardpoints: true, hidden: privateAllocation, damagedWeaponIds, art: tacticalArt })}
            <div class="engineering-shield-bank aft" aria-hidden="false">${shieldBank("Aft shield", maxAftShields, ship.shields.aft, shieldColumns, aftShieldDamaged)}</div>
          </div>
          <div class="weapon-rack">${ship.weapons.map((weapon) => weaponModule(weapon, ship, privateAllocation)).join("")}</div>
        </div>
        <div class="schematic-reference">
          <p class="eyebrow reference-label">Weapon reference</p>
          ${weaponTypes.map(weaponChart).join("")}
        </div>
      </div>
    </section>
  </div>`;
}
