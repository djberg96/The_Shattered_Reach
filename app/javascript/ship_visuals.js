const FLEETS = {
  aurelian: "Aurelian Compact",
  veyr: "Veyr Dominion",
  kestrel: "Kestrel Freeholds"
};

const HULLS = {
  // Aurelian hulls echo the original Mastafarian split-nacelle silhouettes.
  aurelian_frigate: "M0 -35L9 -23L9 -10L18 8L27 -17L35 -8L28 5L34 24L17 23L9 10L6 32L-6 32L-9 10L-17 23L-34 24L-28 5L-35 -8L-27 -17L-18 8L-9 -10L-9 -23Z",
  aurelian_cruiser: "M0 -37L10 -25L10 -11L19 7L29 -20L38 -10L30 6L37 27L18 26L10 12L7 34L-7 34L-10 12L-18 26L-37 27L-30 6L-38 -10L-29 -20L-19 7L-10 -11L-10 -25Z",
  aurelian_battleship: "M0 -38L12 -27L12 -12L21 5L31 -22L40 -12L32 7L39 29L21 29L15 18L14 36L3 36L3 16L-3 16L-3 36L-14 36L-15 18L-21 29L-39 29L-32 7L-40 -12L-31 -22L-21 5L-12 -12L-12 -27Z",

  // Veyr hulls inherit the old Mocha broad, armored wing plan.
  veyr_frigate: "M0 -32L8 -23L14 -10L28 -24L37 -14L31 2L19 9L18 26L9 34L0 27L-9 34L-18 26L-19 9L-31 2L-37 -14L-28 -24L-14 -10L-8 -23Z",
  veyr_cruiser: "M0 -34L9 -25L15 -10L30 -26L40 -15L33 4L20 10L21 29L10 36L0 28L-10 36L-21 29L-20 10L-33 4L-40 -15L-30 -26L-15 -10L-9 -25Z",
  veyr_battleship: "M0 -35L10 -26L17 -10L32 -27L41 -16L35 5L22 11L23 30L11 38L0 29L-11 38L-23 30L-22 11L-35 5L-41 -16L-32 -27L-17 -10L-10 -26Z",

  // Kestrel hulls descend from the original Talapian spear-and-pod family.
  kestrel_frigate: "M0 -38L14 -23L9 -14L9 5L25 14L25 28L11 28L5 16L0 34L-5 16L-11 28L-25 28L-25 14L-9 5L-9 -14L-14 -23Z",
  kestrel_cruiser: "M0 -39L16 -23L10 -13L10 5L29 14L29 30L12 30L5 16L0 36L-5 16L-12 30L-29 30L-29 14L-10 5L-10 -13L-16 -23Z",
  kestrel_battleship: "M0 -40L17 -24L11 -12L11 3L22 10L38 8L41 25L33 33L14 31L6 17L0 38L-6 17L-14 31L-33 33L-41 25L-38 8L-22 10L-11 3L-11 -12L-17 -24Z"
};

// Coordinates deliberately place each weapon on a visible part of its hull.
// Array order matches the weapon order in GameDefinition.
const HARDPOINTS = {
  aurelian_frigate: [[-25, 5], [-25, 14], [25, 5], [25, 14], [0, -22]],
  aurelian_cruiser: [[-26, 5], [-26, 14], [26, 5], [26, 14], [0, -22], [0, 7]],
  aurelian_battleship: [[-28, 2], [-28, 12], [28, 2], [28, 12], [-8.5, 22], [-8.5, 31], [8.5, 22], [8.5, 31], [0, -22], [0, 7]],
  veyr_frigate: [[0, 10], [0, 19], [22, -9], [-23, -10]],
  veyr_cruiser: [[-12, 10], [-12, 19], [12, 10], [12, 19], [24, -10], [-24, -10]],
  veyr_battleship: [[-28, -11], [28, -11], [0, 12]],
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
  const path = HULLS[ship.key] || HULLS[`${ship.fleet}_${ship.size}`] || HULLS.aurelian_cruiser;
  const detail = {
    aurelian: "M0 -27V24M-19 10L-8 4M19 10L8 4M-7 20H7",
    veyr: "M0 -25V25M-27 -11L-13 2M27 -11L13 2M-12 19H12",
    kestrel: "M0 -30V28M-19 13L-8 9M19 13L8 9M-7 -12H7"
  }[ship.fleet];
  return `<path class="hull" d="${path}"/><path class="spine" d="${detail}"/><circle class="engine" cy="28" r="3.5"/>`;
}

const weaponState = (weapon, ship, hidden) => {
  if (weapon.destroyed) return "destroyed";
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
  return `<svg class="ship-glyph ${className}" viewBox="-44 -44 88 88" ${accessibility}><g class="ship-token fleet-${ship.fleet}">${shipHull(ship)}</g>${hardpoints}</svg>`;
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

const shieldPanel = (ship, maxFront, maxAft, damage = {}) => {
  const columns = Math.max(maxFront, maxAft);
  return `<section class="shield-console">
    <header><h3>Shield array</h3><span>hemisphere strength</span></header>
    ${shieldBank("Forward", maxFront, ship.shields.front, columns, damage.shield_bank === "front" && (damage.shield_absorbed > 0 || damage.reinforcement_absorbed > 0))}
    <div class="shield-axis"><span>F</span><i></i><span>A</span></div>
    ${shieldBank("Aft", maxAft, ship.shields.aft, columns, damage.shield_bank === "aft" && (damage.shield_absorbed > 0 || damage.reinforcement_absorbed > 0))}
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

export function shipSchematic(ship, state, player, damageEvent = null) {
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
          ${shieldPanel(ship, maxFrontShields, maxAftShields, recentDamage)}
          ${turnModes(ship.size)}
          <section class="maneuver-status ${ship.special_available ? "ready" : "spent"}"><span></span><div><h3>Special maneuver</h3><p>${maneuver}</p></div></section>
        </div>
        <div class="schematic-vessel">
          <div class="schematic-hull">
            <div class="schematic-view-controls"><span>Engineering view</span><button class="toggle-arcs" type="button" aria-pressed="false">Show firing arcs</button></div>
            ${arcHexCluster(ship)}
            ${shipGlyph(ship, "ship-glyph-schematic", { hardpoints: true, hidden: privateAllocation, damagedWeaponIds })}
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
