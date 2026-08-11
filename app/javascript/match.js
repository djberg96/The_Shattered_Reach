const csrf = () => document.querySelector("meta[name='csrf-token']")?.content;

export function mountMatch(root) {
  let state = JSON.parse(root.dataset.matchState);
  const matchId = root.dataset.matchId;
  let player = "player_one";

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

  const fleet = (key) => ({ aurelian: "Aurelian Compact", veyr: "Veyr Dominion", kestrel: "Kestrel Freeholds" })[key];
  const enemy = () => state.ships.find((ship) => ship.player !== player && !ship.destroyed);
  const mine = () => state.ships.find((ship) => ship.player === player && !ship.destroyed);
  const shipCard = (ship) => `
    <article class="ship-card fleet-${ship.fleet} ${ship.destroyed ? "destroyed" : ""}">
      <div class="ship-silhouette"><span></span><span></span><span></span></div>
      <div><p class="eyebrow">${fleet(ship.fleet)} · ${ship.size}</p><h3>${ship.name}</h3>
      <dl><div><dt>Hull</dt><dd>${ship.hull}/${ship.max_hull}</dd></div><div><dt>Shields</dt><dd>F ${ship.shields.front} · A ${ship.shields.aft}</dd></div><div><dt>Energy</dt><dd>${ship.energy - ship.damage.engines}</dd></div></dl></div>
    </article>`;
  const hex = (ship) => {
    const [q, r, facing] = ship.position; const x = 390 + (q * 47) + (r * 24); const y = 255 + r * 42;
    return `<g class="token fleet-${ship.fleet} ${ship.destroyed ? "destroyed" : ""}" transform="translate(${x} ${y}) rotate(${facing * 60})"><path d="M0 -21 L18 -7 L12 16 L-12 16 L-18 -7 Z"/><circle cx="0" cy="0" r="6"/><text y="4">${ship.size[0].toUpperCase()}</text></g>`;
  };
  const controls = (ship, target) => {
    if (state.winner) return `<a class="button" href="/">Return to fleet selection</a>`;
    if (state.phase === "allocation") return `<div class="control-stack"><label>Speed <output id="speed-value">${ship.allocation.speed}</output><input id="speed" type="range" min="0" max="12" value="${ship.allocation.speed}"></label><label>Shield reinforcement <output id="shields-value">${ship.allocation.shields}</output><input id="shields" type="range" min="0" max="${ship.size === "small" ? 1 : ship.size === "medium" ? 2 : 3}" value="${ship.allocation.shields}"></label><button class="primary save-allocation">Set allocation</button><button class="secondary lock-allocation">Lock allocation</button></div>`;
    return `<div class="control-stack"><button class="primary advance">Draw next impulse</button>${target ? ship.weapons.filter((w) => !w.destroyed).map((w) => `<button class="secondary fire" data-weapon="${w.id}">Fire ${w.type === "beam" ? "Lance beam" : w.type === "driver" ? "Mass driver" : "Seeker missile"} at ${target.name}</button>`).join("") : ""}${ship.special_available ? `<button class="secondary special">Emergency power maneuver</button>` : ""}</div>`;
  };
  const bind = (ship, target) => {
    root.querySelector(".switch-player")?.addEventListener("click", () => { player = player === "player_one" ? "player_two" : "player_one"; render(); });
    root.querySelectorAll("input").forEach((input) => input.addEventListener("input", () => root.querySelector(`#${input.id}-value`).textContent = input.value));
    root.querySelector(".save-allocation")?.addEventListener("click", () => request("allocate", { ship_id: ship.id, speed: root.querySelector("#speed").value, shields: root.querySelector("#shields").value, weapons: ship.weapons.filter((w) => w.type !== "missile" && !w.destroyed).map((w) => w.id) }));
    root.querySelector(".lock-allocation")?.addEventListener("click", () => request("lock_allocation"));
    root.querySelector(".advance")?.addEventListener("click", () => request("advance_impulse"));
    root.querySelectorAll(".fire").forEach((button) => button.addEventListener("click", () => request("fire", { ship_id: ship.id, target_id: target.id, weapon_id: button.dataset.weapon })));
    root.querySelector(".special")?.addEventListener("click", () => request("special", { ship_id: ship.id, maneuver: "emergency_power" }));
  };
  const render = () => {
    const current = mine(); const target = enemy();
    root.innerHTML = `
      <header class="game-header"><a href="/" class="wordmark">THE <strong>SHATTERED</strong> REACH</a><div class="turn-state"><span>TURN ${state.turn}</span><b>${state.winner ? `${state.winner === "player_one" ? "Player One" : "Player Two"} wins` : state.phase === "allocation" ? "Secret allocation" : `Impulse ${state.impulse} · ${state.initiative === player ? "You hold initiative" : "Opponent holds initiative"}`}</b></div><button class="switch-player">Viewing: ${player === "player_one" ? "Player One" : "Player Two"}</button></header>
      <main class="match-layout"><section class="command-panel"><p class="eyebrow">${state.scenario === "tutorial" ? `Tutorial · ${["Set the battle plan", "Reveal allocations", "Watch an impulse", "Fire your first weapon"][state.tutorial_step] || "Continue the engagement"}` : "Fleet command"}</p><h1>${state.phase === "allocation" ? "Commit your energy" : "Command the engagement"}</h1><p class="quiet">${state.log.at(-1)}</p>${current ? controls(current, target) : ""}</section>
      <section class="battlefield"><div class="nebula"></div><svg viewBox="0 0 780 510" aria-label="Tactical hex battlefield"><defs><pattern id="hexes" width="72" height="84" patternUnits="userSpaceOnUse"><path d="M24 0L72 0L96 42L72 84L24 84L0 42Z" fill="none" stroke="rgba(180,207,255,.16)"/></pattern></defs><rect width="780" height="510" fill="url(#hexes)"/>${state.ships.map(hex).join("")}</svg><div class="battlefield-label">Tactical display · axial hex grid</div></section>
      <aside class="fleet-status"><h2>Fleet status</h2>${state.ships.map(shipCard).join("")}</aside></main>`;
    bind(current, target);
  };
  render();
}
