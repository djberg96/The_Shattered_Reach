import { fleetName, shipGlyph, shipHull, shipSchematic, weaponHint } from "ship_visuals";

const csrf = () => document.querySelector("meta[name='csrf-token']")?.content;

export function mountMatch(root) {
  let state = JSON.parse(root.dataset.matchState);
  const matchId = root.dataset.matchId;
  let player = "player_one";
  let activeShipId = state.ships.find((ship) => ship.player === player && !ship.destroyed)?.id || null;
  let zoom = 1;
  let selectedShipId = null;
  let damageReport = null;
  let selectedWeaponId = null;
  let impulseModalOpen = Boolean(state.impulse_card && state.activity_step === "movement");
  let soundEnabled = window.localStorage.getItem("shattered-reach-sound") !== "muted";
  let movementLinesVisible = window.localStorage.getItem("shattered-reach-movement-lines") !== "hidden";
  let fleetStatusCollapsed = window.localStorage.getItem("shattered-reach-fleet-status") === "collapsed";
  let gameMenuOpen = false;
  let gameConfirmation = null;
  let audioContext = null;
  let combatEffectPlaying = false;
  const combatEffectQueue = [];
  let lastCombatEventId = Math.max(0, ...(state.combat_events || []).map((event) => Number(event.id) || 0));
  const directions = [[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]];

  const request = async (action, payload = {}) => {
    ensureAudio();
    const response = await fetch(`/matches/${matchId}/action`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf(), "Accept": "application/json" },
      body: JSON.stringify({ player, command: action, payload })
    });
    const result = await response.json();
    if (!response.ok) { window.alert(result.error); return false; }
    const newCombatEvents = (result.combat_events || []).filter((event) => Number(event.id) > lastCombatEventId);
    if (newCombatEvents.length) lastCombatEventId = Math.max(...newCombatEvents.map((event) => Number(event.id)));
    state = result;
    if (action === "fire") selectedWeaponId = null;
    if (action === "advance_impulse") impulseModalOpen = true;
    render();
    enqueueCombatEffects(newCombatEvents);
    return true;
  };

  const enemies = () => state.ships.filter((ship) => ship.player !== player && !ship.destroyed);
  const enemy = () => enemies()[0];
  const mine = () => {
    const moving = state.ships.find((ship) => ship.id === state.pending_movement?.[0] && ship.player === player && !ship.destroyed);
    return moving || state.ships.find((ship) => ship.id === activeShipId && ship.player === player && !ship.destroyed) || state.ships.find((ship) => ship.player === player && !ship.destroyed);
  };
  const targetOwner = (target) => target.player || target.owner;
  const targetName = (target) => target.name || "Seeker missile";
  const findTarget = (targetId) => state.ships.find((entry) => entry.id === targetId) || (state.missiles || []).find((entry) => entry.id === targetId);
  const targetStatus = (target) => {
    const attacker = mine(); const weapon = attacker?.weapons.find((entry) => entry.id === selectedWeaponId);
    if (!weapon || state.activity_step !== "fire" || targetOwner(target) === player || target.destroyed) return null;
    return directWeaponLegal(attacker, target, weapon) ? "legal" : "illegal";
  };
  const shipCard = (ship) => { const target = targetStatus(ship); const relationship = state.solo ? ship.player === player ? "Your ship" : "AI opponent" : ship.player === "player_one" ? "Player One" : "Player Two"; const concealed = state.phase === "allocation" && ship.player !== player; return `
    <article class="ship-card fleet-${ship.fleet} ${ship.destroyed ? "destroyed" : ""} ${target ? `target-candidate ${target}` : `selectable ${ship.player !== player ? "opponent-schematic" : ""}`}" data-ship-hover-id="${ship.id}" ${target ? `data-target-id="${ship.id}" role="button" tabindex="0" aria-label="${ship.name}, ${target} target"` : `data-ship-id="${ship.id}" role="button" tabindex="0" aria-label="Open ${ship.name} schematic${concealed ? "; allocation concealed" : ""}"`}>
      <div class="ship-card-icon">${shipGlyph(ship, "ship-glyph-card")}</div>
      <div><p class="eyebrow">${relationship} · Ship ${ship.fleet_index || 1} · ${fleetName(ship.fleet)} · ${ship.size}</p><h3>${ship.name}</h3>
      <dl><div><dt>Hull</dt><dd>${ship.hull}/${ship.max_hull}</dd></div><div><dt>Shields</dt><dd>F ${ship.shields.front} · A ${ship.shields.aft}</dd></div><div><dt>Energy</dt><dd>${ship.energy - ship.damage.engines}</dd></div></dl><span class="schematic-cue">${target ? target === "legal" ? "Legal target · inspect or fire" : "Inspect firing solution" : concealed ? "Open schematic · allocation concealed ↗" : "Open schematic ↗"}</span></div>
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
  const ensureAudio = () => {
    if (!soundEnabled) return null;
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    if (!AudioContext) return null;
    audioContext ||= new AudioContext();
    if (audioContext.state === "suspended") audioContext.resume();
    return audioContext;
  };
  const tone = (context, { start, duration, frequency, endFrequency, type = "sine", volume = .08, delay = 0 }) => {
    const oscillator = context.createOscillator(); const gain = context.createGain();
    oscillator.type = type;
    oscillator.frequency.setValueAtTime(frequency, start + delay);
    oscillator.frequency.exponentialRampToValueAtTime(Math.max(20, endFrequency || frequency), start + delay + duration);
    gain.gain.setValueAtTime(.0001, start + delay);
    gain.gain.exponentialRampToValueAtTime(volume, start + delay + .015);
    gain.gain.exponentialRampToValueAtTime(.0001, start + delay + duration);
    oscillator.connect(gain).connect(context.destination);
    oscillator.start(start + delay); oscillator.stop(start + delay + duration + .02);
  };
  const noise = (context, { start, duration, volume = .08, delay = 0, frequency = 800 }) => {
    const samples = Math.ceil(context.sampleRate * duration); const buffer = context.createBuffer(1, samples, context.sampleRate);
    const data = buffer.getChannelData(0);
    for (let index = 0; index < samples; index += 1) data[index] = (Math.random() * 2 - 1) * (1 - (index / samples));
    const source = context.createBufferSource(); const filter = context.createBiquadFilter(); const gain = context.createGain();
    source.buffer = buffer; filter.type = "lowpass"; filter.frequency.value = frequency; gain.gain.value = volume;
    source.connect(filter).connect(gain).connect(context.destination); source.start(start + delay);
  };
  const playWeaponSound = (event) => {
    const context = ensureAudio(); if (!context) return;
    const now = context.currentTime;
    const impactDelay = event.weapon_type === "beam" ? .24 : .48;
    if (event.weapon_type === "beam") {
      tone(context, { start: now, duration: .42, frequency: 1150, endFrequency: 180, type: "sawtooth", volume: .055 });
      tone(context, { start: now, duration: .34, frequency: 1700, endFrequency: 390, type: "sine", volume: .045, delay: .025 });
    } else {
      tone(context, { start: now, duration: .3, frequency: 145, endFrequency: 42, type: "square", volume: .09 });
      noise(context, { start: now, duration: .22, volume: .075, frequency: 520 });
    }
    if (event.hit) {
      noise(context, { start: now, duration: .38, volume: .1, delay: impactDelay, frequency: 1150 });
      tone(context, { start: now, duration: .38, frequency: 210, endFrequency: 48, type: "sine", volume: .12, delay: impactDelay });
      if (event.damage?.destroyed) {
        noise(context, { start: now, duration: 1.2, volume: .16, delay: impactDelay + .12, frequency: 720 });
        noise(context, { start: now, duration: .75, volume: .11, delay: impactDelay + .5, frequency: 240 });
        tone(context, { start: now, duration: 1.35, frequency: 150, endFrequency: 24, type: "sawtooth", volume: .14, delay: impactDelay + .12 });
        tone(context, { start: now, duration: .7, frequency: 72, endFrequency: 26, type: "square", volume: .1, delay: impactDelay + .48 });
      }
    } else {
      tone(context, { start: now, duration: .24, frequency: 360, endFrequency: 120, type: "sine", volume: .035, delay: event.weapon_type === "beam" ? .25 : .5 });
    }
  };
  const combatEffectMarkup = (event) => {
    const [startX, startY] = center(...event.origin); const [targetX, targetY] = center(...event.target_position);
    const dx = targetX - startX; const dy = targetY - startY; const length = Math.hypot(dx, dy) || 1;
    const missSide = Number(event.id) % 2 ? 1 : -1; const missOffset = Math.min(48, Math.max(35, length * .16));
    const endX = event.hit ? targetX : targetX + ((-dy / length) * missOffset * missSide);
    const endY = event.hit ? targetY : targetY + ((dx / length) * missOffset * missSide);
    const destroyed = Boolean(event.damage?.destroyed);
    const resultText = destroyed ? "DESTROYED" : event.hit ? `HIT · ${event.roll}` : `MISS · ${event.roll}`;
    const trajectory = event.weapon_type === "beam"
      ? `<line class="weapon-beam-halo" x1="${startX}" y1="${startY}" x2="${endX}" y2="${endY}"/><line class="weapon-beam-core" x1="${startX}" y1="${startY}" x2="${endX}" y2="${endY}"/>`
      : `<line class="driver-trajectory" x1="${startX}" y1="${startY}" x2="${endX}" y2="${endY}"/><circle class="driver-projectile" r="4"><animateMotion dur="520ms" path="M ${startX} ${startY} L ${endX} ${endY}" fill="freeze"/></circle>`;
    const destruction = destroyed ? `<g class="ship-explosion" transform="translate(${targetX} ${targetY})" aria-hidden="true"><circle class="explosion-glare" r="10"/><circle class="explosion-core" r="13"/><circle class="explosion-ring explosion-ring-one" r="15"/><circle class="explosion-ring explosion-ring-two" r="22"/><path class="explosion-rays" d="M0-58V-15M41-41L11-11M58 0H15M41 41L11 11M0 58V15M-41 41L-11 11M-58 0H-15M-41-41L-11-11"/><path class="explosion-debris" d="M-5-8L-27-48M7-5L48-27M8 5L39 47M-6 8L-41 39M-10 0L-55-12M9-1L54 15"/></g>` : "";
    return `<g class="combat-effect weapon-${event.weapon_type} result-${event.hit ? "hit" : "miss"} ${destroyed ? "result-destroyed" : ""}" aria-label="${event.weapon_label} ${destroyed ? "destroys" : event.hit ? "hits" : "misses"} ${event.target_name}, roll ${event.roll}">
      ${trajectory}
      <g class="muzzle-flash" transform="translate(${startX} ${startY})"><circle r="6"/><path d="M-13 0H13M0-13V13M-9-9L9 9M9-9L-9 9"/></g>
      <g class="impact-burst" transform="translate(${targetX} ${targetY})"><circle class="impact-ring" r="8"/><circle class="impact-core" r="5"/><path d="M-20 0H20M0-20V20M-14-14L14 14M14-14L-14 14"/></g>
      ${destruction}
      <g class="combat-result-marker" transform="translate(${targetX} ${targetY - 31})"><rect x="-31" y="-10" width="62" height="20" rx="2"/><text y="3">${resultText}</text></g>
    </g>`;
  };
  const playNextCombatEffect = () => {
    if (combatEffectPlaying || combatEffectQueue.length === 0) return;
    const event = combatEffectQueue.shift(); const svg = root.querySelector(".battlefield svg");
    if (!svg) return;
    combatEffectPlaying = true;
    svg.insertAdjacentHTML("beforeend", combatEffectMarkup(event));
    playWeaponSound(event);
    window.setTimeout(() => {
      root.querySelector(".combat-effect")?.remove();
      combatEffectPlaying = false;
      if (event.hit && event.target_type === "ship" && event.damage) {
        impulseModalOpen = false;
        damageReport = event;
        selectedShipId = event.target_id;
        render();
        root.querySelector(".schematic-close")?.focus();
      } else {
        playNextCombatEffect();
      }
    }, event.damage?.destroyed ? 2850 : 1650);
  };
  const enqueueCombatEffects = (events) => {
    combatEffectQueue.push(...events);
    playNextCombatEffect();
  };
  const grid = () => {
    const cells = [];
    for (let row = 0; row < boardSize; row += 1) for (let column = 0; column < boardSize; column += 1) {
      const q = column; const r = row - Math.floor(column / 2); const [x, y] = center(q, r);
      const reference = `${String(column + 1).padStart(2, "0")}${String(row + 1).padStart(2, "0")}`;
      cells.push(`<g class="hex-cell"><polygon points="${polygon(x, y)}"/><text class="hex-reference" x="${x}" y="${y - (hexHeight / 2) + 12}">${reference}</text></g>`);
    }
    return `<g class="hex-grid">${cells.join("")}</g>`;
  };
  const movementLines = () => {
    if (!movementLinesVisible) return "";
    return `<g class="movement-lines" aria-label="Ship movement paths this turn">${state.ships.map((ship) => {
      const path = Array.isArray(ship.movement_path) && ship.movement_path.length ? ship.movement_path : [ship.position.slice(0, 2)];
      const points = path.map((position) => center(...position).join(",")).join(" ");
      const [startX, startY] = center(...path[0]);
      const segments = path.length > 1 ? `<polyline points="${points}"/>${path.slice(1, -1).map((position) => { const [x, y] = center(...position); return `<circle class="movement-waypoint" cx="${x}" cy="${y}" r="3"/>`; }).join("")}` : "";
      return `<g class="movement-line fleet-${ship.fleet}" aria-label="${ship.name} movement path"><circle class="movement-origin-pulse" cx="${startX}" cy="${startY}" r="12"/><circle class="movement-origin" cx="${startX}" cy="${startY}" r="5"/>${segments}</g>`;
    }).join("")}</g>`;
  };
  const hex = (ship) => {
    const [q, r, facing] = ship.position; const [x, y] = center(q, r);
    const selectable = !state.solo || ship.player === player;
    const moving = state.pending_movement?.[0] === ship.id;
    const target = targetStatus(ship);
    return `<g class="ship-token fleet-${ship.fleet} ${ship.destroyed ? "destroyed" : ""} ${moving ? "movement-active" : ""} ${target ? `target-candidate ${target}` : selectable ? "selectable" : "ai-opponent"}" data-ship-hover-id="${ship.id}" ${target ? `data-target-id="${ship.id}" role="button" tabindex="0" aria-label="${ship.name}, ${target} target"` : selectable ? `data-ship-id="${ship.id}" role="button" tabindex="0" aria-label="Open ${ship.name} schematic"` : `aria-label="${ship.name}, AI-controlled opponent"`} transform="translate(${x} ${y}) rotate(${120 - (facing * 60)}) scale(.86)"><circle class="ship-hover-area" r="32"/>${shipHull(ship)}</g>`;
  };
  const missileCounter = (missile) => {
    const [q, r, facing] = missile.position; const [x, y] = center(q, r);
    const target = targetStatus(missile);
    const targetShip = state.ships.find((ship) => ship.id === missile.target_id);
    const label = `Seeker missile${targetShip ? ` targeting ${targetShip.name}` : ""}`;
    return `<g class="missile-counter fleet-${missile.fleet} ${target ? `target-candidate ${target}` : ""}" ${target ? `data-target-id="${missile.id}" role="button" tabindex="0" aria-label="${label}, ${target} target"` : `aria-label="${label}"`} transform="translate(${x} ${y}) rotate(${120 - (facing * 60)})">
      <circle class="missile-target-area" r="24"/><circle class="missile-pulse" r="16"/><path class="missile-wake" d="M-5 10 L0 22 L5 10"/>
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
  const firingSolution = (ship, target, weapon) => {
    const range = axialDistance(ship.position, target.position);
    const profile = weapon.type === "beam" ? { limits: [3, 6, 9], hit: [2, 3, 4], damage: [3, 2, 1] } : { limits: [4, 8, 12], hit: [3, 4, 5], damage: [2, 2, 2] };
    const bracket = profile.limits.findIndex((limit) => range <= limit);
    const inArc = targetInArc(ship, target, weapon.arc); const legal = bracket >= 0 && inArc;
    const problem = bracket < 0 ? "OUT OF RANGE" : !inArc ? "OUTSIDE FIRING ARC" : "LEGAL SHOT";
    const missileTarget = Boolean(target.owner);
    // Mirrors RulesEngine::MISSILE_TARGET_TO_HIT_PENALTY: firing at a missile
    // suffers -1 on the die, represented here by a target number one higher.
    const missilePenalty = 1;
    const hit = bracket >= 0 ? `${profile.hit[bracket] + (missileTarget ? missilePenalty : 0)}+` : undefined;
    return { range, bracket, inArc, legal, problem, band: ["Short", "Medium", "Long"][bracket], hit, damage: missileTarget ? "Destroy" : profile.damage[bracket], missileTarget };
  };
  const currentTurnMode = (ship) => {
    const speed = Number(ship.allocation.speed); const speedBand = speed <= 4 ? 0 : speed <= 8 ? 1 : 2;
    return ({ small: 0, medium: 1, large: 2 }[ship.size] || 0) + speedBand;
  };
  const motionReadout = (ship) => {
    const concealed = state.phase === "allocation" && ship.player !== player;
    return {
      concealed,
      speed: concealed ? "—" : Number(ship.allocation.speed),
      turnMode: concealed ? "—" : currentTurnMode(ship)
    };
  };
  const motionReadoutMarkup = (ship, compact = false) => {
    const motion = motionReadout(ship);
    return `<div class="ship-motion-readout ${compact ? "compact" : ""} ${motion.concealed ? "concealed" : ""}">
      <div><span>Current speed</span><b>${motion.speed}</b></div><div><span>Turn mode</span><b>${motion.turnMode}</b></div>
      ${motion.concealed ? `<small>Opponent allocation unannounced</small>` : ""}
    </div>`;
  };
  const shipHoverMarkup = (ship) => `<div class="ship-hover-heading"><span>${fleetName(ship.fleet)} · ${ship.size}</span><b>${ship.name}</b></div>${motionReadoutMarkup(ship)}`;
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
  const speedRelationship = (speed) => {
    const yours = state.ships.some((ship) => ship.player === player && !ship.destroyed && Number(ship.allocation.speed) === speed);
    const opponents = state.ships.some((ship) => ship.player !== player && !ship.destroyed && Number(ship.allocation.speed) === speed);
    if (yours && opponents) return { className: "both-speed", label: "Both ships" };
    if (yours) return { className: "your-speed", label: "Your ship" };
    if (opponents) return { className: "opponent-speed", label: "Opponent" };
    return { className: "", label: "" };
  };
  const speedTile = (speed) => {
    const relationship = speedRelationship(speed);
    return `<strong class="${relationship.className}" aria-label="Speed ${speed}${relationship.label ? `, ${relationship.label} moves` : ""}"><b>${speed}</b>${relationship.label ? `<small>${relationship.label}</small>` : ""}</strong>`;
  };
  const impulseModal = () => {
    if (!impulseModalOpen || !state.impulse_card) return "";
    return `<div class="impulse-modal-backdrop" role="presentation"><section class="impulse-modal" role="dialog" aria-modal="true" aria-labelledby="impulse-modal-title">
      <p class="eyebrow">Impulse ${state.impulse} · Original card #${state.impulse_card_number}</p>
      <h2 id="impulse-modal-title">Phase ${state.impulse_phase}<br><span>Movement</span></h2>
      <p class="impulse-modal-label">Speeds that move</p>
      <div class="impulse-speeds speed-count-${state.impulse_card.length}">${state.impulse_card.map(speedTile).join("")}</div>
      <button class="primary dismiss-impulse">${state.activity_step === "movement" ? "Continue to movement" : "Continue to missile launch"}</button>
    </section></div>`;
  };
  const gameConfirmationModal = () => {
    if (!gameConfirmation) return "";
    const resetting = gameConfirmation === "reset";
    return `<div class="game-confirmation-backdrop" role="presentation"><section class="game-confirmation" role="dialog" aria-modal="true" aria-labelledby="game-confirmation-title" aria-describedby="game-confirmation-description">
      <p class="eyebrow">${resetting ? "Reset battle" : "Exit battle"}</p>
      <h2 id="game-confirmation-title">Are you sure?</h2>
      <p id="game-confirmation-description">${resetting ? "This returns every ship to its starting position and discards all progress in this battle." : "Any progress since your last downloaded save will remain only in this browser's local battle archive."}</p>
      <div class="game-confirmation-actions"><button class="secondary cancel-game-action">Cancel</button><button class="${resetting ? "danger" : "primary"} confirm-game-action">${resetting ? "Reset battle" : "Exit to title"}</button></div>
    </section></div>`;
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
  const commandShipPicker = (current) => {
    const ships = state.ships.filter((ship) => ship.player === player && !ship.destroyed);
    if (ships.length < 2) return "";
    return `<nav class="command-ship-picker" aria-label="Choose ship to command">${ships.map((ship) => `<button class="${ship.id === current?.id ? "active" : ""}" data-command-ship-id="${ship.id}"><span>Ship ${ship.fleet_index || 1}</span><b>${ship.name}</b><small>${state.phase === "allocation" ? ship.locked ? `Speed ${ship.allocation.speed} · locked` : ship.allocation_set ? `Speed ${ship.allocation.speed} · saved` : "Not allocated" : `Speed ${ship.allocation.speed}`}</small></button>`).join("")}</nav>`;
  };
  const controls = (ship, target) => {
    const undoMovement = state.movement_undo?.player === player ? `<button class="secondary undo-movement">Undo last movement</button>` : "";
    if (state.winner) return `<div class="control-stack">${undoMovement}<a class="button" href="/">Return to fleet selection</a></div>`;
    if (state.phase === "allocation") {
      const shieldCap = ship.size === "small" ? 1 : ship.size === "medium" ? 2 : 3;
      const frontDamaged = ship.shields.front < ship.max_front_shields;
      const aftDamaged = ship.shields.aft < ship.max_aft_shields;
      const fleetCount = state.ships.filter((entry) => entry.player === player && !entry.destroyed).length;
      return `<div class="control-stack"><label>Speed <output id="speed-value">${ship.allocation.speed}</output><input id="speed" type="range" min="0" max="12" value="${ship.allocation.speed}"></label><fieldset class="shield-allocation-list"><legend>Shield reinforcement</legend><label>Forward <output id="front-shields-value">${ship.allocation.shields.front}</output><input id="front-shields" type="range" min="0" max="${ship.shields.front > 0 ? shieldCap : 0}" value="${ship.allocation.shields.front}"></label><label>Aft <output id="aft-shields-value">${ship.allocation.shields.aft}</output><input id="aft-shields" type="range" min="0" max="${ship.shields.aft > 0 ? shieldCap : 0}" value="${ship.allocation.shields.aft}"></label></fieldset><fieldset class="shield-repair-list"><legend>Shield repair · 2 energy</legend><label>Restore at end of turn<select id="shield-repair"><option value="">No repair</option><option value="front" ${ship.allocation.shield_repair === "front" ? "selected" : ""} ${frontDamaged ? "" : "disabled"}>Forward · ${ship.shields.front}/${ship.max_front_shields}</option><option value="aft" ${ship.allocation.shield_repair === "aft" ? "selected" : ""} ${aftDamaged ? "" : "disabled"}>Aft · ${ship.shields.aft}/${ship.max_aft_shields}</option></select></label></fieldset><fieldset class="weapon-allocation-list"><legend>Weapon circuits</legend>${weaponChoices(ship)}</fieldset><div class="allocation-budget"><span>Energy committed</span><b><output id="energy-used">0</output> / ${ship.energy - ship.damage.engines}</b></div><button class="secondary save-allocation allocation-tip" aria-describedby="save-allocation-tip">Save draft<span id="save-allocation-tip" role="tooltip">Store this plan and keep it editable.</span></button><button class="primary commit-allocation allocation-tip" aria-describedby="commit-allocation-tip">${fleetCount > 1 ? "Confirm ship" : "Commit allocation"}<span id="commit-allocation-tip" role="tooltip">${fleetCount > 1 ? "Confirm this ship, then continue to any fleet ships still awaiting orders. The final ship commits the fleet." : `Save this plan and make it final for the turn${state.solo ? "; the AI then commits its own plan" : ""}.`}</span></button></div>`;
    }
    if (state.activity_step === "draw") return `<div class="control-stack">${activityStrip()}<p class="step-help">Draw the next card to discover which speeds receive a movement opportunity.</p><button class="primary advance">${state.impulse === 0 ? "Draw first impulse" : state.impulse === 11 ? "Draw the last impulse" : "Draw next impulse"}</button></div>`;
    if (state.activity_step === "movement") {
      const movingShip = state.ships.find((entry) => entry.id === state.pending_movement?.[0]);
      if (!movingShip || movingShip.player !== player) return `<div class="control-stack">${activityStrip()}<p class="step-callout"><b>${movingShip?.name || "Another ship"}</b> moves next.</p><p class="step-help">${state.solo ? "Command AI is resolving its maneuver." : "Pass command and use the player switch above."}</p>${undoMovement}</div>`;
      const labels = { forward: "Move forward", sideslip_left: "Side-slip port", sideslip_right: "Side-slip starboard", turn_left: "Turn 60° port", turn_right: "Turn 60° starboard", lose_movement: "Lose blocked movement" };
      const options = (state.movement_options || []).map((maneuver) => `<button class="${maneuver === "forward" ? "primary" : "secondary"} move-ship" data-maneuver="${maneuver}">${labels[maneuver]}</button>`).join("");
      const special = movingShip.special_available ? `<details class="special-maneuvers"><summary>Use one-time special maneuver</summary><button class="secondary special" data-special="emergency_power">Emergency power · extra forward move</button><button class="secondary special" data-special="quick_stop">Quick stop · speed zero</button><label>Bootlegger heading<select id="bootlegger-facing">${["East", "Northeast", "Northwest", "West", "Southwest", "Southeast"].map((label, direction) => `<option value="${direction}" ${movingShip.position[2] === direction ? "selected" : ""}>${label}</option>`).join("")}</select></label><button class="secondary bootlegger">Bootlegger · rotate freely</button></details>` : "";
      return `<div class="control-stack">${activityStrip()}<p class="step-callout"><b>${movingShip.name}</b> has a movement opportunity.</p><p class="step-help">Choose one highlighted destination or turn in place. Turn mode ${currentTurnMode(movingShip)}: ${movingShip.movement?.hexes_since_turn || 0} forward hexes accumulated.</p><div class="impulse-card"><span>Movement card</span><b>${(state.impulse_card || []).map((speed) => { const relationship = speedRelationship(speed); return `<i class="${relationship.className}">${speed}</i>`; }).join("<em>·</em>")}</b></div>${options}${special}${undoMovement}</div>`;
    }
    if (state.activity_step === "launch") {
      const launchers = ship.weapons.filter((weapon) => weapon.type === "missile" && !weapon.destroyed && !weapon.fired && weapon.ammo > 0);
      const launches = launchers.flatMap((weapon) => enemies().map((candidate) => `<button class="secondary launch-missile" data-weapon="${weapon.id}" data-target="${candidate.id}">Launch ${weapon.mount || "M"} seeker missile at ${candidate.name} · ${weapon.ammo} remaining</button>`)).join("");
      return `<div class="control-stack">${activityStrip()}<p class="step-help">Existing missiles have moved. Launch any new missiles now; they remain in your hex until the next impulse.</p>${launches}${undoMovement}<button class="primary finish-launches">${launchers.length ? "Finish missile launches" : "Continue to weapons fire"}</button></div>`;
    }
    const poweredWeapons = ship.weapons.filter((weapon) => weapon.type !== "missile" && !weapon.destroyed && !weapon.fired && ship.allocation.weapons.includes(weapon.id));
    const selectedWeapon = poweredWeapons.find((weapon) => weapon.id === selectedWeaponId);
    return `<div class="control-stack">${activityStrip()}<p class="step-help">${selectedWeapon ? `Now hover over an enemy ship or missile to inspect the shot, then click a legal target to fire ${selectedWeapon.mount || weaponName(selectedWeapon)}.` : "Select a powered weapon, then choose an enemy ship or missile on the battlefield."}</p>${poweredWeapons.map((weapon) => `<button class="secondary select-weapon ${weapon.id === selectedWeaponId ? "selected" : ""}" data-weapon="${weapon.id}">${weapon.id === selectedWeaponId ? "Selected" : "Select"} ${weapon.mount ? `${weapon.mount} ` : ""}${weaponName(weapon)} · Arc ${weapon.arc.join("/")}<small>${weapon.id === selectedWeaponId ? "Choose an enemy ship or missile" : `${weaponEnergy(weapon)} energy · unfired`}</small></button>`).join("")}${poweredWeapons.length ? "" : `<p class="no-legal-action">No unfired direct weapon is powered this turn.</p>`}${selectedWeapon ? `<button class="secondary cancel-weapon">Cancel target selection</button>` : ""}<button class="primary finish-impulse">${state.impulse >= 12 ? "End turn" : "End impulse"}</button></div>`;
  };
  const bind = (ship, target) => {
    root.querySelector(".game-menu-toggle")?.addEventListener("click", () => { gameMenuOpen = !gameMenuOpen; render(); root.querySelector(gameMenuOpen ? ".game-menu-item" : ".game-menu-toggle")?.focus(); });
    root.querySelector(".reset-game")?.addEventListener("click", () => { gameMenuOpen = false; gameConfirmation = "reset"; render(); root.querySelector(".cancel-game-action")?.focus(); });
    root.querySelector(".exit-game")?.addEventListener("click", () => { gameMenuOpen = false; gameConfirmation = "exit"; render(); root.querySelector(".cancel-game-action")?.focus(); });
    root.querySelector(".cancel-game-action")?.addEventListener("click", () => { gameConfirmation = null; render(); root.querySelector(".game-menu-toggle")?.focus(); });
    root.querySelector(".game-confirmation-backdrop")?.addEventListener("click", (event) => { if (event.target === event.currentTarget) { gameConfirmation = null; render(); } });
    root.querySelector(".confirm-game-action")?.addEventListener("click", async () => {
      if (gameConfirmation === "exit") { window.location.assign("/"); return; }
      const response = await fetch(`/matches/${matchId}/reset`, { method: "POST", headers: { "X-CSRF-Token": csrf(), "Accept": "application/json" } });
      if (!response.ok) { window.alert("The battle could not be reset."); return; }
      window.location.assign(`/matches/${matchId}`);
    });
    const allocationPayload = () => ({ ship_id: ship.id, speed: root.querySelector("#speed").value, front_shields: root.querySelector("#front-shields").value, aft_shields: root.querySelector("#aft-shields").value, shield_repair: root.querySelector("#shield-repair").value, weapons: [...root.querySelectorAll(".weapon-allocation input:checked")].map((input) => input.value) });
    const saveCurrentAllocation = async () => {
      if (state.phase !== "allocation" || !ship || ship.locked) return true;
      return request("allocate", allocationPayload());
    };
    root.querySelector(".switch-player")?.addEventListener("click", async () => {
      if (state.solo || !await saveCurrentAllocation()) return;
      player = player === "player_one" ? "player_two" : "player_one";
      activeShipId = state.ships.find((entry) => entry.player === player && !entry.destroyed)?.id || null;
      selectedWeaponId = null;
      render();
    });
    root.querySelectorAll("[data-command-ship-id]").forEach((button) => button.addEventListener("click", async () => {
      if (button.dataset.commandShipId === ship?.id || !await saveCurrentAllocation()) return;
      activeShipId = button.dataset.commandShipId;
      selectedWeaponId = null;
      render();
    }));
    root.querySelector(".fleet-status-toggle")?.addEventListener("click", () => {
      fleetStatusCollapsed = !fleetStatusCollapsed;
      window.localStorage.setItem("shattered-reach-fleet-status", fleetStatusCollapsed ? "collapsed" : "expanded");
      render();
      root.querySelector(".fleet-status-toggle")?.focus();
    });
    root.querySelector(".zoom-out")?.addEventListener("click", () => { zoom = Math.max(.75, zoom - .25); render(); });
    root.querySelector(".zoom-reset")?.addEventListener("click", () => { zoom = 1; render(); });
    root.querySelector(".zoom-in")?.addEventListener("click", () => { zoom = Math.min(1.75, zoom + .25); render(); });
    root.querySelector(".sound-toggle")?.addEventListener("click", () => {
      soundEnabled = !soundEnabled;
      window.localStorage.setItem("shattered-reach-sound", soundEnabled ? "enabled" : "muted");
      if (soundEnabled) ensureAudio();
      render();
    });
    root.querySelector(".movement-lines-toggle")?.addEventListener("click", () => {
      movementLinesVisible = !movementLinesVisible;
      window.localStorage.setItem("shattered-reach-movement-lines", movementLinesVisible ? "visible" : "hidden");
      render();
    });
    const updateEnergyBudget = () => {
      const speed = Number(root.querySelector("#speed")?.value || 0);
      const shields = Number(root.querySelector("#front-shields")?.value || 0) + Number(root.querySelector("#aft-shields")?.value || 0);
      const shieldRepair = root.querySelector("#shield-repair")?.value ? 2 : 0;
      const weapons = [...root.querySelectorAll(".weapon-allocation input:checked")].reduce((sum, input) => sum + Number(input.dataset.energy), 0);
      const used = speed + shields + shieldRepair + weapons;
      const budget = root.querySelector(".allocation-budget");
      if (budget) budget.classList.toggle("over", used > ship.energy - ship.damage.engines);
      const output = root.querySelector("#energy-used");
      if (output) output.textContent = used;
    };
    root.querySelectorAll('input[type="range"]').forEach((input) => input.addEventListener("input", () => { root.querySelector(`#${input.id}-value`).textContent = input.value; updateEnergyBudget(); }));
    root.querySelectorAll(".weapon-allocation input").forEach((input) => input.addEventListener("change", updateEnergyBudget));
    root.querySelector("#shield-repair")?.addEventListener("change", updateEnergyBudget);
    updateEnergyBudget();
    root.querySelector(".save-allocation")?.addEventListener("click", () => request("allocate", allocationPayload()));
    root.querySelector(".commit-allocation")?.addEventListener("click", async () => {
      if (!await request("allocate", allocationPayload())) return;
      const nextShip = state.ships.find((entry) => entry.player === player && !entry.destroyed && !entry.allocation_set);
      if (nextShip) { activeShipId = nextShip.id; render(); } else { await request("lock_allocation"); }
    });
    root.querySelector(".advance")?.addEventListener("click", () => request("advance_impulse"));
    root.querySelector(".dismiss-impulse")?.addEventListener("click", () => { impulseModalOpen = false; render(); });
    root.querySelectorAll(".move-ship, .movement-choice").forEach((button) => button.addEventListener("click", () => request("move_ship", { ship_id: state.pending_movement[0], maneuver: button.dataset.maneuver })));
    root.querySelector(".undo-movement")?.addEventListener("click", () => request("undo_movement"));
    root.querySelectorAll(".movement-choice").forEach((button) => button.addEventListener("keydown", (event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); request("move_ship", { ship_id: state.pending_movement[0], maneuver: button.dataset.maneuver }); } }));
    root.querySelectorAll(".launch-missile").forEach((button) => button.addEventListener("click", () => request("launch_missile", { ship_id: ship.id, target_id: button.dataset.target, weapon_id: button.dataset.weapon })));
    root.querySelector(".finish-launches")?.addEventListener("click", () => request("finish_launches"));
    root.querySelectorAll(".select-weapon").forEach((button) => button.addEventListener("click", () => { selectedWeaponId = button.dataset.weapon; render(); }));
    root.querySelector(".cancel-weapon")?.addEventListener("click", () => { selectedWeaponId = null; render(); });
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
    const closeSchematic = () => {
      const resumeCombatEffects = Boolean(damageReport);
      selectedShipId = null;
      damageReport = null;
      render();
      if (resumeCombatEffects) playNextCombatEffect();
    };
    root.querySelector(".schematic-close")?.addEventListener("click", closeSchematic);
    root.querySelector(".schematic-backdrop")?.addEventListener("click", (event) => {
      if (event.target === event.currentTarget) closeSchematic();
    });
    root.querySelector(".impulse-modal-backdrop")?.addEventListener("click", (event) => { if (event.target === event.currentTarget) { impulseModalOpen = false; render(); } });
    root.querySelector(".ship-schematic")?.addEventListener("keydown", (event) => {
      if (event.key === "Escape") closeSchematic();
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
    const hint = root.querySelector(".weapon-hover-hint");
    const positionWeaponHint = (event, weaponControl) => {
      if (!hint) return;
      const rect = weaponControl.getBoundingClientRect();
      const pointerX = Number.isFinite(event?.clientX) && event.clientX > 0 ? event.clientX : rect.right;
      const pointerY = Number.isFinite(event?.clientY) && event.clientY > 0 ? event.clientY : rect.top + (rect.height / 2);
      const hintWidth = hint.offsetWidth || 260; const hintHeight = hint.offsetHeight || 170; const gap = 14;
      const left = pointerX + gap + hintWidth < window.innerWidth ? pointerX + gap : pointerX - hintWidth - gap;
      const top = Math.min(Math.max(gap, pointerY - 22), window.innerHeight - hintHeight - gap);
      hint.style.left = `${Math.max(gap, left)}px`; hint.style.top = `${top}px`;
    };
    const positionShipHint = (shipControl) => {
      if (!hint) return;
      const rect = shipControl.getBoundingClientRect();
      const hintWidth = hint.offsetWidth || 260; const hintHeight = hint.offsetHeight || 150;
      const viewportGap = 14; const shipGap = 34;
      const roomOnRight = rect.right + shipGap + hintWidth <= window.innerWidth - viewportGap;
      const left = roomOnRight ? rect.right + shipGap : rect.left - hintWidth - shipGap;
      const centeredTop = rect.top + (rect.height / 2) - (hintHeight / 2);
      const top = Math.min(Math.max(viewportGap, centeredTop), window.innerHeight - hintHeight - viewportGap);
      hint.style.left = `${Math.max(viewportGap, left)}px`; hint.style.top = `${top}px`;
    };
    const showTargetHint = (event, targetControl) => {
      const weapon = ship?.weapons.find((entry) => entry.id === selectedWeaponId);
      const candidate = findTarget(targetControl.dataset.targetId);
      if (!hint || !weapon || !candidate) return;
      const solution = firingSolution(ship, candidate, weapon);
      const targetMotion = candidate.name ? motionReadoutMarkup(candidate, true) : "";
      hint.className = `weapon-hover-hint fleet-${ship.fleet}`;
      hint.innerHTML = `${weaponHint(weapon)}<div class="target-firing-solution ${solution.legal ? "legal" : "illegal"}"><header><span>${solution.missileTarget ? "Intercept · −1 die" : "Target"}</span><b>${targetName(candidate)}</b></header>${targetMotion}<div><span>Range</span><b>${solution.range}</b><span>Band</span><b>${solution.band || "—"}</b><span>To hit</span><b>${solution.hit || "—"}</b><span>${solution.missileTarget ? "On hit" : "Damage"}</span><b>${solution.damage || "—"}</b></div><strong>${solution.problem}</strong></div>`;
      hint.classList.add("visible"); hint.setAttribute("aria-hidden", "false");
      positionWeaponHint(event, targetControl);
    };
    const showShipHint = (event, shipControl) => {
      const candidate = state.ships.find((entry) => entry.id === shipControl.dataset.shipHoverId);
      if (!hint || !candidate) return;
      hint.className = `weapon-hover-hint ship-motion-hint fleet-${candidate.fleet} visible`;
      hint.innerHTML = shipHoverMarkup(candidate);
      hint.setAttribute("aria-hidden", "false");
      positionShipHint(shipControl);
    };
    const hideWeaponHint = () => { hint?.classList.remove("visible"); hint?.setAttribute("aria-hidden", "true"); };
    root.querySelectorAll(".weapon-module, .weapon-hardpoint").forEach((weaponControl) => {
      weaponControl.addEventListener("mouseenter", () => displayWeaponArcs(weaponControl));
      weaponControl.addEventListener("focus", () => displayWeaponArcs(weaponControl));
      weaponControl.addEventListener("click", () => displayWeaponArcs(weaponControl));
    });
    root.querySelectorAll("[data-target-id]").forEach((targetControl) => {
      targetControl.setAttribute("aria-describedby", "weapon-hover-hint");
      targetControl.addEventListener("mouseenter", (event) => showTargetHint(event, targetControl));
      targetControl.addEventListener("mousemove", (event) => positionWeaponHint(event, targetControl));
      targetControl.addEventListener("mouseleave", hideWeaponHint);
      targetControl.addEventListener("focus", (event) => showTargetHint(event, targetControl));
      targetControl.addEventListener("blur", hideWeaponHint);
      targetControl.addEventListener("click", () => {
        const candidate = findTarget(targetControl.dataset.targetId);
        const weapon = ship?.weapons.find((entry) => entry.id === selectedWeaponId);
        if (candidate && weapon && directWeaponLegal(ship, candidate, weapon)) request("fire", { ship_id: ship.id, target_id: candidate.id, weapon_id: weapon.id });
      });
      targetControl.addEventListener("keydown", (event) => { if ((event.key === "Enter" || event.key === " ") && targetControl.classList.contains("legal")) { event.preventDefault(); targetControl.click(); } });
    });
    root.querySelectorAll("[data-ship-hover-id]:not([data-target-id])").forEach((shipControl) => {
      shipControl.setAttribute("aria-describedby", "weapon-hover-hint");
      shipControl.addEventListener("mouseenter", (event) => showShipHint(event, shipControl));
      shipControl.addEventListener("mousemove", () => positionShipHint(shipControl));
      shipControl.addEventListener("mouseleave", hideWeaponHint);
      shipControl.addEventListener("focus", (event) => showShipHint(event, shipControl));
      shipControl.addEventListener("blur", hideWeaponHint);
    });
  };
  const render = () => {
    const current = mine(); const target = enemy();
    if (current) activeShipId = current.id;
    const selectedShip = state.ships.find((ship) => ship.id === selectedShipId);
    const identity = state.solo ? `<div class="solo-identity"><span>You command</span><b>${state.ships.filter((ship) => ship.player === player && !ship.destroyed).length} ship fleet</b></div>` : `<button class="switch-player">Viewing: ${player === "player_one" ? "Player One" : "Player Two"}</button>`;
    const activityLabel = { draw: "Awaiting movement card", movement: "Movement phase", launch: "Missile launch phase", fire: "Direct fire phase" }[state.activity_step];
    const commandTitle = state.phase === "allocation" ? "Allocate Energy" : state.activity_step === "draw" && state.impulse === 11 ? "Draw the last impulse" : { draw: "Draw the next impulse", movement: "Choose your maneuver", launch: "Launch missiles", fire: "Resolve weapons fire" }[state.activity_step] || "Command the engagement";
    const commandLog = state.phase === "allocation" ? "" : `<p class="quiet">${state.log.at(-1)}</p>`;
    root.innerHTML = `
      <header class="game-header"><a href="/" class="wordmark">THE <strong>SHATTERED</strong> REACH</a><div class="turn-state"><span>TURN ${state.turn}${state.phase === "impulse" ? ` · IMPULSE ${state.impulse}` : ""}</span><b>${state.winner ? `${state.winner === "player_one" ? "Player One" : "Player Two"} wins` : state.phase === "allocation" ? "Secret allocation" : activityLabel}</b></div><div class="game-header-actions">${identity}<div class="game-menu"><button class="game-menu-toggle" aria-haspopup="menu" aria-expanded="${gameMenuOpen}">Game <span aria-hidden="true">▾</span></button>${gameMenuOpen ? `<div class="game-menu-list" role="menu"><a class="game-menu-item" role="menuitem" href="/matches/${matchId}/download" download>Save</a><button class="game-menu-item reset-game" role="menuitem">Reset</button><button class="game-menu-item exit-game" role="menuitem">Exit</button></div>` : ""}</div></div></header>
      <main class="match-layout phase-${state.phase} ${fleetStatusCollapsed ? "fleet-status-collapsed" : ""}"><section class="command-panel"><p class="eyebrow">${state.solo ? `Solo command · Active ship ${current?.fleet_index || 1}` : state.scenario === "tutorial" ? `Tutorial · ${["Set the battle plan", "Reveal allocations", "Choose a maneuver", "Fire your first weapon"][state.tutorial_step] || "Continue the engagement"}` : "Fleet command"}</p><h1 class="${state.phase === "allocation" ? "allocation-title" : ""}">${commandTitle}</h1>${commandLog}${commandShipPicker(current)}${current ? controls(current, target) : ""}</section>
      <section class="battlefield"><div class="nebula"></div><div class="zoom-controls" aria-label="Battlefield controls"><button class="movement-lines-toggle" aria-label="${movementLinesVisible ? "Hide" : "Show"} movement paths" aria-pressed="${movementLinesVisible}">${movementLinesVisible ? "TRAILS ON" : "TRAILS OFF"}</button><button class="sound-toggle" aria-label="${soundEnabled ? "Mute" : "Enable"} weapon sounds" aria-pressed="${soundEnabled}">${soundEnabled ? "SOUND ON" : "MUTED"}</button><button class="zoom-out" aria-label="Zoom out">−</button><button class="zoom-reset" aria-label="Reset zoom">${Math.round(zoom * 100)}%</button><button class="zoom-in" aria-label="Zoom in">+</button></div><svg viewBox="0 0 ${boardWidth} ${boardHeight}" aria-label="${boardSize} by ${boardSize} tactical flat-top hex battlefield" style="width:${zoom * 100}%;max-width:none">${grid()}${movementLines()}${movementChoices()}${state.ships.map(hex).join("")}${(state.missiles || []).map(missileCounter).join("")}</svg><div class="battlefield-label">Tactical display · ${boardSize} × ${boardSize} · numbered flat-top hex grid</div></section>
      <aside class="fleet-status ${fleetStatusCollapsed ? "collapsed" : ""}"><div class="fleet-status-header"><h2>Fleet status</h2><button class="fleet-status-toggle" aria-expanded="${!fleetStatusCollapsed}" aria-label="${fleetStatusCollapsed ? "Expand" : "Collapse"} fleet status"><span class="fleet-status-toggle-icon" aria-hidden="true">${fleetStatusCollapsed ? "‹" : "›"}</span><span class="fleet-status-toggle-label">Fleet status</span></button></div><div class="fleet-status-content"><p class="fleet-status-hint">Select any ship to inspect public damage. Enemy allocation remains concealed.</p>${state.ships.map(shipCard).join("")}</div></aside></main>${selectedShip ? shipSchematic(selectedShip, state, player, damageReport) : ""}${impulseModal()}${gameConfirmationModal()}<aside id="weapon-hover-hint" class="weapon-hover-hint fleet-${current?.fleet || "aurelian"}" role="tooltip" aria-hidden="true"></aside>`;
    bind(current, target);
  };
  render();
}
