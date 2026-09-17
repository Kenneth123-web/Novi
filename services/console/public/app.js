const app = document.getElementById("app");

const captcha = { enabled: false, sitekey: "" };

const state = {
  authed: false,
  view: "overview",
  error: "",
  busy: false,
  turnstileToken: "",
  stats: null,
  users: [],
  usersTotal: 0,
  q: "",
  selected: null,
  usage: [],
  usageTotal: 0,
  usageKind: "",
};

async function api(path, opts = {}) {
  const res = await fetch(path, {
    credentials: "same-origin",
    headers: { "content-type": "application/json", ...(opts.headers || {}) },
    ...opts,
  });
  if (res.status === 204) return null;
  const text = await res.text();
  let body = {};
  try { body = text ? JSON.parse(text) : {}; } catch { body = { raw: text }; }
  if (!res.ok) {
    const err = new Error(body.error?.message || res.statusText);
    err.status = res.status;
    throw err;
  }
  return body;
}

function fmt(n) {
  return new Intl.NumberFormat("en-US").format(n ?? 0);
}

function when(iso) {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString();
}

function escapeHtml(s) {
  return String(s ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function render() {
  if (!state.authed) {
    app.innerHTML = `
      <div class="login">
        <form class="login-card" id="login">
          <div class="mark"></div>
          <h1>Novi console</h1>
          <p>Accounts, logins, and API usage.</p>
          <label for="password">Password</label>
          <input id="password" name="password" type="password" autocomplete="current-password" autofocus />
          ${captcha.enabled ? `<div id="turnstile-slot" class="turnstile"></div>` : ""}
          <button class="btn btn-primary" ${state.busy ? "disabled" : ""}>Sign in</button>
          <div class="note">${escapeHtml(state.error)}</div>
        </form>
      </div>`;
    document.getElementById("login").onsubmit = onLogin;
    if (captcha.enabled && window.turnstile) {
      const slot = document.getElementById("turnstile-slot");
      if (slot) {
        window.turnstile.render(slot, {
          sitekey: captcha.sitekey,
          action: "turnstile-spin-v1",
          callback: (token) => { state.turnstileToken = token; },
          "error-callback": () => { state.turnstileToken = ""; },
          "expired-callback": () => { state.turnstileToken = ""; },
        });
      }
    }
    return;
  }

  const nav = (id, label) =>
    `<button class="nav ${state.view === id ? "active" : ""}" data-view="${id}">${label}</button>`;

  app.innerHTML = `
    <div class="shell">
      <aside class="side">
        <div class="brand">Novi</div>
        ${nav("overview", "Overview")}
        ${nav("users", "Users")}
        ${nav("usage", "API usage")}
        <div class="spacer"></div>
        <button class="nav" id="logout">Sign out</button>
      </aside>
      <main class="main">${main()}</main>
    </div>`;

  app.querySelectorAll("[data-view]").forEach((el) => {
    el.onclick = () => show(el.dataset.view);
  });
  const logout = document.getElementById("logout");
  if (logout) logout.onclick = onLogout;
  bindMain();
}

function main() {
  if (state.view === "overview") return overview();
  if (state.view === "users") return usersView();
  if (state.view === "user") return userView();
  return usageView();
}

function overview() {
  const s = state.stats || {};
  const max = Math.max(1, ...(s.requests_by_day || []).map((d) => d.n));
  const bars = (s.requests_by_day || [])
    .map(
      (d) =>
        `<div class="bar" style="height:${Math.round((d.n / max) * 100)}%">
           <span>${escapeHtml(d.day.slice(5))}</span>
         </div>`,
    )
    .join("");
  const paths = (s.top_paths || [])
    .map(
      (p) =>
        `<tr><td class="mono">${escapeHtml(p.path)}</td><td class="mono">${fmt(p.n)}</td></tr>`,
    )
    .join("");
  return `
    <h2>Overview</h2>
    <p class="sub">Last 24 hours, unless a chart says otherwise.</p>
    <div class="grid">
      <div class="stat"><div class="k">USERS</div><div class="v">${fmt(s.users)}</div></div>
      <div class="stat"><div class="k">ACTIVE</div><div class="v">${fmt(s.active_users)}</div></div>
      <div class="stat"><div class="k">LOGINS 24H</div><div class="v">${fmt(s.logins_24h)}</div></div>
      <div class="stat"><div class="k">REQUESTS 24H</div><div class="v">${fmt(s.requests_24h)}</div></div>
      <div class="stat"><div class="k">AI IN TOKENS</div><div class="v">${fmt(s.ai_input_tokens_24h)}</div></div>
      <div class="stat"><div class="k">AI OUT TOKENS</div><div class="v">${fmt(s.ai_output_tokens_24h)}</div></div>
    </div>
    <h2>Requests this week</h2>
    <p class="sub">UTC days.</p>
    <div class="card"><div class="bars">${bars || "<p class='sub' style='padding:16px'>No traffic yet.</p>"}</div></div>
    <h2 style="margin-top:28px">Top paths</h2>
    <div class="card"><table><thead><tr><th>PATH</th><th>COUNT</th></tr></thead><tbody>${paths}</tbody></table></div>
  `;
}

function usersView() {
  const rows = state.users
    .map(
      (u) => `
      <tr class="clickable" data-user="${escapeHtml(u.id)}">
        <td>${escapeHtml(u.display_name || u.username)}</td>
        <td>${escapeHtml(u.email)}</td>
        <td class="mono">${escapeHtml(u.source)}</td>
        <td>${u.is_active ? '<span class="pill pill-on">active</span>' : '<span class="pill pill-off">disabled</span>'}</td>
        <td class="mono">${fmt(u.login_count)}</td>
        <td class="mono">${when(u.last_login_at)}</td>
      </tr>`,
    )
    .join("");
  return `
    <h2>Users</h2>
    <p class="sub">${fmt(state.usersTotal)} accounts stored on Cloudflare.</p>
    <div class="toolbar">
      <input type="search" id="q" placeholder="Search email, username, id" value="${escapeHtml(state.q)}" />
    </div>
    <div class="card">
      <table>
        <thead><tr><th>NAME</th><th>EMAIL</th><th>SOURCE</th><th>STATUS</th><th>LOGINS</th><th>LAST LOGIN</th></tr></thead>
        <tbody>${rows || '<tr><td colspan="6">No accounts yet.</td></tr>'}</tbody>
      </table>
    </div>`;
}

function userView() {
  const d = state.selected;
  if (!d) return `<p class="sub">Loading…</p>`;
  const u = d.user;
  const events = (d.login_events || [])
    .map(
      (e) =>
        `<tr><td>${escapeHtml(e.event)}</td><td class="mono">${escapeHtml(e.source)}</td><td class="mono">${when(e.created_at)}</td></tr>`,
    )
    .join("");
  const usage = (state.usage || [])
    .map(
      (e) =>
        `<tr>
           <td class="mono">${escapeHtml(e.method)}</td>
           <td class="mono">${escapeHtml(e.path)}</td>
           <td>${e.kind === "ai" ? '<span class="pill pill-ai">ai</span>' : escapeHtml(e.kind)}</td>
           <td class="mono">${e.status}</td>
           <td class="mono">${e.input_tokens ?? "—"} / ${e.output_tokens ?? "—"}</td>
           <td class="mono">${when(e.created_at)}</td>
         </tr>`,
    )
    .join("");
  return `
    <button class="btn btn-quiet" id="back">← Users</button>
    <h2>${escapeHtml(u.display_name || u.username)}</h2>
    <p class="sub">${escapeHtml(u.email)} · ${escapeHtml(u.id)}</p>
    <div class="actions">
      ${
        u.is_active
          ? `<button class="btn btn-danger" id="disable">Disable login</button>`
          : `<button class="btn btn-ok" id="enable">Enable login</button>`
      }
    </div>
    <div class="detail">
      <div class="card" style="padding:8px 16px 16px">
        <div class="kv">
          <div><b>Username</b><span>${escapeHtml(u.username)}</span></div>
          <div><b>Status</b><span>${u.is_active ? "active" : "disabled"}</span></div>
          <div><b>Admin</b><span>${u.is_admin ? "yes" : "no"}</span></div>
          <div><b>Source</b><span>${escapeHtml(u.source)}</span></div>
          <div><b>Created</b><span>${when(u.created_at)}</span></div>
          <div><b>Last login</b><span>${when(u.last_login_at)}</span></div>
          <div><b>Logins</b><span>${fmt(u.login_count)}</span></div>
          <div><b>HTTP calls</b><span>${fmt(d.usage?.n)}</span></div>
          <div><b>AI calls</b><span>${fmt(d.usage?.ai)}</span></div>
          <div><b>Tokens in/out</b><span>${fmt(d.usage?.input_tokens)} / ${fmt(d.usage?.output_tokens)}</span></div>
        </div>
      </div>
      <div class="card">
        <table>
          <thead><tr><th>EVENT</th><th>SOURCE</th><th>WHEN</th></tr></thead>
          <tbody>${events || "<tr><td colspan='3'>No login events.</td></tr>"}</tbody>
        </table>
      </div>
    </div>
    <h2 style="margin-top:28px">API usage</h2>
    <p class="sub">${fmt(state.usageTotal)} recorded calls.</p>
    <div class="card">
      <table>
        <thead><tr><th>METHOD</th><th>PATH</th><th>KIND</th><th>STATUS</th><th>TOKENS</th><th>WHEN</th></tr></thead>
        <tbody>${usage || "<tr><td colspan='6'>No usage yet.</td></tr>"}</tbody>
      </table>
    </div>`;
}

function usageView() {
  const rows = (state.usage || [])
    .map(
      (e) =>
        `<tr>
           <td class="mono">${escapeHtml((e.user_id || "—").slice(0, 8))}</td>
           <td class="mono">${escapeHtml(e.method)}</td>
           <td class="mono">${escapeHtml(e.path)}</td>
           <td>${e.kind === "ai" ? '<span class="pill pill-ai">ai</span>' : escapeHtml(e.kind)}</td>
           <td class="mono">${e.status}</td>
           <td class="mono">${e.latency_ms ?? 0}</td>
           <td class="mono">${e.input_tokens ?? "—"} / ${e.output_tokens ?? "—"}</td>
           <td class="mono">${when(e.created_at)}</td>
         </tr>`,
    )
    .join("");
  return `
    <h2>API usage</h2>
    <p class="sub">${fmt(state.usageTotal)} events stored on Cloudflare.</p>
    <div class="toolbar">
      <button class="btn ${state.usageKind === "" ? "btn-primary" : "btn-quiet"}" data-kind="" style="width:auto">All</button>
      <button class="btn ${state.usageKind === "http" ? "btn-primary" : "btn-quiet"}" data-kind="http" style="width:auto">HTTP</button>
      <button class="btn ${state.usageKind === "ai" ? "btn-primary" : "btn-quiet"}" data-kind="ai" style="width:auto">AI</button>
    </div>
    <div class="card">
      <table>
        <thead><tr><th>USER</th><th>METHOD</th><th>PATH</th><th>KIND</th><th>STATUS</th><th>MS</th><th>TOKENS</th><th>WHEN</th></tr></thead>
        <tbody>${rows || "<tr><td colspan='8'>No usage yet.</td></tr>"}</tbody>
      </table>
    </div>`;
}

function bindMain() {
  const q = document.getElementById("q");
  if (q) {
    q.onkeydown = (ev) => {
      if (ev.key === "Enter") {
        state.q = q.value;
        loadUsers();
      }
    };
  }
  app.querySelectorAll("[data-user]").forEach((row) => {
    row.onclick = () => openUser(row.dataset.user);
  });
  const back = document.getElementById("back");
  if (back) back.onclick = () => show("users");
  const disable = document.getElementById("disable");
  if (disable) disable.onclick = () => setActive(false);
  const enable = document.getElementById("enable");
  if (enable) enable.onclick = () => setActive(true);
  app.querySelectorAll("[data-kind]").forEach((el) => {
    el.onclick = () => {
      state.usageKind = el.dataset.kind;
      loadUsage();
    };
  });
}

async function onLogin(ev) {
  ev.preventDefault();
  state.busy = true;
  state.error = "";
  render();
  try {
    const password = ev.target.password.value;
    const token = state.turnstileToken
      || ev.target.querySelector('[name="cf-turnstile-response"]')?.value
      || "";
    await api("/api/admin/login", {
      method: "POST",
      body: JSON.stringify({ password, turnstile_token: token }),
    });
    state.authed = true;
    await show("overview");
  } catch (e) {
    state.error = e.message || "Could not sign in";
    state.authed = false;
    render();
  } finally {
    state.busy = false;
  }
}

async function onLogout() {
  try { await api("/api/admin/logout", { method: "POST" }); } catch { /* still leave */ }
  state.authed = false;
  state.selected = null;
  render();
}

async function show(view) {
  state.view = view;
  render();
  if (view === "overview") await loadStats();
  if (view === "users") await loadUsers();
  if (view === "usage") await loadUsage();
}

async function loadStats() {
  state.stats = await api("/api/admin/stats");
  if (state.view === "overview") render();
}

async function loadUsers() {
  const q = state.q ? `&q=${encodeURIComponent(state.q)}` : "";
  const body = await api(`/api/admin/users?limit=100${q}`);
  state.users = body.users;
  state.usersTotal = body.total;
  if (state.view === "users") render();
}

async function openUser(id) {
  state.view = "user";
  state.selected = null;
  render();
  state.selected = await api(`/api/admin/users/${id}`);
  const usage = await api(`/api/admin/users/${id}/usage?limit=80`);
  state.usage = usage.events;
  state.usageTotal = usage.total;
  render();
}

async function setActive(is_active) {
  const id = state.selected.user.id;
  state.selected = await api(`/api/admin/users/${id}`, {
    method: "PATCH",
    body: JSON.stringify({ is_active }),
  });
  render();
}

async function loadUsage() {
  const kind = state.usageKind ? `&kind=${encodeURIComponent(state.usageKind)}` : "";
  const body = await api(`/api/admin/usage?limit=120${kind}`);
  state.usage = body.events;
  state.usageTotal = body.total;
  if (state.view === "usage") render();
}

async function boot() {
  try {
    const cfg = await api("/api/captcha");
    captcha.enabled = Boolean(cfg.enabled && cfg.sitekey);
    captcha.sitekey = cfg.sitekey || "";
  } catch { /* widget stays off; server still fail-closes when configured */ }
  try {
    await api("/api/admin/me");
    state.authed = true;
    await show("overview");
  } catch {
    state.authed = false;
    render();
  }
}

boot();
