const setPanelActive = (panel, active) => {
  panel.hidden = !active;
  panel.querySelectorAll("input, select, button").forEach((control) => {
    control.disabled = !active;
  });
};

export function mountLanding(root) {
  const dialogs = new Map(
    Array.from(root.querySelectorAll("dialog")).map((dialog) => [dialog.id, dialog])
  );
  const setupDialog = root.querySelector("[data-game-setup]");
  const setupSteps = Array.from(setupDialog?.querySelectorAll("[data-setup-step]") || []);
  const modeControls = Array.from(setupDialog?.querySelectorAll('input[name="mode"]') || []);
  const customDeployment = setupDialog?.querySelector("[data-custom-deployment]");
  const playerFleet = setupDialog?.querySelector("[data-player-fleet]");
  const hotseatOptions = setupDialog?.querySelector("[data-hotseat-options]");
  const aiOptions = setupDialog?.querySelector("[data-ai-options]");
  const tutorialOptions = setupDialog?.querySelector("[data-tutorial-options]");
  const stepNumber = setupDialog?.querySelector("[data-step-number]");
  const stepHeading = setupDialog?.querySelector("[data-step-heading]");
  const stepDescription = setupDialog?.querySelector("[data-step-description]");
  const submitButton = setupDialog?.querySelector("[data-begin-game]");

  const selectedMode = () => modeControls.find((control) => control.checked)?.value || "hotseat";

  const configureDeployment = () => {
    const mode = selectedMode();
    const tutorial = mode === "tutorial";
    setPanelActive(customDeployment, !tutorial);
    setPanelActive(playerFleet, !tutorial);
    setPanelActive(hotseatOptions, mode === "hotseat");
    setPanelActive(aiOptions, mode === "solo");
    setPanelActive(tutorialOptions, tutorial);

    if (mode === "solo") {
      stepHeading.textContent = "Assemble your fleet";
      stepDescription.textContent = "Choose up to three ships. Command AI opposition will be generated to match them.";
      submitButton.value = "Fight the command AI";
    } else if (tutorial) {
      stepHeading.textContent = "Review the training mission";
      stepDescription.textContent = "First Light uses a fixed deployment built for its scripted lessons.";
      submitButton.value = "Begin tutorial";
    } else {
      stepHeading.textContent = "Assemble both fleets";
      stepDescription.textContent = "Choose one to three ships for each hot-seat commander.";
      submitButton.value = "Begin skirmish";
    }
  };

  const showStep = (number) => {
    setupSteps.forEach((step) => {
      step.hidden = step.dataset.setupStep !== String(number);
    });
    stepNumber.textContent = String(number);

    if (number === 1) {
      stepHeading.textContent = "Choose your battle";
      stepDescription.textContent = "Select a command mode and the dimensions of the battlefield.";
    } else {
      configureDeployment();
    }
  };

  root.querySelectorAll("[data-open-dialog]").forEach((button) => {
    button.addEventListener("click", () => {
      const dialog = dialogs.get(button.dataset.openDialog);
      if (!dialog) return;
      if (dialog === setupDialog) showStep(1);
      dialog.showModal();
    });
  });

  root.querySelectorAll("[data-close-dialog]").forEach((button) => {
    button.addEventListener("click", () => button.closest("dialog")?.close());
  });

  dialogs.forEach((dialog) => {
    dialog.addEventListener("click", (event) => {
      if (event.target === dialog) dialog.close();
    });
  });

  setupDialog?.querySelector("[data-next-setup]")?.addEventListener("click", () => showStep(2));
  setupDialog?.querySelector("[data-previous-setup]")?.addEventListener("click", () => showStep(1));
  modeControls.forEach((control) => control.addEventListener("change", configureDeployment));
}
