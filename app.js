const moduleButtons = document.querySelectorAll("[data-module]");
const moduleBadge = document.querySelector("#moduleBadge");
const runButton = document.querySelector("#runButton");
const parameterForm = document.querySelector("#parameterForm");
const runTable = document.querySelector("#runTable");
const consoleOutput = document.querySelector("#consoleOutput");
const engineStatus = document.querySelector("#engineStatus");
const scenarioCount = document.querySelector("#scenarioCount");
const totalDuration = document.querySelector("#totalDuration");
const lastModule = document.querySelector("#lastModule");
const clearQueue = document.querySelector("#clearQueue");

let activeModule = "FDS";

function addConsoleLine(message) {
  const line = document.createElement("span");
  line.textContent = `> ${message}`;
  consoleOutput.appendChild(line);
  consoleOutput.scrollTop = consoleOutput.scrollHeight;
}

function updateMetrics() {
  const rows = Array.from(runTable.querySelectorAll("tr"));
  const total = rows.reduce((sum, row) => {
    const durationCell = row.cells[3]?.textContent || "0";
    return sum + Number.parseInt(durationCell, 10);
  }, 0);

  scenarioCount.textContent = String(rows.length);
  totalDuration.textContent = `${total || 0} s`;
  lastModule.textContent = rows[0]?.cells[1]?.textContent || "-";
}

moduleButtons.forEach((button) => {
  button.addEventListener("click", () => {
    moduleButtons.forEach((item) => item.classList.remove("active"));
    button.classList.add("active");
    activeModule = button.dataset.module.toUpperCase();
    moduleBadge.textContent = activeModule;
    addConsoleLine(`Modulo ${activeModule} selecionado.`);
  });
});

runButton.addEventListener("click", () => {
  const data = new FormData(parameterForm);
  const scenario = data.get("scenario") || "Cenario sem nome";
  const duration = data.get("duration") || "0";
  const row = document.createElement("tr");
  const scenarioCell = document.createElement("td");
  const moduleCell = document.createElement("td");
  const statusCell = document.createElement("td");
  const durationCell = document.createElement("td");
  const status = document.createElement("span");

  scenarioCell.textContent = scenario;
  moduleCell.textContent = activeModule;
  status.className = "state running";
  status.textContent = "Executando";
  statusCell.appendChild(status);
  durationCell.textContent = `${duration} s`;
  row.append(scenarioCell, moduleCell, statusCell, durationCell);

  runTable.prepend(row);
  engineStatus.textContent = "Executando";
  addConsoleLine(`Analise iniciada para "${scenario}" em ${activeModule}.`);
  updateMetrics();

  window.setTimeout(() => {
    row.querySelector(".state").className = "state complete";
    row.querySelector(".state").textContent = "Concluido";
    engineStatus.textContent = "Pronto";
    addConsoleLine(`Analise "${scenario}" concluida.`);
    updateMetrics();
  }, 900);
});

clearQueue.addEventListener("click", () => {
  runTable.innerHTML = "";
  addConsoleLine("Fila de execucoes limpa.");
  updateMetrics();
});

document.querySelectorAll("[data-view]").forEach((button) => {
  button.addEventListener("click", () => {
    document.querySelectorAll("[data-view]").forEach((item) => item.classList.remove("active"));
    button.classList.add("active");
    addConsoleLine(`Area "${button.textContent.trim()}" aberta.`);
  });
});

updateMetrics();
