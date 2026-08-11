import { mountMatch } from "match";

document.addEventListener("DOMContentLoaded", () => {
  const root = document.querySelector("[data-match-state]");
  if (root) mountMatch(root);
});
