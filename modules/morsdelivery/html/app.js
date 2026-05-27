const app = document.getElementById('app');
const list = document.getElementById('list');
const search = document.getElementById('search');
const closeBtn = document.getElementById('close');
const btnClose = document.getElementById('btnClose');
const cooldownEl = document.getElementById('cooldown');

let vehicles = [];
let okToCall = true;
let cooldown = 0;
let accent = '#e63946';

function post(name, data = {}) {
  fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data)
  });
}

function setVisible(v) {
  if (v) app.classList.remove('hidden');
  else app.classList.add('hidden');
}

function setTheme(a) {
  accent = a || accent;
  document.documentElement.style.setProperty('--accent', accent);
}

function isParked(row) {

  if (row.parked === undefined || row.parked === null) return true;
  return Number(row.parked) === 1;
}

function rowMatches(row, q) {
  if (!q) return true;
  q = q.toLowerCase();
  return String(row.model || '').toLowerCase().includes(q) || String(row.plate || '').toLowerCase().includes(q);
}

function render() {
  const q = (search.value || '').trim();
  list.innerHTML = '';

  const filtered = vehicles.filter(v => rowMatches(v, q));
  if (!filtered.length) {
    const empty = document.createElement('div');
    empty.className = 'card';
    empty.innerHTML = `<div class="meta"><div class="model">No vehicles</div><div class="plate">Nothing matched your search.</div></div>`;
    list.appendChild(empty);
    return;
  }

  for (const v of filtered) {
    const card = document.createElement('div');
    card.className = 'card';

    const left = document.createElement('div');
    left.className = 'meta';
    left.innerHTML = `
      <div class="model">${escapeHtml(v.model || 'Unknown')}</div>
      <div class="plate">PLATE • ${escapeHtml((v.plate || '').toUpperCase())}</div>
    `;

    const right = document.createElement('div');
    right.className = 'badges';

    const badge = document.createElement('div');
    const parked = isParked(v);
    badge.className = 'badge ' + (parked ? 'ok' : 'out');
    badge.textContent = parked ? 'Parked' : 'Unparked';

    const btn = document.createElement('button');
    btn.className = 'btn';
    btn.textContent = 'Call';
    btn.disabled = !okToCall || !parked;
    btn.onclick = () => {
      post('requestDelivery', { plate: (v.plate || '').toUpperCase() });
    };

    right.appendChild(badge);
    right.appendChild(btn);

    card.appendChild(left);
    card.appendChild(right);
    list.appendChild(card);
  }
}

function escapeHtml(str) {
  return String(str)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

window.addEventListener('message', (e) => {
  const msg = e.data || {};
  if (msg.type === 'setVisible') {
    setVisible(!!msg.visible);
  }
  if (msg.type === 'setTheme') {
    setTheme(msg.accent);
  }
  if (msg.type === 'setData') {
    okToCall = !!msg.ok;
    cooldown = Number(msg.cooldown || 0);
    vehicles = Array.isArray(msg.vehicles) ? msg.vehicles : [];
    cooldownEl.textContent = okToCall ? 'Ready' : `Cooldown: ${cooldown}s`;
    render();
  }
});

search.addEventListener('input', render);
closeBtn.addEventListener('click', () => post('morsClose'));
btnClose.addEventListener('click', () => post('morsClose'));

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') post('morsClose');
});
