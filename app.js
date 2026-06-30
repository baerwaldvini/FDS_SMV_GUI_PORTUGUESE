const navButtons = document.querySelectorAll("[data-view]");
const workflowButtons = document.querySelectorAll("[data-step]");
const generateButton = document.querySelector("#generateButton");
const validateButton = document.querySelector("#validateButton");
const smokeviewButton = document.querySelector("#smokeviewButton");
const extractButton = document.querySelector("#extractButton");
const projectForm = document.querySelector("#projectForm");
const fireForm = document.querySelector("#fireForm");
const fuelType = document.querySelector("#fuelType");
const hrrpua = document.querySelector("#hrrpua");
const fuelHelp = document.querySelector("#fuelHelp");
const consoleOutput = document.querySelector("#consoleOutput");
const engineStatus = document.querySelector("#engineStatus");

const API_BASE = "http://127.0.0.1:8765";

const fuelDescriptions = {
  generic_office: "Carga de escritorio: aproximacao para mesas, papel e plasticos leves. Use como ponto de partida e revise conforme carga de incendio real.",
  wood: "Madeira comum: adequada para mobiliario, portas e paineis. A taxa de liberacao de calor depende da area exposta e ventilacao.",
  foam: "Espuma/poliuretano: representa sofas, colchoes e estofados. Tende a liberar calor e fumaca rapidamente, exigindo revisao criteriosa.",
  textile: "Tecido: aplicavel a cortinas, roupas e armazenagem leve. A propagacao pode mudar bastante conforme densidade e disposicao.",
  custom: "Personalizado: use quando houver ensaio, curva conhecida ou material especifico. A GUI deve pedir propriedades completas antes de exportar.",
};

function addConsoleLine(message) {
  const line = document.createElement("span");
  line.textContent = `> ${message}`;
  consoleOutput.appendChild(line);
  consoleOutput.scrollTop = consoleOutput.scrollHeight;
}

function setActiveStep(step) {
  navButtons.forEach((button) => button.classList.toggle("active", button.dataset.view === step));
  workflowButtons.forEach((button) => button.classList.toggle("active", button.dataset.step === step));
  engineStatus.textContent = step === "fds" ? "Pronto para exportar" : "Em modelagem";
  addConsoleLine(`Etapa ativa: ${step}.`);
}

function formPayload() {
  const projectData = new FormData(projectForm);
  const fireData = new FormData(fireForm);
  return {
    projectName: projectData.get("projectName") || "Projeto sem nome",
    drawingFile: projectData.get("drawingFile") || "",
    outputFolder: projectData.get("outputFolder") || "",
    ceilingHeight: projectData.get("ceilingHeight") || "0",
    area: projectData.get("area") || "0",
    fuelType: fireData.get("fuelType") || "",
    hrrpua: fireData.get("hrrpua") || "0",
    incidentLocation: fireData.get("incidentLocation") || "",
    duration: fireData.get("duration") || "0",
    meshSize: fireData.get("meshSize") || "",
    ventilation: fireData.get("ventilation") || "",
  };
}

async function postJson(path, payload) {
  let response;
  try {
    response = await fetch(`${API_BASE}${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
  } catch (error) {
    throw new Error("Backend local indisponivel. Abra a GUI pelo start-gui.bat e use http://127.0.0.1:8765.");
  }
  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.error || "Falha na comunicacao com o backend.");
  }
  return data;
}

async function checkBackend() {
  try {
    const response = await fetch(`${API_BASE}/api/status`);
    if (!response.ok) {
      throw new Error();
    }
    addConsoleLine("Backend local conectado.");
  } catch (error) {
    addConsoleLine("Backend local indisponivel. Inicie pelo start-gui.bat e acesse http://127.0.0.1:8765.");
  }
}

navButtons.forEach((button) => {
  button.addEventListener("click", () => setActiveStep(button.dataset.view));
});

workflowButtons.forEach((button) => {
  button.addEventListener("click", () => setActiveStep(button.dataset.step));
});

fuelType.addEventListener("change", () => {
  const selected = fuelType.selectedOptions[0];
  hrrpua.value = selected.dataset.hrr || "0";
  fuelHelp.textContent = fuelDescriptions[fuelType.value];
  addConsoleLine(`Material selecionado: ${selected.textContent}.`);
});

extractButton.addEventListener("click", () => {
  engineStatus.textContent = "Revisao necessaria";
  addConsoleLine("Extracao simulada: paredes, aberturas e preventivos foram marcados para conferencia.");
  addConsoleLine("Proxima etapa real: conectar OCR/CV para ler PDF/DWG/imagem da prancha.");
});

document.querySelectorAll("[data-file-target]").forEach((button) => {
  button.addEventListener("click", async () => {
    const input = document.querySelector(`#${button.dataset.fileTarget}`);
    try {
      const result = await postJson("/api/select-file", {
        kind: button.dataset.fileKind,
        currentPath: input.value,
      });
      if (result.path) {
        input.value = result.path;
        addConsoleLine(`Arquivo selecionado: ${result.path}`);
      } else {
        addConsoleLine("Selecao de arquivo cancelada.");
      }
    } catch (error) {
      addConsoleLine(error.message);
    }
  });
});

validateButton.addEventListener("click", async () => {
  try {
    const result = await postJson("/api/validate", formPayload());
    addConsoleLine(`FDS: ${result.fds}`);
    addConsoleLine(`Smokeview: ${result.smokeview}`);
    addConsoleLine(result.ok ? "Ambiente FDS/SMV validado." : "Validacao incompleta. Confira caminhos.");
  } catch (error) {
    addConsoleLine(error.message);
  }
});

generateButton.addEventListener("click", async () => {
  const payload = formPayload();
  engineStatus.textContent = "Exportando";
  addConsoleLine(`Geracao solicitada para "${payload.projectName}".`);
  addConsoleLine(`Incidente: ${payload.incidentLocation}; material: ${fuelType.selectedOptions[0].textContent}; HRRPUA: ${payload.hrrpua}.`);
  addConsoleLine(`Pasta de saida: ${payload.outputFolder}.`);
  addConsoleLine("Nesta etapa a GUI deve gerar o arquivo .fds na pasta de saida antes de chamar o FDS.");

  try {
    await postJson("/api/run", payload);
    addConsoleLine("FDS iniciado usando o caso gerado na pasta de saida.");
    engineStatus.textContent = "Executando FDS";
  } catch (error) {
    addConsoleLine(error.message);
    engineStatus.textContent = "Revisar entradas";
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

document.querySelector("#clearQueue").addEventListener("click", () => {
  consoleOutput.innerHTML = "";
  addConsoleLine("Console limpo.");
});

checkBackend();
