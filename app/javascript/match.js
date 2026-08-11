import { fleetName, shipGlyph, shipHull, shipSchematic } from "ship_visuals";

const csrf = () => document.querySelector("meta[name='csrf-token']")?.content;

export function mountMatch(root) {
  let state = JSON.parse(root.dataset.matchState);
  const matchId = root.dataset.matchId;
  let player = "player_one";
  let zoom = 1;
  let selectedShipId = null;

  const request = async (action, payload = {}) => {
    const response = await fetch(`/matches/${matchId}/action`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf(), "Accept": "application/json" },
      body: JSON.stringify({ player, action, payload })
    });
    const result = await response.json();
    if (!response.ok) { window.alert(result.error); return; }
    state = result; render();
  };

  const enemy = () => state.ships.find((ship) => ship.player !== player && !ship.destroyed);
  const mine = () => state.ships.find((ship) => ship.player === player && !ship.destroyed);
  const shipCard = (ship) => `
    <article class="ship-card fleet-${ship.fleet} ${ship.destroyed ? "destroyed" : ""}" data-ship-id="${ship.id}" role="button" tabindex="0" aria-label="Open ${ship.name} schematic">
      <div class="ship-card-icon">${shipGlyph(ship, "ship-glyph-card")}</div>
      <div><p class="eyebrow">${fleetName(ship.fleet)} · ${ship.size}</p><h3>${ship.name}</h3>
      <dl><div><dt>Hull</dt><dd>${ship.hull}/${ship.max_hull}</dd></div><div><dt>Shields</dt><dd>F ${ship.shields.front} · A ${ship.shields.aft}</dd></div><div><dt>Energy</dt><dd>${ship.energy - ship.damage.engines}</dd></div></dl><span class="schematic-cue">Open schematic ↗</span></div>
    </article>`;
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
      const reference = `${row + 1}${String(column + 1).padStart(2, "0")}`;
      cells.push(`<g class="hex-cell"><polygon points="${polygon(x, y)}"/><text class="hex-reference" x="${x}" y="${y - (hexHeight / 2) + 12}">${reference}</text></g>`);
    }
    return `<g class="hex-grid">${cells.join("")}</g>`;
  };
  const hex = (ship) => {
    const [q, r, facing] = ship.position; const [x, y] = center(q, r);
    return `<g class="ship-token fleet-${ship.fleet} ${ship.destroyed ? "destroyed" : ""}" data-ship-id="${ship.id}" role="button" tabindex="0" aria-label="Open ${ship.name} schematic" transform="translate(${x} ${y}) rotate(${120 - (facing * 60)}) scale(.86)">${shipHull(ship)}</g>`;
  };
  const weaponName = (weapon) => weapon.type === "beam" ? "Lance beam" : weapon.type === "driver" ? "Mass driver" : "Seeker missile";
  const weaponEnergy = (weapon) => weapon.type === "beam" ? 2 : weapon.type === "driver" ? 1 : 0;
  const weaponChoices = (ship) => ship.weapons.filter((weapon) => weapon.type !== "missile" && !weapon.destroyed).map((weapon) => `
    <label class="weapon-allocation">
      <input type="checkbox" value="${weapon.id}" data-energy="${weaponEnergy(weapon)}" ${ship.allocation.weapons.includes(weapon.id) ? "checked" : ""}>
      <span><b>${weapon.mount || weaponName(weapon)}</b>${weaponName(weapon)} · Arc ${weapon.arc.join("/")}</span>
      <em>${weaponEnergy(weapon)}E</em>
    </label>`).join("");
  const controls = (ship, target) => {
    if (state.winner) return `<a class="button" href="/">Return to fleet selection</a>`;
    if (state.phase === "allocation") return `<div class="control-stack"><label>Speed <output id="speed-value">${ship.allocation.speed}</output><input id="speed" type="range" min="0" max="12" value="${ship.allocation.speed}"></label><label>Shield reinforcement <output id="shields-value">${ship.allocation.shields}</output><input id="shields" type="range" min="0" max="${ship.size === "small" ? 1 : ship.size === "medium" ? 2 : 3}" value="${ship.allocation.shields}"></label><fieldset class="weapon-allocation-list"><legend>Weapon circuits</legend>${weaponChoices(ship)}</fieldset><div class="allocation-budget"><span>Energy committed</span><b><output id="energy-used">0</output> / ${ship.energy - ship.damage.engines}</b></div><button class="primary save-allocation">Set allocation</button><button class="secondary lock-allocation">Lock allocation</button></div>`;
    return `<div class="control-stack"><button class="primary advance">Draw next impulse</button>${target ? ship.weapons.filter((w) => !w.destroyed).map((w) => `<button class="secondary fire" data-weapon="${w.id}">Fire ${w.mount ? `${w.mount} ` : ""}${weaponName(w)} at ${target.name}</button>`).join("") : ""}${ship.special_available ? `<button class="secondary special">Emergency power maneuver</button>` : ""}</div>`;
  };
  const bind = (ship, target) => {
    root.querySelector(".switch-player")?.addEventListener("click", () => { player = player === "player_one" ? "player_two" : "player_one"; render(); });
    root.querySelector(".zoom-out")?.addEventListener("click", () => { zoom = Math.max(.75, zoom - .25); render(); });
    root.querySelector(".zoom-reset")?.addEventListener("click", () => { zoom = 1; render(); });
    root.querySelector(".zoom-in")?.addEventListener("click", () => { zoom = Math.min(1.75, zoom + .25); render(); });
    const updateEnergyBudget = () => {
      const speed = Number(root.querySelector("#speed")?.value || 0);
      const shields = Number(root.querySelector("#shields")?.value || 0);
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
    root.querySelector(".save-allocation")?.addEventListener("click", () => request("allocate", { ship_id: ship.id, speed: root.querySelector("#speed").value, shields: root.querySelector("#shields").value, weapons: [...root.querySelectorAll(".weapon-allocation input:checked")].map((input) => input.value) }));
    root.querySelector(".lock-allocation")?.addEventListener("click", () => request("lock_allocation"));
    root.querySelector(".advance")?.addEventListener("click", () => request("advance_impulse"));
    root.querySelectorAll(".fire").forEach((button) => button.addEventListener("click", () => request("fire", { ship_id: ship.id, target_id: target.id, weapon_id: button.dataset.weapon })));
    root.querySelector(".special")?.addEventListener("click", () => request("special", { ship_id: ship.id, maneuver: "emergency_power" }));
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
    const selectedShip = state.ships.find((ship) => ship.id === selectedShipId);
    root.innerHTML = `
      <header class="game-header"><a href="/" class="wordmark">THE <strong>SHATTERED</strong> REACH</a><div class="turn-state"><span>TURN ${state.turn}</span><b>${state.winner ? `${state.winner === "player_one" ? "Player One" : "Player Two"} wins` : state.phase === "allocation" ? "Secret allocation" : `Impulse ${state.impulse} · ${state.initiative === player ? "You hold initiative" : "Opponent holds initiative"}`}</b></div><button class="switch-player">Viewing: ${player === "player_one" ? "Player One" : "Player Two"}</button></header>
      <main class="match-layout"><section class="command-panel"><p class="eyebrow">${state.scenario === "tutorial" ? `Tutorial · ${["Set the battle plan", "Reveal allocations", "Watch an impulse", "Fire your first weapon"][state.tutorial_step] || "Continue the engagement"}` : "Fleet command"}</p><h1>${state.phase === "allocation" ? "Commit your energy" : "Command the engagement"}</h1><p class="quiet">${state.log.at(-1)}</p>${current ? controls(current, target) : ""}</section>
      <section class="battlefield"><div class="nebula"></div><div class="zoom-controls" aria-label="Battlefield zoom"><button class="zoom-out" aria-label="Zoom out">−</button><button class="zoom-reset" aria-label="Reset zoom">${Math.round(zoom * 100)}%</button><button class="zoom-in" aria-label="Zoom in">+</button></div><svg viewBox="0 0 ${boardWidth} ${boardHeight}" aria-label="${boardSize} by ${boardSize} tactical flat-top hex battlefield" style="width:${zoom * 100}%;max-width:none">${grid()}${state.ships.map(hex).join("")}</svg><div class="battlefield-label">Tactical display · ${boardSize} × ${boardSize} · numbered flat-top hex grid</div></section>
      <aside class="fleet-status"><h2>Fleet status</h2><p class="fleet-status-hint">Select a ship for its combat schematic.</p>${state.ships.map(shipCard).join("")}</aside></main>${selectedShip ? shipSchematic(selectedShip, state, player) : ""}`;
    bind(current, target);
  };
  render();
}
