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
const moduleBadge = document.querySelector("#moduleBadge");
const previewTitle = document.querySelector("#previewTitle");
const planCanvas = document.querySelector(".plan-canvas");
const extinguisherCount = document.querySelector("#extinguisherCount");
const hydrantCount = document.querySelector("#hydrantCount");
const exitCount = document.querySelector("#exitCount");
const solidCount = document.querySelector("#solidCount");
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
    scale: projectData.get("scale") || "",
    ceilingHeight: projectData.get("ceilingHeight") || "0",
    area: projectData.get("area") || "0",
    reviewRequired: projectData.get("reviewRequired") === "on",
    fuelType: fireData.get("fuelType") || "",
    hrrpua: fireData.get("hrrpua") || "0",
    incidentLocation: fireData.get("incidentLocation") || "",
    duration: fireData.get("duration") || "0",
    meshSize: fireData.get("meshSize") || "",
    ventilation: fireData.get("ventilation") || "",
  };
}

function setMetricValue(element, value) {
  if (element) {
    element.textContent = Number.isFinite(Number(value)) ? String(value) : "0";
  }
}

function createPreviewElement(className, text, title) {
  const element = document.createElement("div");
  element.className = className;
  if (title) {
    element.title = title;
  }
  if (text) {
    const label = document.createElement("span");
    label.textContent = text;
    element.appendChild(label);
  }
  return element;
}

function createPreviewMarker(className, title) {
  const marker = document.createElement("i");
  marker.className = className;
  marker.title = title;
  return marker;
}

function renderPendingPreview(model) {
  planCanvas.classList.add("preview-pending");
  const room = createPreviewElement("room room-main room-pending", "OCR/CV pendente");
  const sideTop = createPreviewElement("room room-corridor room-pending", "Prancha");
  const sideBottom = createPreviewElement("room room-service room-pending", "Aguardando leitura");
  const overlay = createPreviewElement(
    "preview-message",
    model.extension ? `Arquivo ${model.extension.toUpperCase()} selecionado` : "Arquivo selecionado",
  );

  planCanvas.append(room, sideTop, sideBottom, overlay);
}

function renderFdsPreview(model) {
  const solids = Number(model.geometry?.solids || 0);
  const vents = Number(model.geometry?.vents || 0);
  const meshes = Number(model.geometry?.meshes || 0);
  const exits = Number(model.preventives?.exits || 0);
  const hydrants = Number(model.preventives?.hydrants || 0);
  const extinguishers = Number(model.preventives?.extinguishers || 0);
  const hasGeometry = solids > 0 || vents > 0 || meshes > 0;

  if (!hasGeometry) {
    planCanvas.classList.add("preview-empty");
    planCanvas.append(
      createPreviewElement("room room-main room-pending", "Sem geometria FDS"),
      createPreviewElement("room room-corridor room-pending", "MESH/OBST"),
      createPreviewElement("room room-service room-pending", "VENT"),
      createPreviewElement("preview-message", "Nenhum OBST, VENT ou MESH foi encontrado no arquivo."),
    );
    return;
  }

  const mainLabel = solids > 0 ? `${solids} solidos` : "Envelope";
  const ventLabel = vents > 0 ? `${vents} vents` : "Sem vents";
  const meshLabel = meshes > 0 ? `${meshes} malha(s)` : "Malha nao detectada";

  const mainRoom = createPreviewElement("room room-main", mainLabel, "Solidos/OBST detectados no FDS");
  const ventRoom = createPreviewElement("room room-corridor", ventLabel, "Aberturas/VENT detectadas no FDS");
  const meshRoom = createPreviewElement("room room-service", meshLabel, "Malhas/MESH detectadas no FDS");

  planCanvas.append(mainRoom, ventRoom, meshRoom);

  if (extinguishers > 0) {
    planCanvas.append(createPreviewMarker("device extinguisher", `${extinguishers} extintor(es)`));
  }
  if (hydrants > 0) {
    planCanvas.append(createPreviewMarker("device hydrant", `${hydrants} hidrante(s)`));
  }
  if (exits > 0) {
    planCanvas.append(createPreviewMarker("device exit-sign", `${exits} saida(s)`));
  }
}

function renderRasterPreview(model) {
  const walls = Array.isArray(model.geometry?.walls) ? model.geometry.walls : [];
  const surface = createPreviewElement(
    "raster-preview-surface",
    walls.length ? "" : "Nenhuma parede detectada",
    "Previa esquematica das linhas detectadas na prancha",
  );

  walls.forEach((wall) => {
    const wallElement = document.createElement("i");
    wallElement.className = "raster-wall";
    wallElement.style.left = `${Math.max(Number(wall.x || 0) * 100, 0)}%`;
    wallElement.style.top = `${Math.max(Number(wall.y || 0) * 100, 0)}%`;
    wallElement.style.width = `${Math.max(Number(wall.w || 0.01) * 100, 0.8)}%`;
    wallElement.style.height = `${Math.max(Number(wall.h || 0.01) * 100, 0.8)}%`;
    surface.appendChild(wallElement);
  });

  const overlay = createPreviewElement(
    "preview-message",
    `${walls.length} parede(s) detectada(s) para gerar OBST no FDS`,
  );

  planCanvas.classList.add("preview-raster");
  planCanvas.append(surface, overlay);
}

function renderPlanPreview(model) {
  if (!planCanvas) {
    return;
  }

  planCanvas.classList.remove("preview-pending", "preview-empty", "preview-raster");
  planCanvas.innerHTML = "";

  if (model.sourceType === "fds") {
    renderFdsPreview(model);
    return;
  }
  if (model.sourceType === "raster") {
    renderRasterPreview(model);
    return;
  }

  renderPendingPreview(model);
}

function updateExtractedModel(model) {
  if (!model) {
    return;
  }

  previewTitle.textContent = model.title || "Edificacao solida";
  moduleBadge.textContent = model.status || "Revisao necessaria";
  setMetricValue(extinguisherCount, model.preventives?.extinguishers);
  setMetricValue(hydrantCount, model.preventives?.hydrants);
  setMetricValue(exitCount, model.preventives?.exits);
  setMetricValue(solidCount, model.geometry?.solids);
  renderPlanPreview(model);
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

extractButton.addEventListener("click", async () => {
  const originalText = extractButton.textContent;
  extractButton.disabled = true;
  extractButton.textContent = "Interpretando...";
  engineStatus.textContent = "Interpretando";
  addConsoleLine("Interpretacao da prancha solicitada.");

  try {
    const result = await postJson("/api/interpret-drawing", formPayload());
    updateExtractedModel(result.model);
    engineStatus.textContent = result.reviewRequired ? "Revisao necessaria" : "Modelo interpretado";
    addConsoleLine(result.message);
    (result.notes || []).forEach((note) => addConsoleLine(note));
  } catch (error) {
    engineStatus.textContent = "Revisar entradas";
    addConsoleLine(error.message);
  } finally {
    extractButton.disabled = false;
    extractButton.textContent = originalText;
  }
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
