const state = {
  data: {
    accounts: [],
    transactions: [],
    online_players: [],
    investment_plans: [],
    investments: { items: [] },
    player: {}
  },
  activeFilter: 'all',
  charts: { net: null, split: null }
};

function nui(evt, payload = {}){
  try{
    const parent = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : null;
    if(parent){
      fetch(`https://${parent}/${evt}`, {
        method:'POST',
        headers:{ 'Content-Type':'application/json' },
        body: JSON.stringify(payload)
      });
    }
  }catch(err){ console.error(err); }
}

const money = n => '$' + Number(n || 0).toLocaleString(undefined,{ minimumFractionDigits:2, maximumFractionDigits:2 });
const setText = (id, value) => { const el = document.getElementById(id); if(el) el.textContent = value; };
const qs = sel => document.querySelector(sel);
const qsa = sel => Array.from(document.querySelectorAll(sel));

function shortAcct(value){
  const raw = String(value || '').replace(/\s+/g,'');
  if(!raw) return '—';
  return raw.length > 10 ? `${raw.slice(0,4)}••${raw.slice(-4)}` : raw;
}
function initial(name){ return (String(name || '?').trim()[0] || '?').toUpperCase(); }
function stamp(ts){ return ts ? new Date(Number(ts)*1000).toLocaleString() : '—'; }

function toast(type, text){
  const box = document.getElementById('toasts');
  const el = document.createElement('div');
  el.className = `toast ${type || 'info'}`;
  el.innerHTML = `<i class="fa-solid ${type === 'error' ? 'fa-circle-exclamation' : type === 'success' ? 'fa-circle-check' : 'fa-circle-info'}"></i><div>${text || ''}</div>`;
  box.appendChild(el);
  setTimeout(() => {
    el.style.opacity = '0';
    el.style.transform = 'translateY(-6px)';
    setTimeout(() => el.remove(), 250);
  }, 3200);
}

function showPage(id){
  qsa('.page').forEach(p => p.classList.toggle('active', p.id === id));
  qsa('.tab').forEach(t => t.classList.toggle('active', t.dataset.target === id));
  scheduleChartResize();
}

document.addEventListener('click', e => {
  const tab = e.target.closest('.tab');
  if(tab){ showPage(tab.dataset.target); }
  const jump = e.target.closest('[data-jump]');
  if(jump){ showPage(jump.dataset.jump); }
  const quick = e.target.closest('[data-recipient-server]');
  if(quick){
    const select = document.getElementById('playerRecipient');
    if(select){ select.value = quick.dataset.recipientServer; }
    showPage('page-transfer');
  }
  const filter = e.target.closest('.filter');
  if(filter){
    state.activeFilter = filter.dataset.filter || 'all';
    qsa('.filter').forEach(btn => btn.classList.toggle('active', btn === filter));
    renderActivityTable();
  }
});

function option(label, value){
  const o = document.createElement('option');
  o.textContent = label;
  o.value = value;
  return o;
}

function renderAccountSelect(el, includeCash = true){
  if(!el) return;
  const accounts = Array.isArray(state.data.accounts) ? state.data.accounts : [];
  el.innerHTML = '';
  if(includeCash) el.appendChild(option('Wallet Cash', 'cash'));
  accounts.forEach(a => {
    const name = `${String(a.type || 'account').replace(/^./, s => s.toUpperCase())} • ${money(a.balance)} • ${shortAcct(a.account_number)}`;
    el.appendChild(option(name, `acct:${a.id}`));
  });
}

function renderRecipients(){
  const list = document.getElementById('onlinePlayers');
  const select = document.getElementById('playerRecipient');
  const players = Array.isArray(state.data.online_players) ? state.data.online_players : [];
  setText('recipientCount', `${players.length} live`);
  list.innerHTML = '';
  select.innerHTML = '';
  select.appendChild(option('Select an online player', ''));
  players.forEach(p => {
    const row = document.createElement('div');
    row.className = 'person-chip';
    row.innerHTML = `
      <div class="person-meta">
        <div class="avatar">${initial(p.name)}</div>
        <div style="min-width:0">
          <div class="name">${p.name || 'Unknown'}</div>
          <div class="sub">CharID ${p.charid || '—'} · ID ${p.serverId || '—'}</div>
        </div>
      </div>
      <button class="quick-btn" data-recipient-server="${p.serverId}">Pay</button>
    `;
    list.appendChild(row);
    const label = `${p.name} • CharID ${p.charid} • ID ${p.serverId}`;
    const opt = option(label, String(p.serverId || ''));
    opt.dataset.charid = p.charid || '';
    select.appendChild(opt);
  });
  if(!players.length){
    list.innerHTML = '<div class="empty">No other online recipients right now.</div>';
  }
}

function txKind(type){
  const t = String(type || '').toLowerCase();
  if(t.includes('transfer')) return 'transfer';
  if(t.includes('deposit') || t.includes('withdraw')) return 'cash';
  if(t.includes('invest')) return 'invest';
  return 'other';
}

function txVisual(tx){
  const kind = txKind(tx.type);
  if(kind === 'transfer') return { icon:'fa-right-left', tone:'cyan' };
  if(kind === 'cash') return { icon:'fa-wallet', tone:'green' };
  if(kind === 'invest') return { icon:'fa-chart-line', tone:'violet' };
  return { icon:'fa-building-columns', tone:'cyan' };
}

function amountClass(tx){
  const value = Number(tx.amount || 0);
  if(String(tx.type || '').toLowerCase() === 'transfer_internal') return 'neutral';
  if(value > 0) return 'pos';
  if(value < 0) return 'neg';
  return 'neutral';
}

function recentActivityItems(){
  const wrap = document.getElementById('recentActivity');
  const txs = Array.isArray(state.data.transactions) ? state.data.transactions.slice(0, 6) : [];
  wrap.innerHTML = '';
  if(!txs.length){
    wrap.innerHTML = '<div class="empty">No activity has been logged yet.</div>';
    return;
  }
  txs.forEach(tx => {
    const visual = txVisual(tx);
    const item = document.createElement('div');
    item.className = 'activity-item';
    item.innerHTML = `
      <div class="activity-left">
        <div class="type-icon"><i class="fa-solid ${visual.icon}"></i></div>
        <div class="activity-copy">
          <div class="title">${tx.description || tx.type || 'Activity'}</div>
          <div class="meta">${String(tx.type || '').replace(/_/g,' ')} · ${stamp(tx.ts)}</div>
        </div>
      </div>
      <div class="amount ${amountClass(tx)}">${money(tx.amount)}</div>
    `;
    wrap.appendChild(item);
  });
}

function renderActivityTable(){
  const body = document.getElementById('activityRows');
  const txs = Array.isArray(state.data.transactions) ? state.data.transactions : [];
  body.innerHTML = '';
  const rows = txs.filter(tx => state.activeFilter === 'all' ? true : txKind(tx.type) === state.activeFilter);
  if(!rows.length){
    body.innerHTML = '<tr><td colspan="5"><div class="empty">No activity for this filter.</div></td></tr>';
    return;
  }
  rows.forEach(tx => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${tx.description || '—'}</td>
      <td>${String(tx.type || '—').replace(/_/g,' ')}</td>
      <td>${stamp(tx.ts)}</td>
      <td>${tx.counterparty || '—'}</td>
      <td style="text-align:right" class="amount ${amountClass(tx)}">${money(tx.amount)}</td>
    `;
    body.appendChild(tr);
  });
}

function renderProducts(){
  const grid = document.getElementById('productGrid');
  const select = document.getElementById('investmentPlan');
  const plans = Array.isArray(state.data.investment_plans) ? state.data.investment_plans : [];
  grid.innerHTML = '';
  select.innerHTML = '';
  plans.forEach(plan => {
    const card = document.createElement('section');
    card.className = 'product';
    card.style.setProperty('--accent', plan.color || 'rgba(85,204,255,.2)');
    card.innerHTML = `
      <div class="chips"><span class="chip">${plan.risk || 'Low'} Risk</span><span class="chip">${plan.durationHours || 0}h term</span></div>
      <h4>${plan.label || plan.code}</h4>
      <p>${plan.description || ''}</p>
      <div class="price">+${Number(plan.returnRate || 0).toFixed(1)}%</div>
      <div class="brand-sub">Min ${money(plan.min)} · Max ${money(plan.max)}</div>
    `;
    grid.appendChild(card);
    select.appendChild(option(`${plan.label} • +${Number(plan.returnRate || 0).toFixed(1)}% • ${plan.durationHours}h`, plan.code));
  });
}

function renderInvestments(){
  const info = state.data.investments || { items: [] };
  const items = Array.isArray(info.items) ? info.items : [];
  setText('activePrincipal', money(info.total_principal));
  setText('activeValue', money(info.total_value));
  setText('activePositions', String(info.active_count || 0));
  setText('maturedCountBadge', `${info.matured_count || 0} ready`);
  setText('heroInvestments', `${info.active_count || 0} positions`);
  const body = document.getElementById('investmentRows');
  body.innerHTML = '';
  if(!items.length){
    body.innerHTML = '<tr><td colspan="7"><div class="empty">No investment positions yet.</div></td></tr>';
    return;
  }
  items.forEach(inv => {
    const status = inv.status === 'closed' ? 'closed' : inv.matured ? 'matured' : 'live';
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${inv.plan_name || inv.plan_code}</td>
      <td>${inv.risk || '—'}</td>
      <td>${money(inv.principal)}</td>
      <td>${money(inv.payout)}</td>
      <td>${inv.status === 'closed' ? 'Collected' : stamp(inv.matures_ts)}</td>
      <td><span class="status ${status}">${inv.status === 'closed' ? 'Closed' : inv.matured ? 'Matured' : 'Active'}</span></td>
      <td>${inv.status !== 'closed' && inv.matured ? `<button class="btn secondary collect-btn" data-investment-id="${inv.id}" data-destination="checking">Collect</button>` : '—'}</td>
    `;
    body.appendChild(tr);
  });
}

function renderOverview(){
  const data = state.data || {};
  const accounts = Array.isArray(data.accounts) ? data.accounts : [];
  const checking = accounts.find(a => a.type === 'checking');
  const savings = accounts.find(a => a.type === 'savings');
  const portfolio = data.investments || { total_value: 0 };

  setText('brandName', data.brand?.appName || 'State Bank');
  setText('brandSupport', data.brand?.supportText || 'Premium digital banking');
  setText('playerName', data.player?.name || 'Citizen');
  setText('playerId', `CharID ${data.player?.charid || '—'}`);
  setText('sideNetWorth', money(data.net_worth));
  setText('heroNetWorth', money(data.net_worth));
  setText('walletCash', money(data.cash));
  setText('bankFunds', money(data.bank));
  setText('portfolioValue', money(portfolio.total_value));
  setText('statCash', money(data.cash));
  setText('statChecking', money(checking?.balance));
  setText('statSavings', money(savings?.balance));
  setText('statMonth', `${Number(data.month_change || 0) >= 0 ? '+' : '-'}${money(Math.abs(Number(data.month_change || 0)))}`);
  setText('monthSummary', `This Month ${Number(data.month_change || 0) >= 0 ? '+' : '-'}${money(Math.abs(Number(data.month_change || 0)))}`);
  setText('heroAccounts', `${accounts.length || 0} accounts`);
  setText('checkingAmount', money(checking?.balance));
  setText('savingsAmount', money(savings?.balance));
  setText('checkingAccountNo', shortAcct(checking?.account_number));
  setText('savingsAccountNo', shortAcct(savings?.account_number));
  recentActivityItems();
}

const clamp = (n, min, max) => Math.min(max, Math.max(min, n));
let pendingApplyData = null;
let applyFrame = 0;
let resizeFrame = 0;
const layout = { baseW: 1420, baseH: 860, minW: 980, minH: 640, margin: 18 };

function scheduleChartResize(){
  if(resizeFrame) cancelAnimationFrame(resizeFrame);
  resizeFrame = requestAnimationFrame(() => {
    resizeFrame = 0;
    Object.values(state.charts).forEach(ch => {
      try{ ch && ch.resize(); }catch(e){}
    });
  });
}

function syncLayout(){
  const width = clamp(layout.baseW, layout.minW, 2600);
  const height = clamp(layout.baseH, layout.minH, 1800);
  const safeW = Math.max(320, window.innerWidth - (layout.margin * 2));
  const safeH = Math.max(320, window.innerHeight - (layout.margin * 2));
  const scale = Math.min(1, safeW / width, safeH / height);
  document.documentElement.style.setProperty('--app-w', `${width}px`);
  document.documentElement.style.setProperty('--app-h', `${height}px`);
  document.documentElement.style.setProperty('--app-scale', String(Math.max(0.55, scale)));
  scheduleChartResize();
}

function queueApplyData(payload){
  pendingApplyData = payload || state.data;
  if(applyFrame) return;
  applyFrame = requestAnimationFrame(() => {
    applyFrame = 0;
    applyData(pendingApplyData || state.data);
    pendingApplyData = null;
  });
}

function chartLabelsDays(days){
  const list = []; const now = new Date(); now.setHours(0,0,0,0);
  for(let i=days-1;i>=0;i--){ const d = new Date(now); d.setDate(now.getDate()-i); list.push(d); }
  return list;
}

function buildCharts(){
  const txs = Array.isArray(state.data.transactions) ? state.data.transactions : [];
  const points = chartLabelsDays(30);
  const labels = points.map(d => d.toLocaleDateString(undefined,{ month:'short', day:'numeric' }));
  const daily = points.map(d => {
    const start = d.getTime() / 1000;
    const end = start + 86400;
    return txs.reduce((sum, tx) => {
      const ts = Number(tx.ts || 0);
      const neutral = String(tx.type || '') === 'transfer_internal';
      if(neutral || ts < start || ts >= end) return sum;
      return sum + Number(tx.amount || 0);
    }, 0);
  });

  const portfolioValue = Number(state.data.investments?.total_value || 0);
  const checking = Number((state.data.accounts || []).find(a => a.type === 'checking')?.balance || 0);
  const savings = Number((state.data.accounts || []).find(a => a.type === 'savings')?.balance || 0);
  const split = [Number(state.data.cash || 0), checking, savings, portfolioValue];

  Chart.defaults.color = '#eaf2ff';
  Chart.defaults.borderColor = 'rgba(255,255,255,.08)';
  Chart.defaults.font.family = 'Inter, system-ui, sans-serif';
  Chart.defaults.animation = false;

  const netCtx = document.getElementById('netChart');
  const splitCtx = document.getElementById('splitChart');

  if(state.charts.net){
    state.charts.net.data.labels = labels;
    state.charts.net.data.datasets[0].data = daily;
    state.charts.net.update('none');
  }else{
    state.charts.net = new Chart(netCtx, {
      type:'line',
      data:{ labels, datasets:[{
        label:'Net flow', data:daily, fill:true, tension:.28, borderWidth:2,
        borderColor:'#55ccff', backgroundColor:'rgba(85,204,255,.14)', pointRadius:0, pointHoverRadius:3
      }]},
      options:{
        maintainAspectRatio:false,
        animation:false,
        plugins:{ legend:{ display:false } },
        scales:{
          x:{ grid:{ display:false }, ticks:{ color:'#8da0bc' } },
          y:{ ticks:{ color:'#8da0bc' }, grid:{ color:'rgba(255,255,255,.08)' } }
        }
      }
    });
  }

  if(state.charts.split){
    state.charts.split.data.datasets[0].data = split;
    state.charts.split.update('none');
  }else{
    state.charts.split = new Chart(splitCtx, {
      type:'doughnut',
      data:{
        labels:['Wallet','Checking','Savings','Portfolio'],
        datasets:[{ data:split, backgroundColor:['rgba(234,242,255,.3)','rgba(85,204,255,.55)','rgba(117,228,166,.55)','rgba(156,140,255,.55)'], borderWidth:1, borderColor:'rgba(255,255,255,.08)' }]
      },
      options:{
        maintainAspectRatio:false,
        animation:false,
        cutout:'62%',
        plugins:{ legend:{ position:'bottom', labels:{ color:'#8da0bc', boxWidth:12, boxHeight:12 } } }
      }
    });
  }
}

function applyData(payload){
  state.data = payload || state.data;
  renderOverview();
  renderRecipients();
  renderProducts();
  renderInvestments();
  renderActivityTable();
  renderAccountSelect(document.getElementById('playerTransferSource'), true);
  renderAccountSelect(document.getElementById('internalFrom'), true);
  renderAccountSelect(document.getElementById('internalTo'), true);
  renderAccountSelect(document.getElementById('depositTo'), false);
  renderAccountSelect(document.getElementById('withdrawFrom'), false);
  renderAccountSelect(document.getElementById('investmentSource'), true);
  buildCharts();
}

window.addEventListener('message', e => {
  const m = e.data || {};
  if(m.action === 'show'){
    document.body.style.display = 'block';
    syncLayout();
    showPage('page-overview');
    nui('getData');
    return;
  }
  if(m.action === 'hide'){
    document.body.style.display = 'none';
    return;
  }
  if(m.action === 'refreshData') return nui('getData');
  if(m.action === 'setData') return queueApplyData(m.data || {});
  if(m.action === 'notify' && m.payload) return toast(m.payload.type || 'info', m.payload.text || '');
  if(m.action === 'transferResult' && m.payload){
    toast(m.payload.success ? 'success' : 'error', m.payload.success ? 'Transfer completed.' : (m.payload.error || 'Transfer failed.'));
    if(m.payload.success) nui('getData');
    return;
  }
  if(m.accounts || m.transactions) return queueApplyData(m);
});

document.addEventListener('keydown', e => {
  if(e.key === 'Escape'){
    document.body.style.display = 'none';
    nui('close');
  }
});

document.addEventListener('click', e => {
  const collect = e.target.closest('.collect-btn');
  if(collect){
    nui('investCollect', { id:Number(collect.dataset.investmentId), to: collect.dataset.destination || 'checking' });
  }
});

function once(key, fn){
  window.__busy = window.__busy || {};
  if(window.__busy[key]) return;
  window.__busy[key] = true;
  try{ fn(); } finally { setTimeout(() => { window.__busy[key] = false; }, 700); }
}

function bindActions(){
  document.getElementById('sendPlayerTransfer')?.addEventListener('click', () => once('p2p', () => {
    const select = document.getElementById('playerRecipient');
    const selected = select.options[select.selectedIndex];
    const payload = {
      targetServerId: Number(select.value || 0) || undefined,
      targetCharId: (document.getElementById('manualRecipient').value || '').trim() || (selected?.dataset?.charid || ''),
      from: document.getElementById('playerTransferSource').value,
      destination: document.getElementById('playerTransferDestination').value,
      amount: Number(document.getElementById('playerTransferAmount').value || 0),
      description: document.getElementById('playerTransferNote').value || ''
    };
    nui('transferPlayer', payload);
  }));

  document.getElementById('clearPlayerTransfer')?.addEventListener('click', () => {
    ['manualRecipient','playerTransferAmount','playerTransferNote'].forEach(id => { const el = document.getElementById(id); if(el) el.value = ''; });
    const sel = document.getElementById('playerRecipient'); if(sel) sel.value = '';
  });

  document.getElementById('sendInternalTransfer')?.addEventListener('click', () => once('internal', () => {
    nui('transferInternal', {
      from: document.getElementById('internalFrom').value,
      to: document.getElementById('internalTo').value,
      amount: Number(document.getElementById('internalAmount').value || 0),
      description: document.getElementById('internalNote').value || ''
    });
  }));

  document.getElementById('submitDeposit')?.addEventListener('click', () => once('deposit', () => {
    nui('deposit', {
      to: document.getElementById('depositTo').value,
      amount: Number(document.getElementById('depositAmount').value || 0),
      description: document.getElementById('depositNote').value || ''
    });
  }));

  document.getElementById('submitWithdraw')?.addEventListener('click', () => once('withdraw', () => {
    nui('withdraw', {
      from: document.getElementById('withdrawFrom').value,
      amount: Number(document.getElementById('withdrawAmount').value || 0),
      description: document.getElementById('withdrawNote').value || ''
    });
  }));

  document.getElementById('openInvestment')?.addEventListener('click', () => once('invest', () => {
    nui('investOpen', {
      plan: document.getElementById('investmentPlan').value,
      source: document.getElementById('investmentSource').value,
      amount: Number(document.getElementById('investmentAmount').value || 0)
    });
  }));
}

(function initResizer(){
  const handle = document.querySelector('.resize');
  let sx = 0, sy = 0, sw = 0, sh = 0, dragging = false;

  function point(ev){
    if(ev.touches && ev.touches[0]) return { x: ev.touches[0].clientX, y: ev.touches[0].clientY };
    return { x: ev.clientX, y: ev.clientY };
  }

  function onDown(ev){
    ev.preventDefault();
    dragging = true;
    const p = point(ev);
    sx = p.x; sy = p.y; sw = layout.baseW; sh = layout.baseH;
    document.addEventListener('mousemove', onMove);
    document.addEventListener('mouseup', onUp);
  }

  function onMove(ev){
    if(!dragging) return;
    const p = point(ev);
    layout.baseW = clamp(sw + (p.x - sx), layout.minW, 2400);
    layout.baseH = clamp(sh + (p.y - sy), layout.minH, 1600);
    syncLayout();
  }

  function onUp(){
    dragging = false;
    document.removeEventListener('mousemove', onMove);
    document.removeEventListener('mouseup', onUp);
    scheduleChartResize();
  }

  handle?.addEventListener('mousedown', onDown);
  window.addEventListener('resize', syncLayout, { passive:true });
  syncLayout();
})();

document.addEventListener('DOMContentLoaded', () => {
  bindActions();
  syncLayout();
});
