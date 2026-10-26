// GalaxyGens v8 · Núcleo limpio anticloneo
const SUPABASE_URL = 'https://ndsapciemgudjkfefjcf.supabase.co';
const SUPABASE_KEY = 'sb_publishable_5fsPp1mJiOlYBZ0PpEz5zg_UCs4X8nF';
const db = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

// ============================================================
// SESIÓN Y SEGURIDAD
// ============================================================
let me = null;
let SESSION_HASH = null;
let BROWSER_HASH = null;

try {
  const sess = JSON.parse(localStorage.getItem('galaxy_session_user') || 'null');
  if (sess && sess.id) {
    me = sess;
    SESSION_HASH = sess.session_hash || null;
    BROWSER_HASH = sess.browser_hash || localStorage.getItem('galaxy_device_id') || 'DEV_UNKNOWN';
  }
} catch (e) {}

if (!me || !me.id) {
  location.replace('login.html');
  throw new Error('Sin sesión válida');
}

// Las sesiones antiguas guardadas sin session_hash no pueden validar las
// RPC económicas nuevas. Obligamos a un login limpio una sola vez.
if (!SESSION_HASH) {
  localStorage.removeItem('galaxy_session_user');
  location.replace('login.html');
  throw new Error('Sesión antigua: vuelve a entrar');
}

// ============================================================
// FORMATEADOR DE NÚMEROS ASTRONÓMICOS (K, M, B, T, Qa, Qi...)
// ============================================================
const SUFFIXES = [
  '', 'K', 'M', 'B', 'T', 'Qa', 'Qi', 'Sx', 'Sp', 'Oc', 'No', 
  'Dc', 'Ud', 'Dd', 'Td', 'Qad', 'Qid', 'Sxd', 'Spd', 'Ocd', 'Nod', 'Vg'
];

const fmt = n => {
  n = Number(n || 0);
  if (n === 0) return '0';
  if (n < 0) return '-' + fmt(-n);
  if (n < 1000) {
    if (Number.isInteger(n)) return String(n);
    if (n < 1) return n.toFixed(3);
    return n.toFixed(2);
  }
  const tier = Math.floor(Math.log10(n) / 3);
  if (tier >= SUFFIXES.length) return n.toExponential(2);
  const scale = Math.pow(10, tier * 3);
  const scaled = n / scale;
  const decimals = scaled >= 100 ? 0 : (scaled >= 10 ? 1 : 2);
  return scaled.toFixed(decimals) + SUFFIXES[tier];
};

const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({
  '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
}[c]));

const $ = id => document.getElementById(id);

function toast(t) {
  const el = $('toast');
  if (!el) return;
  el.textContent = t;
  el.classList.add('s');
  clearTimeout(el._t);
  el._t = setTimeout(() => el.classList.remove('s'), 2600);
}

async function logout() {
  try {
    if (me && me.id) {
      await db.rpc('galaxy_logout_session', {
        p_user_id: me.id,
        p_session_hash: SESSION_HASH
      });
    }
  } catch(e) {}
  localStorage.removeItem('galaxy_session_user');
  location.href = 'login.html';
}

let state = null;
const isActive = () => !document.hidden && document.hasFocus();

async function validateSession() {
  try {
    const { data, error } = await db.rpc('galaxy_heartbeat_validate', {
      p_user_id: me.id,
      p_session_hash: SESSION_HASH,
      p_browser_hash: BROWSER_HASH
    });
    if (error) return true;
    if (data && data.valid === false) {
      alert('⚠️ ' + (data.msg || 'Sesión terminada en este dispositivo'));
      logout();
      return false;
    }
    return true;
  } catch (err) {
    return true;
  }
}

function renderHUD(u) {
  if (!u) return;
  const opUser = $('opUser');
  const stCr = $('stCr');
  const stPl = $('stPl');
  const stOrb = $('stOrb');
  const stNs = $('stNs');
  const stMult = $('stMult');

  if (opUser) opUser.textContent = u.username || 'Comandante';
  if (stCr) stCr.textContent = fmt(u.credits);
  if (stPl) stPl.textContent = fmt(u.plasma);
  if (stOrb) stOrb.textContent = fmt(u.quantum); // Columna cuántica reconvertida en Orbes
  if (stNs) stNs.textContent = fmt(u.supernova);

  if (stMult) {
    const unlocked = !!u.wand_unlocked;
    const mult = Number(u.sales_multiplier ?? u.multiplier ?? 0);
    stMult.textContent = (unlocked ? '🪄 x' : 'x') + mult;
    stMult.parentElement?.classList.toggle('active', unlocked);
  }
}

// El estado de la varita vive en Supabase (galaxy_players) y se consulta
// aparte para que el HUD siga correcto aunque galaxy_get_state no devuelva
// las columnas nuevas.
async function syncWandStatus() {
  if (!me || !me.id || !SESSION_HASH) return null;
  try {
    const { data, error } = await db.rpc('galaxy_wand_status', {
      p_user_id: me.id,
      p_session_hash: SESSION_HASH
    });
    if (error || !data || !data.success) return null;
    me.wand_unlocked = !!data.wand_unlocked;
    me.sales_multiplier = Number(data.sales_multiplier || 0);
    me.wand_count = Number(data.wand_count || 0);
    localStorage.setItem('galaxy_session_user', JSON.stringify({
      ...me,
      session_hash: SESSION_HASH,
      browser_hash: BROWSER_HASH
    }));
    renderHUD(me);
    return data;
  } catch (e) {
    return null;
  }
}

const LINKS_PLANET = [
  ['generadores.html', '⚛️ Generadores'],
  ['granja.html', '🌱 Granja Lunar'],
  ['almacen.html', '📦 Almacén'],
  ['inventario.html', '🎒 Inventario'],
  ['mercado.html', '🏪 Mercado'],
  ['planeta.html', '🪐 Mi Planeta'],
  ['ranking.html', '🏆 Ranking'],
  ['perfil.html', '👤 Mi Perfil']
];

function toggleSidebar(forceClose = false) {
  const nav = $('nav');
  const overlay = $('navOverlay');
  if (!nav || !overlay) return;
  if (forceClose || nav.classList.contains('open')) {
    nav.classList.remove('open');
    overlay.classList.remove('open');
  } else {
    nav.classList.add('open');
    overlay.classList.add('open');
  }
}

function renderShell(active) {
  if ($('btnBurger')) return;
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
      <div class="stat ec" title="Orbes Cósmicos"><span id="stOrb">0</span> ORB</div>
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

function renderNav(s) {
  const act = document.body.dataset.active;
  const a = (href, label, extra = '') =>
    `<a href="${href}" onclick="toggleSidebar(true)" class="side-link${act === href ? ' current' : ''}">${label}${extra}</a>`;
  let h = `<button class="nav-close" onclick="toggleSidebar(true)">✕ CERRAR</button>` + a('lobby.html', '🏠 Lobby');
  if (s && s.planet) {
    h += LINKS_PLANET.map(([href, l]) => a(href, l)).join('');
    if (s.planet.is_owner) {
      h += a('correo.html', '✉️ Correo', s.planet.pending_count ? `<span class="badge">${s.planet.pending_count}</span>` : '');
    }
  }
  const nav = $('nav');
  if (nav) nav.innerHTML = h;
}

function applyState(s) {
  if (!s || !s.user) return;
  state = s;
  me = Object.assign(me, s.user);
  localStorage.setItem('galaxy_session_user', JSON.stringify({...me, session_hash: SESSION_HASH, browser_hash: BROWSER_HASH}));
  renderHUD(s.user);
  renderNav(s);
}

async function refresh() {
  if (!await validateSession()) return null;
  try {
    const { data, error } = await db.rpc('galaxy_get_state', { p_user_id: me.id });
    if (error || !data) return null;
    if (data.success === false) {
      logout();
      return null;
    }
    applyState(data);
    syncWandStatus();
    return data;
  } catch (err) {
    return null;
  }
}

async function sendHeartbeat(page, mode) {
  try {
    const clientTime = Date.now();
    const { data, error } = await db.rpc('galaxy_heartbeat_v3', {
      p_user_id: me.id,
      p_session_hash: SESSION_HASH,
      p_browser_hash: BROWSER_HASH,
      p_page: page,
      p_mode: mode,
      p_client_time: clientTime
    });

    if (data && data.success === false && data.msg) {
      alert('⚠️ ' + data.msg);
      logout();
      return false;
    }

    if (data && data.added_orbs > 0) {
      toast(`🔮 Tus reactores produjeron +${fmt(data.added_orbs)} Orbes`);
      refresh();
    }

    return true;
  } catch (err) {
    return false;
  }
}

async function startPage(opts) {
  renderShell(opts.active);
  renderHUD(me);
  renderNav(state || {});

  const guard = s => {
    if (!s) return true;
    if (opts.needPlanet && !s.planet) {
      location.replace('lobby.html');
      return false;
    }
    if (opts.ownerOnly && !(s.planet && s.planet.is_owner)) {
      location.replace(s.planet ? 'planeta.html' : 'lobby.html');
      return false;
    }
    return true;
  };

  const s = await refresh();
  if (s && !guard(s)) return;
  if (s && opts.onState) opts.onState(s);

  setInterval(async () => {
    if (document.hidden) return;
    const n = await refresh();
    if (n && guard(n) && opts.onState) opts.onState(n);
  }, 8000);

  const page = opts.active.replace('.html', '');
  const pulse = async () => {
    if (document.hidden) return;
    await sendHeartbeat(page, isActive() ? 'tick' : 'idle');
  };

  const flush = async () => {
    try {
      await sendHeartbeat(page, 'flush');
    } catch (e) {}
  };

  pulse();
  setInterval(pulse, 5000);

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) flush();
    else pulse();
  });

  window.addEventListener('pagehide', flush);
  window.addEventListener('blur', flush);
  window.addEventListener('focus', pulse);
}