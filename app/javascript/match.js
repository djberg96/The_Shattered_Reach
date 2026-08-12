import { fleetName, shipGlyph, shipHull, shipSchematic } from "ship_visuals";

const csrf = () => document.querySelector("meta[name='csrf-token']")?.content;

export function mountMatch(root) {
  let state = JSON.parse(root.dataset.matchState);
  const matchId = root.dataset.matchId;
  let player = "player_one";
  let zoom = 1;
  let selectedShipId = null;
  const directions = [[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]];

  const request = async (action, payload = {}) => {
    const response = await fetch(`/matches/${matchId}/action`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf(), "Accept": "application/json" },
      body: JSON.stringify({ player, command: action, payload })
    });
    const result = await response.json();
    if (!response.ok) { window.alert(result.error); return false; }
    state = result; render(); return true;
  };

  const enemy = () => state.ships.find((ship) => ship.player !== player && !ship.destroyed);
  const mine = () => state.ships.find((ship) => ship.player === player && !ship.destroyed);
  const shipCard = (ship) => { const selectable = !state.solo || ship.player === player; const relationship = state.solo ? ship.player === player ? "Your ship" : "AI opponent" : ship.player === "player_one" ? "Player One" : "Player Two"; return `
    <article class="ship-card fleet-${ship.fleet} ${ship.destroyed ? "destroyed" : ""} ${selectable ? "selectable" : "readonly ai-opponent"}" ${selectable ? `data-ship-id="${ship.id}" role="button" tabindex="0" aria-label="Open ${ship.name} schematic"` : `aria-label="${ship.name}, AI-controlled opponent"`}>
      <div class="ship-card-icon">${shipGlyph(ship, "ship-glyph-card")}</div>
      <div><p class="eyebrow">${relationship} · ${fleetName(ship.fleet)} · ${ship.size}</p><h3>${ship.name}</h3>
      <dl><div><dt>Hull</dt><dd>${ship.hull}/${ship.max_hull}</dd></div><div><dt>Shields</dt><dd>F ${ship.shields.front} · A ${ship.shields.aft}</dd></div><div><dt>Energy</dt><dd>${ship.energy - ship.damage.engines}</dd></div></dl><span class="schematic-cue">${selectable ? "Open your schematic ↗" : "Controlled by command AI"}</span></div>
    </article>`; };
  const hexSize = 42;
  const boardSize = [12, 15, 20].includes(Number(state.board_size)) ? Number(state.board_size) : 15;
  const hexHeight = Math.sqrt(3) * hexSize;
  const boardWidth = (2 * hexSize) + ((boardSize - 1) * 1.5 * hexSize);
  const boardHeight = (boardSize + .5) * hexHeight;
  const center = (q, r) => {
    const row = r + Math.floor(q / 2);
    return [hexSize + (1.5 * hexSize * q), (hexHeight / 2) + (hexHeight * row) + ((q % 2) * hexHeight / 2)];
  };
  const polygon = (x, y, size = hexSize) => Array.from({ length: 6 }, (_, index) => {
    const angle = (60 * index) * Math.PI / 180;
    return `${(x + size * Math.cos(angle)).toFixed(1)},${(y + size * Math.sin(angle)).toFixed(1)}`;
  }).join(" ");
  const grid = () => {
    const cells = [];
    for (let row = 0; row < boardSize; row += 1) for (let column = 0; column < boardSize; column += 1) {
      const q = column; const r = row - Math.floor(column / 2); const [x, y] = center(q, r);
      const reference = `${String(column + 1).padStart(2, "0")}${String(row + 1).padStart(2, "0")}`;
      cells.push(`<g class="hex-cell"><polygon points="${polygon(x, y)}"/><text class="hex-reference" x="${x}" y="${y - (hexHeight / 2) + 12}">${reference}</text></g>`);
    }
    return `<g class="hex-grid">${cells.join("")}</g>`;
  };
  const hex = (ship) => {
    const [q, r, facing] = ship.position; const [x, y] = center(q, r);
    const selectable = !state.solo || ship.player === player;
    const moving = state.pending_movement?.[0] === ship.id;
    return `<g class="ship-token fleet-${ship.fleet} ${ship.destroyed ? "destroyed" : ""} ${moving ? "movement-active" : ""} ${selectable ? "selectable" : "ai-opponent"}" ${selectable ? `data-ship-id="${ship.id}" role="button" tabindex="0" aria-label="Open ${ship.name} schematic"` : `aria-label="${ship.name}, AI-controlled opponent"`} transform="translate(${x} ${y}) rotate(${120 - (facing * 60)}) scale(.86)">${shipHull(ship)}</g>`;
  };
  const missileCounter = (missile) => {
    const [q, r, facing] = missile.position; const [x, y] = center(q, r);
    return `<g class="missile-counter fleet-${missile.fleet}" transform="translate(${x} ${y}) rotate(${120 - (facing * 60)})" aria-label="Seeker missile">
      <circle class="missile-pulse" r="16"/><path class="missile-wake" d="M-5 10 L0 22 L5 10"/>
      <path class="missile-body" d="M0 -15 L8 8 L3 6 L0 12 L-3 6 L-8 8 Z"/><text x="0" y="2">M</text>
    </g>`;
  };
  const weaponName = (weapon) => weapon.type === "beam" ? "Lance beam" : weapon.type === "driver" ? "Mass driver" : "Seeker missile";
  const weaponEnergy = (weapon) => weapon.type === "beam" ? 2 : weapon.type === "driver" ? 1 : 0;
  const axialDistance = (a, b) => (Math.abs(a[0] - b[0]) + Math.abs(a[1] - b[1]) + Math.abs((a[0] + a[1]) - (b[0] + b[1]))) / 2;
  const targetInArc = (attacker, target, arcs) => {
    const range = axialDistance(attacker.position, target.position);
    const bearing = directions.map((delta, direction) => ({ direction, distance: axialDistance([attacker.position[0] + delta[0], attacker.position[1] + delta[1]], target.position) })).filter((entry) => entry.distance < range).map((entry) => entry.direction);
    const offsets = { F: [-1, 0, 1], L: [1, 2, 3], A: [2, 3, 4], R: [3, 4, 5] };
    const permitted = arcs.flatMap((arc) => (offsets[arc] || []).map((offset) => (attacker.position[2] + offset + 6) % 6));
    return bearing.some((direction) => permitted.includes(direction));
  };
  const directWeaponLegal = (ship, target, weapon) => {
    const maximumRange = weapon.type === "beam" ? 9 : 12;
    return axialDistance(ship.position, target.position) <= maximumRange && targetInArc(ship, target, weapon.arc);
  };
  const currentTurnMode = (ship) => {
    const speed = Number(ship.allocation.speed); const speedBand = speed <= 4 ? 0 : speed <= 8 ? 1 : 2;
    return ({ small: 0, medium: 1, large: 2 }[ship.size] || 0) + speedBand;
  };
  const movementDestination = (ship, maneuver) => {
    const direction = maneuver === "sideslip_left" ? (ship.position[2] + 1) % 6 : maneuver === "sideslip_right" ? (ship.position[2] + 5) % 6 : ship.position[2];
    const delta = directions[direction];
    return [ship.position[0] + delta[0], ship.position[1] + delta[1]];
  };
  const hexReference = ([q, r]) => `${String(q + 1).padStart(2, "0")}${String(r + Math.floor(q / 2) + 1).padStart(2, "0")}`;
  const activityStrip = () => {
    const steps = [["movement", "1 Move"], ["launch", "2 Launch"], ["fire", "3 Fire"]];
    const order = { movement: 0, launch: 1, fire: 2 };
    return `<div class="activity-strip">${steps.map(([step, label]) => `<span class="${state.activity_step === step ? "current" : order[state.activity_step] > order[step] ? "done" : ""}">${label}</span>`).join("")}</div>`;
  };
  const movementChoices = () => {
    if (state.activity_step !== "movement") return "";
    const movingShip = state.ships.find((ship) => ship.id === state.pending_movement?.[0]);
    if (!movingShip || movingShip.player !== player) return "";
    return (state.movement_options || []).filter((maneuver) => ["forward", "sideslip_left", "sideslip_right"].includes(maneuver)).map((maneuver) => {
      const destination = movementDestination(movingShip, maneuver); const [x, y] = center(...destination);
      const label = maneuver === "forward" ? "FORWARD" : maneuver === "sideslip_left" ? "PORT" : "STARBOARD";
      return `<g class="movement-choice" data-maneuver="${maneuver}" role="button" tabindex="0" aria-label="${label} to hex ${hexReference(destination)}"><polygon points="${polygon(x, y, hexSize - 3)}"/><text x="${x}" y="${y - 2}">${label}</text><text class="destination-reference" x="${x}" y="${y + 10}">${hexReference(destination)}</text></g>`;
    }).join("");
  };
  const weaponChoices = (ship) => ship.weapons.filter((weapon) => weapon.type !== "missile" && !weapon.destroyed).map((weapon) => `
    <label class="weapon-allocation">
      <input type="checkbox" value="${weapon.id}" data-energy="${weaponEnergy(weapon)}" ${ship.allocation.weapons.includes(weapon.id) ? "checked" : ""}>
      <span><b>${weapon.mount || weaponName(weapon)}</b>${weaponName(weapon)} · Arc ${weapon.arc.join("/")}</span>
      <em>${weaponEnergy(weapon)}E</em>
    </label>`).join("");
  const controls = (ship, target) => {
    if (state.winner) return `<a class="button" href="/">Return to fleet selection</a>`;
    if (state.phase === "allocation") { const shieldCap = ship.size === "small" ? 1 : ship.size === "medium" ? 2 : 3; return `<div class="control-stack"><label>Speed <output id="speed-value">${ship.allocation.speed}</output><input id="speed" type="range" min="0" max="12" value="${ship.allocation.speed}"></label><fieldset class="shield-allocation-list"><legend>Shield reinforcement</legend><label>Forward <output id="front-shields-value">${ship.allocation.shields.front}</output><input id="front-shields" type="range" min="0" max="${ship.shields.front > 0 ? shieldCap : 0}" value="${ship.allocation.shields.front}"></label><label>Aft <output id="aft-shields-value">${ship.allocation.shields.aft}</output><input id="aft-shields" type="range" min="0" max="${ship.shields.aft > 0 ? shieldCap : 0}" value="${ship.allocation.shields.aft}"></label></fieldset><fieldset class="weapon-allocation-list"><legend>Weapon circuits</legend>${weaponChoices(ship)}</fieldset><div class="allocation-budget"><span>Energy committed</span><b><output id="energy-used">0</output> / ${ship.energy - ship.damage.engines}</b></div><p class="allocation-help"><b>Save draft</b> stores this plan but keeps it editable. <b>Commit allocation</b> saves the current plan and makes it final for this turn${state.solo ? "; the AI then commits its own plan" : ""}.</p><button class="secondary save-allocation">Save draft</button><button class="primary commit-allocation">Commit allocation</button></div>`; }
    if (state.activity_step === "draw") return `<div class="control-stack">${activityStrip()}<p class="step-help">Draw the next card to discover which speeds receive a movement opportunity.</p><button class="primary advance">${state.impulse === 0 ? "Draw first impulse" : "Draw next impulse"}</button></div>`;
    if (state.activity_step === "movement") {
      const movingShip = state.ships.find((entry) => entry.id === state.pending_movement?.[0]);
      if (!movingShip || movingShip.player !== player) return `<div class="control-stack">${activityStrip()}<p class="step-callout"><b>${movingShip?.name || "Another ship"}</b> moves next.</p><p class="step-help">${state.solo ? "Command AI is resolving its maneuver." : "Pass command and use the player switch above."}</p></div>`;
      const labels = { forward: "Move forward", sideslip_left: "Side-slip port", sideslip_right: "Side-slip starboard", turn_left: "Turn 60° port", turn_right: "Turn 60° starboard", lose_movement: "Lose blocked movement" };
      const options = (state.movement_options || []).map((maneuver) => `<button class="${maneuver === "forward" ? "primary" : "secondary"} move-ship" data-maneuver="${maneuver}">${labels[maneuver]}</button>`).join("");
      const special = movingShip.special_available ? `<details class="special-maneuvers"><summary>Use one-time special maneuver</summary><button class="secondary special" data-special="emergency_power">Emergency power · extra forward move</button><button class="secondary special" data-special="quick_stop">Quick stop · speed zero</button><label>Bootlegger heading<select id="bootlegger-facing">${["East", "Northeast", "Northwest", "West", "Southwest", "Southeast"].map((label, direction) => `<option value="${direction}" ${movingShip.position[2] === direction ? "selected" : ""}>${label}</option>`).join("")}</select></label><button class="secondary bootlegger">Bootlegger · rotate freely</button></details>` : "";
      return `<div class="control-stack">${activityStrip()}<p class="step-callout"><b>${movingShip.name}</b> has a movement opportunity.</p><p class="step-help">Choose one highlighted destination or turn in place. Turn mode ${currentTurnMode(movingShip)}: ${movingShip.movement?.hexes_since_turn || 0} forward hexes accumulated.</p><div class="impulse-card"><span>Movement card</span><b>${(state.impulse_card || []).join(" · ")}</b></div>${options}${special}</div>`;
    }
    if (state.activity_step === "launch") {
      const launchers = target ? ship.weapons.filter((weapon) => weapon.type === "missile" && !weapon.destroyed && !weapon.fired && weapon.ammo > 0) : [];
      return `<div class="control-stack">${activityStrip()}<p class="step-help">Existing missiles have moved. Launch any new missiles now; they remain in your hex until the next impulse.</p>${launchers.map((weapon) => `<button class="secondary launch-missile" data-weapon="${weapon.id}">Launch ${weapon.mount || "M"} seeker missile at ${target.name} · ${weapon.ammo} remaining</button>`).join("")}<button class="primary finish-launches">${launchers.length ? "Finish missile launches" : "Continue to weapons fire"}</button></div>`;
    }
    const legalWeapons = target ? ship.weapons.filter((weapon) => weapon.type !== "missile" && !weapon.destroyed && !weapon.fired && ship.allocation.weapons.includes(weapon.id) && directWeaponLegal(ship, target, weapon)) : [];
    const remainingPowered = ship.weapons.filter((weapon) => weapon.type !== "missile" && !weapon.destroyed && !weapon.fired && ship.allocation.weapons.includes(weapon.id));
    return `<div class="control-stack">${activityStrip()}<p class="step-help">Fire any powered weapon with a legal range and arc, then end the impulse.</p>${legalWeapons.map((weapon) => `<button class="secondary fire" data-weapon="${weapon.id}">Fire ${weapon.mount ? `${weapon.mount} ` : ""}${weaponName(weapon)} · Arc ${weapon.arc.join("/")}<small>Target: ${target.name} · Range ${axialDistance(ship.position, target.position)}</small></button>`).join("")}${legalWeapons.length ? "" : `<p class="no-legal-action">${remainingPowered.length ? "No powered weapon currently has both range and firing arc." : "No unfired direct weapon is powered this turn."}</p>`}<button class="primary finish-impulse">${state.impulse >= 12 ? "End turn" : "End impulse"}</button></div>`;
  };
  const bind = (ship, target) => {
    root.querySelector(".switch-player")?.addEventListener("click", () => { if (!state.solo) { player = player === "player_one" ? "player_two" : "player_one"; render(); } });
    root.querySelector(".zoom-out")?.addEventListener("click", () => { zoom = Math.max(.75, zoom - .25); render(); });
    root.querySelector(".zoom-reset")?.addEventListener("click", () => { zoom = 1; render(); });
    root.querySelector(".zoom-in")?.addEventListener("click", () => { zoom = Math.min(1.75, zoom + .25); render(); });
    const updateEnergyBudget = () => {
      const speed = Number(root.querySelector("#speed")?.value || 0);
      const shields = Number(root.querySelector("#front-shields")?.value || 0) + Number(root.querySelector("#aft-shields")?.value || 0);
      const weapons = [...root.querySelectorAll(".weapon-allocation input:checked")].reduce((sum, input) => sum + Number(input.dataset.energy), 0);
      const used = speed + shields + weapons;
      const budget = root.querySelector(".allocation-budget");
      if (budget) budget.classList.toggle("over", used > ship.energy - ship.damage.engines);
      const output = root.querySelector("#energy-used");
      if (output) output.textContent = used;
    };
    root.querySelectorAll('input[type="range"]').forEach((input) => input.addEventListener("input", () => { root.querySelector(`#${input.id}-value`).textContent = input.value; updateEnergyBudget(); }));
    root.querySelectorAll(".weapon-allocation input").forEach((input) => input.addEventListener("change", updateEnergyBudget));
    updateEnergyBudget();
    const allocationPayload = () => ({ ship_id: ship.id, speed: root.querySelector("#speed").value, front_shields: root.querySelector("#front-shields").value, aft_shields: root.querySelector("#aft-shields").value, weapons: [...root.querySelectorAll(".weapon-allocation input:checked")].map((input) => input.value) });
    root.querySelector(".save-allocation")?.addEventListener("click", () => request("allocate", allocationPayload()));
    root.querySelector(".commit-allocation")?.addEventListener("click", async () => { if (await request("allocate", allocationPayload())) await request("lock_allocation"); });
    root.querySelector(".advance")?.addEventListener("click", () => request("advance_impulse"));
    root.querySelectorAll(".move-ship, .movement-choice").forEach((button) => button.addEventListener("click", () => request("move_ship", { ship_id: state.pending_movement[0], maneuver: button.dataset.maneuver })));
    root.querySelectorAll(".movement-choice").forEach((button) => button.addEventListener("keydown", (event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); request("move_ship", { ship_id: state.pending_movement[0], maneuver: button.dataset.maneuver }); } }));
    root.querySelectorAll(".launch-missile").forEach((button) => button.addEventListener("click", () => request("launch_missile", { ship_id: ship.id, target_id: target.id, weapon_id: button.dataset.weapon })));
    root.querySelector(".finish-launches")?.addEventListener("click", () => request("finish_launches"));
    root.querySelectorAll(".fire").forEach((button) => button.addEventListener("click", () => request("fire", { ship_id: ship.id, target_id: target.id, weapon_id: button.dataset.weapon })));
    root.querySelector(".finish-impulse")?.addEventListener("click", () => request("finish_impulse"));
    root.querySelectorAll(".special").forEach((button) => button.addEventListener("click", () => request("special", { ship_id: state.pending_movement[0], maneuver: button.dataset.special })));
    root.querySelector(".bootlegger")?.addEventListener("click", () => request("special", { ship_id: state.pending_movement[0], maneuver: "bootlegger", direction: root.querySelector("#bootlegger-facing").value }));
    const openSchematic = (element) => {
      selectedShipId = element.dataset.shipId;
      render();
      root.querySelector(".schematic-close")?.focus();
    };
    root.querySelectorAll("[data-ship-id]").forEach((element) => {
      element.addEventListener("click", () => openSchematic(element));
      element.addEventListener("keydown", (event) => {
        if (event.key === "Enter" || event.key === " ") { event.preventDefault(); openSchematic(element); }
      });
    });
    root.querySelector(".schematic-close")?.addEventListener("click", () => { selectedShipId = null; render(); });
    root.querySelector(".schematic-backdrop")?.addEventListener("click", (event) => {
      if (event.target === event.currentTarget) { selectedShipId = null; render(); }
    });
    root.querySelector(".ship-schematic")?.addEventListener("keydown", (event) => {
      if (event.key === "Escape") { selectedShipId = null; render(); }
    });
    root.querySelector(".toggle-arcs")?.addEventListener("click", (event) => {
      const hull = root.querySelector(".schematic-hull");
      const arcsVisible = hull?.classList.toggle("show-arcs") || false;
      event.currentTarget.textContent = arcsVisible ? "Hide firing arcs" : "Show firing arcs";
      event.currentTarget.setAttribute("aria-pressed", String(arcsVisible));
      root.querySelector(".arc-vignette")?.setAttribute("aria-hidden", String(!arcsVisible));
    });
    const displayWeaponArcs = (weaponControl) => {
      const arcs = weaponControl.dataset.arcs.split(" ");
      const weaponId = weaponControl.dataset.weaponId;
      root.querySelectorAll(".weapon-module, .weapon-hardpoint").forEach((entry) => entry.classList.toggle("selected", entry.dataset.weaponId === weaponId));
      root.querySelectorAll(".arc-hex[data-arcs]").forEach((cell) => {
        const cellArcs = cell.dataset.arcs.split(" ");
        cell.classList.toggle("active", cellArcs.some((arc) => arcs.includes(arc)));
      });
      const readout = root.querySelector(".arc-readout b");
      if (readout) readout.textContent = `${weaponControl.dataset.weaponLabel} · ${arcs.join("/")}`;
    };
    root.querySelectorAll(".weapon-module, .weapon-hardpoint").forEach((weaponControl) => {
      weaponControl.addEventListener("mouseenter", () => displayWeaponArcs(weaponControl));
      weaponControl.addEventListener("focus", () => displayWeaponArcs(weaponControl));
      weaponControl.addEventListener("click", () => displayWeaponArcs(weaponControl));
    });
  };
  const render = () => {
    const current = mine(); const target = enemy();
    const selectedShip = state.ships.find((ship) => ship.id === selectedShipId && (!state.solo || ship.player === player));
    const identity = state.solo ? `<div class="solo-identity"><span>You command</span><b>${current?.name || "Fleet destroyed"}</b></div>` : `<button class="switch-player">Viewing: ${player === "player_one" ? "Player One" : "Player Two"}</button>`;
    const activityLabel = { draw: "Awaiting movement card", movement: "Movement phase", launch: "Missile launch phase", fire: "Direct fire phase" }[state.activity_step];
    const commandTitle = state.phase === "allocation" ? "Commit your energy" : { draw: "Draw the next impulse", movement: "Choose your maneuver", launch: "Launch missiles", fire: "Resolve weapons fire" }[state.activity_step] || "Command the engagement";
    root.innerHTML = `
      <header class="game-header"><a href="/" class="wordmark">THE <strong>SHATTERED</strong> REACH</a><div class="turn-state"><span>TURN ${state.turn}${state.phase === "impulse" ? ` · IMPULSE ${state.impulse}` : ""}</span><b>${state.winner ? `${state.winner === "player_one" ? "Player One" : "Player Two"} wins` : state.phase === "allocation" ? "Secret allocation" : activityLabel}</b></div>${identity}</header>
      <main class="match-layout"><section class="command-panel"><p class="eyebrow">${state.solo ? `Solo command · Your ship: ${current?.name}` : state.scenario === "tutorial" ? `Tutorial · ${["Set the battle plan", "Reveal allocations", "Choose a maneuver", "Fire your first weapon"][state.tutorial_step] || "Continue the engagement"}` : "Fleet command"}</p><h1>${commandTitle}</h1><p class="quiet">${state.log.at(-1)}</p>${current ? controls(current, target) : ""}</section>
      <section class="battlefield"><div class="nebula"></div><div class="zoom-controls" aria-label="Battlefield zoom"><button class="zoom-out" aria-label="Zoom out">−</button><button class="zoom-reset" aria-label="Reset zoom">${Math.round(zoom * 100)}%</button><button class="zoom-in" aria-label="Zoom in">+</button></div><svg viewBox="0 0 ${boardWidth} ${boardHeight}" aria-label="${boardSize} by ${boardSize} tactical flat-top hex battlefield" style="width:${zoom * 100}%;max-width:none">${grid()}${movementChoices()}${state.ships.map(hex).join("")}${(state.missiles || []).map(missileCounter).join("")}</svg><div class="battlefield-label">Tactical display · ${boardSize} × ${boardSize} · numbered flat-top hex grid</div></section>
      <aside class="fleet-status"><h2>Fleet status</h2><p class="fleet-status-hint">${state.solo ? "Your ship is selectable; the opposing ship is controlled by the AI." : "Select a ship for its combat schematic."}</p>${state.ships.map(shipCard).join("")}</aside></main>${selectedShip ? shipSchematic(selectedShip, state, player) : ""}`;
    bind(current, target);
  };
  render();
}
