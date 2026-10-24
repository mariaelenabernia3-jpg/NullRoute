// GalaxyGens · núcleo compartido
const SUPABASE_URL = 'https://ndsapciemgudjkfefjcf.supabase.co';
const SUPABASE_KEY = 'sb_publishable_5fsPp1mJiOlYBZ0PpEz5zg_UCs4X8nF';
const db = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

let me = null;
try { me = JSON.parse(localStorage.getItem('galaxy_session_user') || 'null'); } catch (e) {}
if (!me || !me.id) { location.replace('login.html'); throw new Error('Sin sesión'); }

const fmt = n => { n = Number(n || 0); if (n >= 1e6) return (n/1e6).toFixed(1)+'M'; if (n >= 1e3) return (n/1e3).toFixed(1)+'K'; if (Number.isInteger(n)) return n; if (n < 1) return n.toFixed(3); if (n < 100) return n.toFixed(2); return Math.floor(n); };
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const $ = id => document.getElementById(id);
function toast(t){ const el = $('toast'); el.textContent = t; el.classList.add('s'); clearTimeout(el._t); el._t = setTimeout(() => el.classList.remove('s'), 2600); }
function logout(){ localStorage.removeItem('galaxy_session_user'); location.href = 'index.html'; }

let state = null;
const isActive = () => !document.hidden && document.hasFocus();
const PLAY_KEY = 'galaxy_play_' + me.id;
let play = Number(localStorage.getItem(PLAY_KEY) || 0);
const getPlay = () => play;
const syncPlay = n => { n = Number(n || 0); if (n > play) { play = n; localStorage.setItem(PLAY_KEY, play); } };
setInterval(() => { if (isActive()) { play++; localStorage.setItem(PLAY_KEY, play); } }, 1000);

// Secciones del menú lateral ordenadas
const LINKS_PLANET = [
  ['generadores.html','⚛️ Generadores'],
  ['granja.html','🌱 Granja Lunar'],
  ['almacen.html','📦 Almacén'],
  ['planeta.html','🪐 Mi Planeta'],
  ['ranking.html','🏆 Ranking'],
  ['perfil.html','👤 Mi Perfil']
];

function toggleSidebar(forceClose = false){
  const nav = $('nav');
  const overlay = $('navOverlay');
  if(!nav || !overlay) return;
  if(forceClose || nav.classList.contains('open')){
    nav.classList.remove('open');
    overlay.classList.remove('open');
  } else {
    nav.classList.add('open');
    overlay.classList.add('open');
  }
}

function renderShell(active){
  document.body.insertAdjacentHTML('afterbegin', `
  <div class="top">
    <div style="display:flex;justify-content:space-between;align-items:center;width:100%;gap:10px">
      <div style="display:flex;align-items:center;gap:10px">
        <button class="btn-burger" id="btnBurger" onclick="toggleSidebar()" title="Abrir Menú">☰</button>
        <a class="logo px" href="index.html">GALAXYGENS</a>
      </div>
      <div class="user-info">
        <div class="user-tag px">PILOTO: <span id="opUser"></span></div>
        <button class="btn-exit" onclick="logout()">Salir</button>
      </div>
    </div>
    <div class="nav-currencies">
      <div class="stat mult"><span id="stMult">x0</span></div>
      <div class="stat cr"><span id="stCr">0</span> CR</div>
      <div class="stat pl"><span id="stPl">0</span> PL</div>
      <div class="stat ec"><span id="stEc">0</span> EC</div>
      <div class="stat ns"><span id="stNs">0</span> NS</div>
    </div>
  </div>
  <div class="nav-overlay" id="navOverlay" onclick="toggleSidebar(true)"></div>
  <div class="app">
    <aside class="side-nav drawer" id="nav">
      <button class="nav-close" onclick="toggleSidebar(true)">✕ CERRAR</button>
    </aside>
    <main class="main"><div class="content-wrapper" id="view"></div></main>
  </div>
  <div id="toast"></div>`);
  document.body.dataset.active = active;
}

function renderHUD(u){
  $('opUser').textContent = u.username;
  $('stCr').textContent = fmt(u.credits); $('stPl').textContent = fmt(u.plasma);
  $('stEc').textContent = fmt(u.quantum); $('stNs').textContent = fmt(u.supernova);
  $('stMult').textContent = 'x' + (u.multiplier || 0);
}

function renderNav(s){
  const act = document.body.dataset.active;
  const a = (href, label, extra='') => `<a href="${href}" onclick="toggleSidebar(true)" class="side-link${act === href ? ' current' : ''}">${label}${extra}</a>`;
  let h = `<button class="nav-close" onclick="toggleSidebar(true)">✕ CERRAR</button>` + a('lobby.html', '🏠 Lobby');
  if (s.planet) {
    h += LINKS_PLANET.map(([href, l]) => a(href, l)).join('');
    if (s.planet.is_owner) h += a('correo.html', '✉️ Correo', s.planet.pending_count ? `<span class="badge">${s.planet.pending_count}</span>` : '');
  }
  $('nav').innerHTML = h;
}

function applyState(s){
  state = s; me = Object.assign(me, s.user);
  localStorage.setItem('galaxy_session_user', JSON.stringify(me));
  renderHUD(s.user); renderNav(s);
}

async function refresh(){
  const { data, error } = await db.rpc('galaxy_get_state', { p_user_id: me.id });
  if (error || !data) return null;
  if (!data.success) { logout(); return null; }
  applyState(data); return data;
}

async function startPage(opts){
  renderShell(opts.active);
  renderHUD(me);
  const guard = s => {
    if (opts.needPlanet && !s.planet) { location.replace('lobby.html'); return false; }
    if (opts.ownerOnly && !(s.planet && s.planet.is_owner)) { location.replace(s.planet ? 'planeta.html' : 'lobby.html'); return false; }
    return true;
  };
  const s = await refresh();
  if (!s) { toast('Error de conexión'); return; }
  if (!guard(s)) return;
  opts.onState && opts.onState(s);
  setInterval(async () => { if (document.hidden) return; const n = await refresh(); if (n && guard(n)) opts.onState && opts.onState(n); }, 8000);
  const page = opts.active.replace('.html', '');
  const beat = async mode => {
    try {
      const { data } = await db.rpc('galaxy_heartbeat', { p_user_id: me.id, p_page: page, p_mode: mode });
      if (data && data.valid === false) {
        alert('⚠️ ' + data.msg);
        logout();
      }
    } catch (err) {}
  };
  const flush = () => { try { fetch(SUPABASE_URL + '/rest/v1/rpc/galaxy_heartbeat', { method: 'POST', keepalive: true,
      headers: { apikey: SUPABASE_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_user_id: me.id, p_page: page, p_mode: 'flush' }) }).catch(() => {}); } catch (e) {} };
  const pulse = () => { if (!document.hidden) beat(isActive() ? 'tick' : 'idle'); };
  pulse(); setInterval(pulse, 5000);
  document.addEventListener('visibilitychange', () => document.hidden ? flush() : pulse());
  window.addEventListener('pagehide', flush);
  window.addEventListener('blur', flush);
  window.addEventListener('focus', pulse);
}