let resource = (() => {
  try { if (typeof GetParentResourceName === 'function') return GetParentResourceName(); } catch (e) {}
  try { if (window.parent && typeof window.parent.GetParentResourceName === 'function') return window.parent.GetParentResourceName(); } catch (e) {}
  try { if (window.parent && typeof window.parent.AzFrameworkGetResourceName === 'function') return window.parent.AzFrameworkGetResourceName(); } catch (e) {}
  return 'Az-Framework';
})();

const root = document.getElementById('chat-root');
const stack = document.getElementById('message-stack');
const inputShell = document.getElementById('input-shell');
const input = document.getElementById('chat-input');
const emojiToggle = document.getElementById('emoji-toggle');
const emojiPicker = document.getElementById('emoji-picker');
const suggestionsEl = document.getElementById('suggestions');

let maxMessages = 150;
let fadeAfterMs = 18000;
let messageTimers = new WeakMap();
let suggestions = {};
let activeSuggestions = [];
let activeSuggestionIndex = 0;
let visibilityMode = 'always';
let isChatOpen = false;
let inputHistory = [];
let historyIndex = -1;
let historyDraft = '';
let refocusTimer = null;

function refocusInputSoon(delay = 25) {
  if (!isChatOpen) return;
  if (refocusTimer) clearTimeout(refocusTimer);
  refocusTimer = setTimeout(() => {
    if (!isChatOpen) return;
    const active = document.activeElement;
    const inEmoji = !!(active && emojiPicker && emojiPicker.contains(active));
    const inSuggestions = !!(active && suggestionsEl && suggestionsEl.contains(active));
    if (active === input || active === emojiToggle || inEmoji || inSuggestions) return;
    try {
      input.focus();
      input.setSelectionRange(input.value.length, input.value.length);
    } catch (e) {}
  }, delay);
}

let inputHistoryMax = 50;

function normalizeVisibilityMode(mode) {
  const normalized = String(mode || '').toLowerCase();
  return ['active', 'disabled', 'always'].includes(normalized) ? normalized : 'always';
}

function applyVisibilityState() {
  visibilityMode = normalizeVisibilityMode(visibilityMode);
  root.classList.toggle('chat-open', !!isChatOpen);
  root.dataset.visibilityMode = visibilityMode;

  const hideStack = visibilityMode === 'disabled' || (!isChatOpen && visibilityMode === 'active');
  stack.classList.toggle('stack-hidden', hideStack);
}

function setVisibility(nextMode, nextOpenState) {
  if (nextMode != null) visibilityMode = normalizeVisibilityMode(nextMode);
  if (nextOpenState != null) isChatOpen = !!nextOpenState;
  applyVisibilityState();
}

function isNearBottom(element, threshold = 18) {
  if (!element) return true;
  return (element.scrollHeight - element.clientHeight - element.scrollTop) <= threshold;
}

function scrollToBottom(force = false) {
  if (!stack) return;
  if (force || isNearBottom(stack, 40)) {
    stack.scrollTop = stack.scrollHeight;
  }
}

const aliasMap = {
  ':smile:': '😄',
  ':grin:': '😁',
  ':joy:': '😂',
  ':sob:': '😭',
  ':heart:': '❤️',
  ':thumbsup:': '👍',
  ':thumbsdown:': '👎',
  ':fire:': '🔥',
  ':100:': '💯',
  ':eyes:': '👀',
  ':wave:': '👋',
  ':ok:': '👌',
  ':clap:': '👏',
  ':pray:': '🙏',
  ':skull:': '💀',
  ':laugh:': '🤣',
  ':thinking:': '🤔',
  ':salute:': '🫡',
  ':rocket:': '🚀'
};

function post(name, data = {}) {
  return fetch(`https://${resource}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data)
  }).catch(() => {});
}

function applyStyleVars(style = {}) {
  const map = {
    chatWidth: '--chat-width',
    maxWidth: '--chat-max-width',
    inputWidth: '--input-width',
    inputMaxWidth: '--input-max-width',
    top: '--top',
    left: '--left',
    accent: '--accent',
    text: '--text',
    textMuted: '--muted',
    bubble: '--bubble',
    bubbleBorder: '--bubble-border',
    inputBg: '--input-bg',
    inputBorder: '--input-border',
    shadow: '--shadow',
    fontFamily: '--font',
    success: '--success',
    warning: '--warning',
    danger: '--danger',
    info: '--info',
    stackMaxHeight: '--stack-max-height',
    roleIconSize: '--role-icon-size'
  };

  Object.entries(map).forEach(([key, cssVar]) => {
    if (style[key] != null) {
      document.documentElement.style.setProperty(cssVar, String(style[key]));
    }
  });

  if (style.messageGap != null) {
    document.documentElement.style.setProperty('--gap', String(style.messageGap));
  }
}

function applyAliases(text) {
  let out = String(text || '');
  Object.entries(aliasMap).forEach(([alias, emoji]) => {
    out = out.split(alias).join(emoji);
  });
  return out;
}

function clearFadeTimer(node) {
  const timer = messageTimers.get(node);
  if (timer) {
    clearTimeout(timer);
  }
}

function scheduleFade(node) {
  clearFadeTimer(node);
  const timer = setTimeout(() => {
    node.classList.add('fade');
  }, fadeAfterMs);
  messageTimers.set(node, timer);
}

function pruneMessages() {
  while (stack.children.length > maxMessages) {
    const first = stack.firstElementChild;
    clearFadeTimer(first);
    first.remove();
  }
}

function addMessage(message) {
  if (!message || !message.html) return;

  const shouldStick = isNearBottom(stack, 40);
  const node = document.createElement('div');
  node.className = 'message';
  node.innerHTML = message.html;
  stack.appendChild(node);

  pruneMessages();
  scheduleFade(node);
  if (shouldStick) {
    scrollToBottom(true);
  }
}

function clearMessages(keepLast = 0) {
  const amount = Math.max(0, Number(keepLast) || 0);
  const nodes = [...stack.children];
  const keep = amount > 0 ? nodes.slice(-amount) : [];

  nodes.forEach((node) => {
    if (!keep.includes(node)) {
      clearFadeTimer(node);
      node.remove();
    }
  });

  scrollToBottom(true);
}

function setSuggestions(nextSuggestions) {
  suggestions = nextSuggestions || {};
  renderSuggestions();
}

function getMatchingSuggestions() {
  const value = input.value.trim();
  if (!value.startsWith('/')) return [];

  const query = value.toLowerCase();
  return Object.values(suggestions)
    .filter((entry) => entry && entry.name && entry.name.toLowerCase().startsWith(query))
    .sort((a, b) => a.name.localeCompare(b.name))
    .slice(0, 6);
}

function renderSuggestions() {
  activeSuggestions = getMatchingSuggestions();
  if (!activeSuggestions.length) {
    suggestionsEl.classList.add('hidden');
    suggestionsEl.innerHTML = '';
    activeSuggestionIndex = 0;
    return;
  }

  activeSuggestionIndex = Math.min(activeSuggestionIndex, activeSuggestions.length - 1);
  suggestionsEl.classList.remove('hidden');
  suggestionsEl.innerHTML = '';

  activeSuggestions.forEach((entry, index) => {
    const wrap = document.createElement('div');
    wrap.className = `suggestion ${index === activeSuggestionIndex ? 'active' : ''}`;

    const params = Array.isArray(entry.params) && entry.params.length
      ? entry.params.map((item) => item?.name ? `<${item.name}>` : '').filter(Boolean).join(' ')
      : '';

    wrap.innerHTML = `
      <div class="suggestion-name">${entry.name}</div>
      <div class="suggestion-help">${entry.help || ''}</div>
      ${params ? `<div class="suggestion-params">${params}</div>` : ''}
    `;

    suggestionsEl.appendChild(wrap);
  });
}

function applyActiveSuggestion() {
  const current = activeSuggestions[activeSuggestionIndex];
  if (!current) return;
  input.value = `${current.name} `;
  renderSuggestions();
}

function rememberSubmittedInput(text) {
  const value = String(text || '').trim();
  if (!value) return;

  if (!inputHistory.length || inputHistory[inputHistory.length - 1] !== value) {
    inputHistory.push(value);
    if (inputHistory.length > inputHistoryMax) {
      inputHistory = inputHistory.slice(-inputHistoryMax);
    }
  }

  historyIndex = -1;
  historyDraft = '';
}

function applyHistoryEntry(step) {
  if (!inputHistory.length) return false;

  if (historyIndex === -1) {
    historyDraft = input.value;
    historyIndex = inputHistory.length;
  }

  historyIndex = Math.max(0, Math.min(inputHistory.length, historyIndex + step));

  if (historyIndex >= inputHistory.length) {
    input.value = historyDraft;
    historyIndex = -1;
  } else {
    input.value = inputHistory[historyIndex] || '';
  }

  input.focus();
  input.setSelectionRange(input.value.length, input.value.length);
  renderSuggestions();
  return true;
}

function openInput(prefill = '') {
  isChatOpen = true;
  historyIndex = -1;
  historyDraft = prefill || '';
  inputShell.classList.remove('hidden');
  input.value = prefill || '';
  input.focus();
  input.setSelectionRange(input.value.length, input.value.length);
  renderSuggestions();
  applyVisibilityState();
  refocusInputSoon(0);
}

function closeInput() {
  isChatOpen = false;
  historyIndex = -1;
  historyDraft = '';
  inputShell.classList.add('hidden');
  suggestionsEl.classList.add('hidden');
  emojiPicker.classList.add('hidden');
  input.value = '';
  applyVisibilityState();
  if (refocusTimer) { clearTimeout(refocusTimer); refocusTimer = null; }
}

function insertAtCaret(text) {
  const start = input.selectionStart ?? input.value.length;
  const end = input.selectionEnd ?? input.value.length;
  input.value = `${input.value.slice(0, start)}${text}${input.value.slice(end)}`;
  const next = start + text.length;
  input.focus();
  input.setSelectionRange(next, next);
  renderSuggestions();
}

function buildEmojiPicker(list = []) {
  emojiPicker.innerHTML = '';
  list.forEach((emoji) => {
    const button = document.createElement('button');
    button.className = 'emoji-btn';
    button.type = 'button';
    button.textContent = emoji;
    button.addEventListener('click', () => insertAtCaret(emoji));
    emojiPicker.appendChild(button);
  });
}

window.addEventListener('message', (event) => {
  const data = event.data || {};

  if (data.type === 'azfw_set_resource' && data.resource) {
    resource = data.resource;
    return;
  }

  switch (data.action) {
    case 'bootstrap':
      maxMessages = Number(data.maxMessages) || maxMessages;
      fadeAfterMs = Number(data.fadeAfterMs) || fadeAfterMs;
      inputHistoryMax = Math.max(1, Number(data.inputHistoryMax) || inputHistoryMax);
      applyStyleVars(data.style || {});
      buildEmojiPicker(data.emojiPicker || []);
      setSuggestions(data.suggestions || {});
      setVisibility(data.visibilityMode, data.chatOpen);
      scrollToBottom(true);
      break;
    case 'open':
      if (Array.isArray(data.emojiPicker)) buildEmojiPicker(data.emojiPicker);
      if (data.suggestions) setSuggestions(data.suggestions);
      if (data.visibilityMode != null || data.chatOpen != null) {
        setVisibility(data.visibilityMode, true);
      }
      openInput(data.prefill || '');
      requestAnimationFrame(() => { try { input.focus(); input.setSelectionRange(input.value.length, input.value.length); } catch (e) {} });
      break;
    case 'close':
      closeInput();
      break;
    case 'message':
      addMessage(data.message);
      refocusInputSoon();
      break;
    case 'clear':
      clearMessages(data.keepLast || 0);
      break;
    case 'suggestions':
      setSuggestions(data.suggestions || {});
      break;
    case 'visibility':
      setVisibility(data.visibilityMode, data.chatOpen);
      break;
  }
});

emojiToggle.addEventListener('click', () => {
  emojiPicker.classList.toggle('hidden');
  input.focus();
});

input.addEventListener('input', () => {
  input.value = applyAliases(input.value);
  renderSuggestions();
});

input.addEventListener('blur', () => {
  refocusInputSoon();
});

input.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') {
    event.preventDefault();
    post('azchat:close');
    return;
  }

  if (event.key === 'ArrowUp') {
    event.preventDefault();
    if (applyHistoryEntry(-1)) return;
    return;
  }

  if (event.key === 'ArrowDown') {
    event.preventDefault();
    if (historyIndex !== -1) {
      applyHistoryEntry(1);
      return;
    }
    if (activeSuggestions.length) {
      activeSuggestionIndex = (activeSuggestionIndex + 1) % activeSuggestions.length;
      renderSuggestions();
      return;
    }
    return;
  }

  if (event.key === 'Tab' && activeSuggestions.length) {
    event.preventDefault();
    applyActiveSuggestion();
    return;
  }

  if (event.key === 'Enter') {
    event.preventDefault();
    const text = input.value.trim();
    if (text) {
      rememberSubmittedInput(text);
    }
    post('azchat:submit', { text });
  }
});

window.addEventListener('focus', () => {
  refocusInputSoon();
});

document.addEventListener('visibilitychange', () => {
  if (!document.hidden) refocusInputSoon();
});

window.addEventListener('DOMContentLoaded', () => {
  applyVisibilityState();
  post('azchat:ready');
});
