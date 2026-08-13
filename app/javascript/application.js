import { mountMatch } from "match";
import { mountLanding } from "landing";

document.addEventListener("DOMContentLoaded", () => {
  const landing = document.querySelector("[data-landing]");
  if (landing) mountLanding(landing);

  const root = document.querySelector("[data-match-state]");
  if (root) mountMatch(root);
});
