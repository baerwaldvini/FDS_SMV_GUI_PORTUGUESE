const moduleButtons = document.querySelectorAll("[data-module]");
const moduleBadge = document.querySelector("#moduleBadge");
const runButton = document.querySelector("#runButton");
const validateButton = document.querySelector("#validateButton");
const smokeviewButton = document.querySelector("#smokeviewButton");
const parameterForm = document.querySelector("#parameterForm");
const runTable = document.querySelector("#runTable");
const consoleOutput = document.querySelector("#consoleOutput");
const engineStatus = document.querySelector("#engineStatus");
const scenarioCount = document.querySelector("#scenarioCount");
const totalDuration = document.querySelector("#totalDuration");
const lastModule = document.querySelector("#lastModule");
const clearQueue = document.querySelector("#clearQueue");

const API_BASE = "http://127.0.0.1:8765";
let activeModule = "FDS";
let pollTimer = null;

function formPayload() {
  const data = new FormData(parameterForm);
  return {
    scenario: data.get("scenario") || "Cenario sem nome",
    inputFile: data.get("inputFile") || "",
    duration: data.get("duration") || "0",
    sample: data.get("sample") || "0",
    mode: data.get("mode") || "",
    exportReport: data.get("exportReport") === "on",
  };
}

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

function createRunRow(payload, statusText = "Executando") {
  const row = document.createElement("tr");
  const scenarioCell = document.createElement("td");
  const moduleCell = document.createElement("td");
  const statusCell = document.createElement("td");
  const durationCell = document.createElement("td");
  const status = document.createElement("span");

  scenarioCell.textContent = payload.scenario;
  moduleCell.textContent = activeModule;
  status.className = "state running";
  status.textContent = statusText;
  statusCell.appendChild(status);
  durationCell.textContent = `${payload.duration} s`;
  row.append(scenarioCell, moduleCell, statusCell, durationCell);
  return row;
}

async function postJson(path, payload) {
  const response = await fetch(`${API_BASE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.error || "Falha na comunicacao com o backend.");
  }
  return data;
}

async function refreshStatus(row) {
  const response = await fetch(`${API_BASE}/api/status`);
  const status = await response.json();
  engineStatus.textContent = status.running ? "Executando" : "Pronto";

  const lastLines = status.log.slice(-8);
  consoleOutput.innerHTML = "";
  lastLines.forEach(addConsoleLine);

  if (!status.running && row) {
    const state = row.querySelector(".state");
    state.className = status.last_return_code === 0 ? "state complete" : "state waiting";
    state.textContent = status.last_return_code === 0 ? "Concluido" : "Verificar log";
    window.clearInterval(pollTimer);
    pollTimer = null;
  }
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

validateButton.addEventListener("click", async () => {
  try {
    const result = await postJson("/api/validate", formPayload());
    addConsoleLine(`FDS: ${result.fds}`);
    addConsoleLine(`Smokeview: ${result.smokeview}`);
    addConsoleLine(result.ok ? "Ambiente validado." : "Validacao incompleta. Confira caminhos.");
  } catch (error) {
    addConsoleLine(error.message);
  }
});

runButton.addEventListener("click", async () => {
  const payload = formPayload();
  const row = createRunRow(payload);
  runTable.prepend(row);
  updateMetrics();

  try {
    await postJson("/api/run", payload);
    engineStatus.textContent = "Executando";
    addConsoleLine(`FDS iniciado para "${payload.scenario}".`);
    window.clearInterval(pollTimer);
    pollTimer = window.setInterval(() => refreshStatus(row), 1200);
  } catch (error) {
    row.querySelector(".state").className = "state waiting";
    row.querySelector(".state").textContent = "Erro";
    addConsoleLine(error.message);
  }
});

smokeviewButton.addEventListener("click", async () => {
  try {
    const result = await postJson("/api/open-smokeview", formPayload());
    addConsoleLine(`Smokeview aberto: ${result.smv}`);
  } catch (error) {
    addConsoleLine(error.message);
  }
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
