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
const stepTitle = document.querySelector("#stepTitle");
const stepDescription = document.querySelector("#stepDescription");
const stepChecklist = document.querySelector("#stepChecklist");

const API_BASE = "http://127.0.0.1:8766";

const stepGuidance = {
  planta: {
    title: "1. Ler prancha",
    description: "Envie a prancha para que a GUI identifique escala, limites da edificacao, compartimentos, aberturas e simbolos de preventivos. Esses dados viram a base geometrica do arquivo FDS.",
    items: [
      "Escolha PDF, DXF, DWG ou imagem da prancha.",
      "Informe a escala quando ela nao puder ser lida com confianca.",
      "Defina a pasta onde os arquivos gerados serao salvos.",
    ],
  },
  edificacao: {
    title: "2. Revisar edificacao solida",
    description: "Nesta etapa voce confere o que a leitura da prancha transformou em geometria: paredes, limites, ambientes, aberturas, pe-direito, obstaculos e dominio de simulacao.",
    items: [
      "Paredes e obstaculos serao convertidos para OBST.",
      "Janelas, portas e vazios serao convertidos para VENT ou aberturas equivalentes.",
      "Dimensoes incorretas devem ser corrigidas antes de gerar a malha FDS.",
    ],
  },
  preventivos: {
    title: "3. Conferir preventivos",
    description: "A GUI tenta reconhecer simbolos de seguranca da prancha, mas a decisao tecnica precisa ser revisada. Preventivos nao definem o fogo diretamente, mas ajudam a documentar o cenario e interpretar rotas, protecao e condicoes de projeto.",
    items: [
      "Confirme extintores, hidrantes, alarmes, sinalizacoes e saidas.",
      "Marque itens ausentes ou lidos em posicao errada.",
      "Use a revisao para separar desenho arquitetonico de medidas de protecao.",
    ],
  },
  incendio: {
    title: "4. Definir incendio",
    description: "A prancha mostra a edificacao, mas nao sabe o que esta queimando, onde o incidente comeca ou qual curva de liberacao de calor usar. Esses dados precisam vir do usuario ou de uma premissa tecnica.",
    items: [
      "Material combustivel define propriedades de queima, fumaca e calor.",
      "HRRPUA/coeficiente controla a intensidade inicial da fonte de fogo.",
      "Local do incidente posiciona o foco no dominio para calcular calor e fumaca.",
    ],
  },
  fds: {
    title: "5. Gerar FDS",
    description: "Depois da leitura e revisao, a GUI monta o arquivo .fds na pasta de saida. O arquivo final deve conter HEAD, TIME, MESH, OBST, VENT, SURF, REAC, dispositivos e saidas para Smokeview.",
    items: [
      "A pasta de saida recebe o .fds e os arquivos gerados pela simulacao.",
      "O primeiro arquivo pode ser um rascunho quando a geometria ainda nao foi revisada.",
      "A execucao no FDS so deve acontecer quando as premissas estiverem conferidas.",
    ],
  },
};

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
  const guidance = stepGuidance[step];
  if (guidance) {
    stepTitle.textContent = guidance.title;
    stepDescription.textContent = guidance.description;
    stepChecklist.innerHTML = "";
    guidance.items.forEach((item) => {
      const line = document.createElement("li");
      line.textContent = item;
      stepChecklist.appendChild(line);
    });
  }
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
    throw new Error("Backend local indisponivel. Abra a GUI pelo start-gui.bat e use http://127.0.0.1:8766.");
  }
  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.error || "Falha na comunicacao com o backend.");
  }
  return data;
}

async function getJson(path) {
  let response;
  try {
    response = await fetch(`${API_BASE}${path}`);
  } catch (error) {
    throw new Error("Backend local indisponivel. Abra a GUI pelo start-gui.bat e use http://127.0.0.1:8766.");
  }
  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.error || "Falha na comunicacao com o backend.");
  }
  return data;
}

async function waitForPickerResult(token) {
  for (let attempt = 0; attempt < 180; attempt += 1) {
    const result = await getJson(`/api/select-file-result?token=${encodeURIComponent(token)}`);
    if (result.done) {
      return result.path || "";
    }
    await new Promise((resolve) => window.setTimeout(resolve, 700));
  }
  throw new Error("Selecao de arquivo expirou.");
}

async function checkBackend() {
  try {
    const response = await fetch(`${API_BASE}/api/status`);
    if (!response.ok) {
      throw new Error();
    }
    addConsoleLine("Backend local conectado.");
  } catch (error) {
    addConsoleLine("Backend local indisponivel. Inicie pelo start-gui.bat e acesse http://127.0.0.1:8766.");
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
  addConsoleLine("Interpretacao da prancha solicitada.");
  addConsoleLine("Modulo de OCR/CV ainda sera conectado: ele devera extrair paredes, aberturas, escala, compartimentos e preventivos.");
  addConsoleLine("Por enquanto, a GUI prepara um rascunho FDS e destaca quais informacoes voce precisa revisar.");
});

document.querySelectorAll("[data-file-target]").forEach((button) => {
  button.addEventListener("click", async () => {
    const input = document.querySelector(`#${button.dataset.fileTarget}`);
    try {
      const result = await postJson("/api/select-file", {
        kind: button.dataset.fileKind,
        currentPath: input.value,
      });
      addConsoleLine("Aguardando selecao na janela do Windows.");
      const selectedPath = result.token ? await waitForPickerResult(result.token) : result.path;
      if (selectedPath) {
        input.value = selectedPath;
        addConsoleLine(`Caminho selecionado: ${selectedPath}`);
      } else {
        addConsoleLine("Selecao cancelada.");
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
  addConsoleLine("Gerando arquivo .fds inicial na pasta de saida.");

  try {
    const result = await postJson("/api/generate-fds", payload);
    addConsoleLine(`Arquivo FDS gerado: ${result.fdsFile}`);
    addConsoleLine("Este e um rascunho inicial. A geometria extraida da prancha ainda precisa ser implementada/revisada antes da simulacao final.");
    engineStatus.textContent = "FDS gerado";
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
setActiveStep("planta");
