// ScoutFlow Academy MVP frontend logic

const root = document.getElementById("app-root");
const title = document.getElementById("page-title");
const subtitle = document.getElementById("page-subtitle");

const pageMeta = {
  dashboard: ["Inicio", "Resumen operativo de ScoutFlow Academy"],
  players: ["Jugadores", "Vista por tarjetas, filtros y búsqueda inteligente"],
  "ai-import": ["Importar con IA", "Pega WhatsApp, email o texto para crear una ficha"],
  pipeline: ["Captación", "Pipeline de candidatos por estado"],
  documents: ["Documentos", "Documentación pendiente, recibida y validada"],
  reports: ["Informes", "Informes deportivos, académicos y familiares"],
  family: ["Family", "Portal para padres/tutores y jugador"],
  finance: ["Finanzas", "Cuotas, pagos, facturas y becas"],
  permissions: ["Usuarios y permisos", "Roles + jugadores asignados + visibilidad por módulo"],
  settings: ["Configuración", "Academia, idiomas, deportes y marca"]
};

function badgeClass(status) {
  if (status === "Aceptado" || status === "Inscrito") return "green";
  if (status === "Datos incompletos" || status === "Info incompleta") return "red";
  if (status === "Entrevista") return "blue";
  return "yellow";
}

function playerCard(player) {
  const score = player.scoutScore ?? "Pendiente";
  const nationalities = player.nationality.join(" / ");
  return `
    <div class="card player-card">
      <div class="player-photo">Foto jugador</div>
      <div class="player-body">
        <h4>${player.fullName}</h4>
        <div class="row"><span>🌍 ${nationalities}</span><span>📅 ${player.birthYear}</span></div>
        <div class="row"><span>🏀 ${player.primaryPosition} / ${player.secondaryPosition}</span><span>📏 ${player.height}</span></div>
        <div class="row"><span class="badge ${badgeClass(player.status)}">${player.status}</span><span>⭐ ${score}</span></div>
        <div class="icons">
          <span class="icon">🎥 ${player.videos.highlights ? "OK" : "Pendiente"}</span>
          <span class="icon">📄 ${player.documents.passport ? "OK" : "Pendiente"}</span>
          <span class="icon">👨‍👩‍👦 ${player.familyAccess ? "Family" : "Sin Family"}</span>
        </div>
        <div class="card-actions">
          <button class="btn btn-light" onclick="renderPlayerProfile('${player.id}')">Ver ficha</button>
          <button class="btn btn-primary" onclick="renderAIForPlayer('${player.id}')">IA</button>
        </div>
      </div>
    </div>
  `;
}

function renderDashboard() {
  const players = ScoutFlowData.players;
  root.innerHTML = `
    <div class="grid kpis">
      <div class="card kpi"><small>Total jugadores</small><strong>${players.length}</strong></div>
      <div class="card kpi"><small>En evaluación</small><strong>0</strong></div>
      <div class="card kpi"><small>Datos incompletos</small><strong>${players.filter(p => p.status === "Datos incompletos").length}</strong></div>
      <div class="card kpi"><small>Pagos pendientes</small><strong>0</strong></div>
      <div class="card kpi"><small>Family activos</small><strong>${players.filter(p => p.familyAccess).length}</strong></div>
    </div>
    ${renderPlayersSection()}
    <div class="grid two">
      ${renderProfileSection(players[0])}
      ${renderAIImportBox()}
    </div>
  `;
}

function renderPlayersSection() {
  return `
    <section class="card">
      <div class="section-title">
        <h3>Jugadores</h3>
        <span class="badge">Vista principal: tarjetas</span>
      </div>
      <div class="filters">
        <div class="filter">Año</div><div class="filter">País</div><div class="filter">Nacionalidad</div>
        <div class="filter">Posición</div><div class="filter">Altura</div><div class="filter">Estado</div>
        <div class="filter">Documentos</div><div class="filter">Vídeos</div><div class="filter">Family</div>
      </div>
      <div class="grid players">
        ${ScoutFlowData.players.map(playerCard).join("")}
      </div>
    </section>
  `;
}

function renderPlayers() {
  root.innerHTML = renderPlayersSection();
}

function renderProfileSection(player) {
  if (!player) return "";
  return `
    <section class="card">
      <div class="section-title"><h3>Ficha maestra del jugador</h3><span class="badge green">Perfil primero</span></div>
      <div class="profile-head">
        <div class="big-avatar">${player.firstName[0]}${player.lastName[0]}</div>
        <div>
          <h3>${player.fullName}</h3>
          <div class="muted">${player.scoutflowId} · ${player.birthDate} · ${player.primaryPosition}/${player.secondaryPosition} · ${player.height}</div>
          <div style="margin-top:8px"><span class="badge ${badgeClass(player.status)}">${player.status}</span> <span class="badge">Scout Score ${player.scoutScore ?? "pendiente"}</span></div>
        </div>
      </div>
      <div class="tabs">
        <div class="tab active">Perfil</div><div class="tab">Deportivo</div><div class="tab">Académico</div>
        <div class="tab">Familia</div><div class="tab">Documentos</div><div class="tab">Vídeos</div>
        <div class="tab">Captación</div><div class="tab">Seguimiento</div><div class="tab">Finanzas</div><div class="tab">Notas internas</div>
      </div>
      <div class="info-grid">
        <div class="info"><small>Nombre completo</small><strong>${player.fullName}</strong></div>
        <div class="info"><small>Fecha nacimiento</small><strong>${player.birthDate}</strong></div>
        <div class="info"><small>Año</small><strong>${player.birthYear}</strong></div>
        <div class="info"><small>Edad</small><strong>${player.age} años</strong></div>
        <div class="info"><small>Nacionalidad</small><strong>${player.nationality.join(" y ")}</strong></div>
        <div class="info"><small>Deporte</small><strong>${player.sport}</strong></div>
        <div class="info"><small>Posición principal</small><strong>${player.primaryPosition}</strong></div>
        <div class="info"><small>Posición secundaria</small><strong>${player.secondaryPosition}</strong></div>
        <div class="info"><small>Altura</small><strong>${player.height}</strong></div>
      </div>
    </section>
  `;
}

function renderPlayerProfile(id) {
  setActivePage("players");
  const player = ScoutFlowData.players.find(p => p.id === id);
  root.innerHTML = renderProfileSection(player);
}

function renderAIImportBox() {
  return `
    <section class="card">
      <div class="section-title"><h3>Importar con IA</h3><span class="badge">Texto real procesado</span></div>
      <textarea id="ai-text">Pablo Ignacio Andres Suarez nacido en 25 de agosto del 2002, posicion Base/escolta nacionalidad argentina y española mide 1,86 mts</textarea>
      <div style="display:flex;gap:10px;margin-top:12px">
        <button class="btn btn-primary" onclick="simulateAIExtract()">Extraer datos</button>
        <button class="btn btn-light">Crear ficha</button>
      </div>
      <div class="info" style="margin-top:14px" id="ai-result">
        <small>Datos faltantes detectados</small>
        <strong>Foto, país de residencia, ciudad, contacto, club actual, categoría, videos, documentos, familia, objetivo y estado académico.</strong>
      </div>
    </section>
  `;
}

function renderAIImport() {
  root.innerHTML = renderAIImportBox();
}

function renderAIForPlayer(id) {
  const player = ScoutFlowData.players.find(p => p.id === id);
  root.innerHTML = `
    <section class="card">
      <div class="section-title"><h3>Análisis IA · ${player.fullName}</h3><span class="badge">ScoutFlow AI</span></div>
      <div class="info-grid">
        <div class="info"><small>Resumen</small><strong>Base/Escolta con doble nacionalidad argentina y española. Perfil todavía incompleto.</strong></div>
        <div class="info"><small>Faltantes críticos</small><strong>Vídeo, club actual, documentos, contacto familiar y datos académicos.</strong></div>
        <div class="info"><small>Próximo paso</small><strong>Solicitar vídeo de partido completo y datos de contacto.</strong></div>
      </div>
    </section>
  `;
}

function simulateAIExtract() {
  document.getElementById("ai-result").innerHTML = `
    <small>IA detectó</small>
    <strong>Jugador: Pablo Ignacio Andrés Suárez · Nacimiento: 25/08/2002 · Año: 2002 · Nacionalidad: Argentina y española · Posición: Base/Escolta · Altura: 1,86 m.</strong>
  `;
}

function renderPipeline() {
  const stages = ScoutFlowData.pipeline;
  root.innerHTML = `
    <section class="card">
      <div class="section-title"><h3>Pipeline de captación</h3><span class="badge">Estados</span></div>
      <div class="pipeline">
        ${Object.keys(stages).map(stage => `
          <div class="stage">
            <h4>${stage}</h4>
            ${stages[stage].map(id => {
              const p = ScoutFlowData.players.find(player => player.id === id);
              return `<div class="mini">${p ? p.fullName : id}</div>`;
            }).join("")}
          </div>
        `).join("")}
      </div>
    </section>
  `;
}

function renderPermissions() {
  root.innerHTML = `
    <section class="card">
      <div class="section-title"><h3>Usuarios y permisos</h3><span class="badge blue">Rol + jugador asignado</span></div>
      <div class="permission-grid">
        <div class="permission"><div><strong>Director</strong><div class="muted">Acceso total</div></div><div class="switch on"></div></div>
        <div class="permission"><div><strong>Entrenador</strong><div class="muted">Solo jugadores asignados</div></div><div class="switch on"></div></div>
        <div class="permission"><div><strong>Scout</strong><div class="muted">Captación y evaluación inicial</div></div><div class="switch on"></div></div>
        <div class="permission"><div><strong>Padre/Tutor</strong><div class="muted">Solo hijo/a e informes publicados</div></div><div class="switch on"></div></div>
        <div class="permission"><div><strong>Notas internas</strong><div class="muted">Ocultas para familias</div></div><div class="switch on"></div></div>
        <div class="permission"><div><strong>Scout Score</strong><div class="muted">Privado para staff</div></div><div class="switch on"></div></div>
      </div>
    </section>
  `;
}

function renderPlaceholder(page) {
  root.innerHTML = `
    <section class="card">
      <div class="section-title"><h3>${pageMeta[page][0]}</h3><span class="badge">MVP</span></div>
      <p class="muted">Módulo preparado en la estructura real del proyecto. Se conectará con base de datos en la siguiente fase.</p>
    </section>
  `;
}

function setActivePage(page) {
  document.querySelectorAll(".nav-item").forEach(item => {
    item.classList.toggle("active", item.dataset.page === page);
  });
  title.textContent = pageMeta[page]?.[0] || "ScoutFlow";
  subtitle.textContent = pageMeta[page]?.[1] || "";
}

function renderPage(page) {
  setActivePage(page);
  if (page === "dashboard") renderDashboard();
  else if (page === "players") renderPlayers();
  else if (page === "ai-import") renderAIImport();
  else if (page === "pipeline") renderPipeline();
  else if (page === "permissions") renderPermissions();
  else renderPlaceholder(page);
}

document.querySelectorAll(".nav-item").forEach(item => {
  item.addEventListener("click", () => renderPage(item.dataset.page));
});

document.querySelectorAll("[data-page-target]").forEach(btn => {
  btn.addEventListener("click", () => renderPage(btn.dataset.pageTarget));
});

document.getElementById("new-player-btn").addEventListener("click", () => {
  root.innerHTML = `
    <section class="card">
      <div class="section-title"><h3>Nuevo jugador</h3><span class="badge">Formulario base</span></div>
      <div class="form-grid">
        <input placeholder="Nombre" />
        <input placeholder="Apellidos" />
        <input placeholder="Fecha nacimiento" />
        <input placeholder="Nacionalidad" />
        <input placeholder="Deporte" value="Baloncesto" />
        <input placeholder="Posición" />
        <input placeholder="Altura" />
        <input placeholder="Estado" value="Datos incompletos" />
      </div>
      <button class="btn btn-primary" style="margin-top:14px">Guardar jugador</button>
    </section>
  `;
});

document.getElementById("camera-btn").addEventListener("click", () => {
  alert("En la app real este botón abrirá la cámara del teléfono o permitirá subir una foto desde el ordenador.");
});

renderPage("dashboard");
