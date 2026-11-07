/* RHCSA Study Kit: a small hash-routed single-page app over window.KIT (built by tools/build-site.py). */
(function () {
  "use strict";
  const KIT = window.KIT;
  const app = document.getElementById("app");
  const sidebar = document.getElementById("sidebar");
  const searchBox = document.getElementById("search");
  const REPO_URL = "https://github.com/Braden-Develops/rhcsa-lab-kit";

  /* ---------- storage (per-browser progress) ---------- */
  const STORE_KEY = "rhcsa-kit-v1";
  let state = { obj: {}, labs: {}, best: {}, checks: {}, read: {}, theme: null };
  try { Object.assign(state, JSON.parse(localStorage.getItem(STORE_KEY) || "{}")); } catch (e) {}
  state.read = state.read || {};
  function save() { try { localStorage.setItem(STORE_KEY, JSON.stringify(state)); } catch (e) {} }

  /* ---------- helpers ---------- */
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const labById = (id) => KIT.labs.find((l) => l.id === id);
  const sections = KIT.guide.sections;
  const numbered = sections.filter((s) => s.num);
  const lectures = KIT.lectures || [];
  const lectureByNum = (n) => lectures.find((l) => l.num === n);
  const readMins = (l) => Math.max(1, Math.round(l.words / 200));
  const slugId = (t) => t.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  const allObjectives = KIT.objectives.groups.flatMap((g) => g.items);
  const objDone = (items) => items.filter((o) => state.obj[o.id]).length;
  const labsDone = () => KIT.labs.filter((l) => state.labs[l.id] === "done").length;
  const pct = (a, b) => (b ? Math.round((a / b) * 100) : 0);
  const fmtTime = (s) => { s = Math.max(0, Math.floor(s)); const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
    return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(x).padStart(2, "0"); };

  marked.setOptions({ gfm: true, breaks: false });

  /* Render Markdown, then decorate: tables scroll, code gets highlight + copy, kit paths become links. */
  function md(src, opts) {
    const wrap = document.createElement("div");
    wrap.className = "md";
    wrap.innerHTML = marked.parse(src || "");
    wrap.querySelectorAll("table").forEach((t) => {
      const w = document.createElement("div"); w.className = "table-wrap"; t.replaceWith(w); w.appendChild(t);
    });
    wrap.querySelectorAll("pre code").forEach((c) => {
      const lang = (c.className.match(/language-(\S+)/) || [])[1];
      if (!lang || !hljs.getLanguage(lang)) { c.className = c.className.replace(/language-\S+/, ""); c.classList.add("language-bash"); }
      try { hljs.highlightElement(c); } catch (e) {}
      const b = document.createElement("button"); b.className = "copy-btn"; b.textContent = "Copy";
      b.onclick = () => { navigator.clipboard?.writeText(c.innerText).then(() => { b.textContent = "Copied"; setTimeout(() => (b.textContent = "Copy"), 1200); }); };
      c.parentElement.appendChild(b);
    });
    wrap.querySelectorAll(":not(pre) > code").forEach((c) => {
      const t = c.textContent.trim();
      let href = null;
      const m = t.match(/^labs\/(\d\d)-[\w-]+\/?(\w+\.md)?$/);
      if (m && labById(m[1])) href = "#/lab/" + m[1];
      else if (t === "STUDY-GUIDE.md") href = "#/guide";
      else if (/^lectures\/(\d\d)-[\w-]+\.md$/.test(t) && lectureByNum(String(+t.slice(9, 11)))) href = "#/lecture/" + (+t.slice(9, 11));
      else if (t === "OBJECTIVES.md") href = "#/objectives";
      else if (t === "README.md") href = "#/setup";
      if (href) { const a = document.createElement("a"); a.href = href; c.replaceWith(a); a.appendChild(c); }
    });
    // Task-list checkboxes become persistent when a key is given.
    if (opts && opts.checkKey) {
      wrap.querySelectorAll('li > input[type="checkbox"]').forEach((cb, i) => {
        const k = opts.checkKey + ":" + i;
        cb.disabled = false; cb.checked = !!state.checks[k];
        cb.onchange = () => { state.checks[k] = cb.checked; save(); };
      });
    }
    return wrap;
  }

  /* Link lab numbers in an objective's "Lab task(s)" cell: "01 task 2; 05 task 8" */
  function linkLabs(text) {
    return esc(text).replace(/\b(0\d|1[01])\b(?=\s*tasks?\b)/g, (m) => labById(m) ? `<a href="#/lab/${m}">Lab ${m}</a>` : m);
  }

  function el(html) { const d = document.createElement("div"); d.innerHTML = html.trim(); return d.firstElementChild; }

  /* ---------- sidebar ---------- */
  function renderSidebar(route) {
    const active = (h) => (route === h ? " active" : "");
    const done = objDone(allObjectives);
    let h = `<div class="nav-group">
      <a class="nav-link${active("#/")}" href="#/">Overview</a>
      <a class="nav-link${active("#/setup")}" href="#/setup">Set up the labs</a>
      <a class="nav-link${active("#/objectives")}" href="#/objectives"><span class="nav-text">Objectives checklist</span><span class="nav-num">${done}/${allObjectives.length}</span></a>
      <div class="mini-bar"><i style="width:${pct(done, allObjectives.length)}%"></i></div>
    </div>
    `;
    if (lectures.length) {
      h += `<div class="nav-group"><div class="nav-label"><span>Lectures</span><span>${lectures.filter((l) => state.read[l.num]).length}/${lectures.length}</span></div>`;
      for (const l of lectures) h += `<a class="nav-link${active("#/lecture/" + l.num)}" href="#/lecture/${l.num}"><span class="nav-num">${l.num}</span><span class="nav-text">${esc(l.title)}</span>${state.read[l.num] ? '<span class="dot done"></span>' : ""}</a>`;
      h += `</div>`;
    }
    h += `<div class="nav-group"><div class="nav-label">Study guide (quick reference)</div>`;
    for (const s of sections) {
      h += `<a class="nav-link${active("#/guide/" + s.slug)}" href="#/guide/${s.slug}"><span class="nav-num">${s.num ? s.num : "•"}</span><span class="nav-text">${esc(s.title)}</span></a>`;
    }
    h += `</div><div class="nav-group"><div class="nav-label"><span>Labs</span><span>${labsDone()}/${KIT.labs.length}</span></div>`;
    for (const l of KIT.labs) {
      const st = state.labs[l.id] || "todo";
      h += `<a class="nav-link${active("#/lab/" + l.id)}" href="#/lab/${l.id}"><span class="nav-num">${l.id}</span><span class="nav-text">${esc(shortTitle(l.title))}</span><span class="dot ${st}"></span></a>`;
    }
    h += `</div>`;
    sidebar.innerHTML = h;
  }
  function shortTitle(t) { return t.split(/[:(]/)[0].trim(); }

  /* ---------- pages ---------- */
  function pageHome() {
    const done = objDone(allObjectives), ld = labsDone();
    const finalSec = sections.find((s) => /final-week/.test(s.slug));
    const finalItems = finalSec ? (finalSec.body.match(/^- \[ \]/gm) || []).length : 0;
    const finalDone = finalSec ? Object.keys(state.checks).filter((k) => k.startsWith("guide:" + finalSec.slug + ":") && state.checks[k]).length : 0;
    const groups = Object.fromEntries(KIT.objectives.groups.map((g) => [g.num, g]));
    let rows = "";
    for (const s of numbered) {
      const g = groups[s.num];
      const od = g ? objDone(g.items) : 0, ot = g ? g.items.length : 0;
      rows += `<div class="card section-row">
        <div class="n">${s.num}</div>
        <div><a class="t" href="#/guide/${s.slug}">${esc(s.title)}</a><div class="s">${od}/${ot} objectives checked off</div></div>
        <div class="links">${lectureByNum(s.num) ? `<a class="pill" href="#/lecture/${s.num}">${state.read[s.num] ? "✓ " : ""}Lecture</a>` : ""}${s.labs.map((id) => { const st = state.labs[id]; return `<a class="pill" href="#/lab/${id}">${st === "done" ? "✓ " : ""}Lab ${id}</a>`; }).join("")}</div>
      </div>`;
    }
    app.innerHTML = `
      <div class="eyebrow">EX200 · RHEL 10</div>
      <h1>${esc(KIT.guide.title)}</h1>
      <p class="lede">The 62 official objectives, long-form lectures that explain how each part of the system works, a quick-reference study guide with the commands and traps, and 11 hands-on labs with broken scenarios,
      an automatic grader and worked solutions. Your progress is saved in this browser.</p>
      <div class="grid cols-3">
        <a class="card" href="#/objectives" style="color:inherit;text-decoration:none"><div class="stat-num">${done}<span class="stat-label"> / ${allObjectives.length}</span></div><div class="stat-label">objectives checked off</div><div class="bar"><i style="width:${pct(done, allObjectives.length)}%"></i></div></a>
        <a class="card" href="#/labs" style="color:inherit;text-decoration:none"><div class="stat-num">${ld}<span class="stat-label"> / ${KIT.labs.length}</span></div><div class="stat-label">labs passing</div><div class="bar"><i style="width:${pct(ld, KIT.labs.length)}%"></i></div></a>
        <a class="card" href="#/guide/${finalSec ? finalSec.slug : ""}" style="color:inherit;text-decoration:none"><div class="stat-num">${finalDone}<span class="stat-label"> / ${finalItems}</span></div><div class="stat-label">final-week drills done</div><div class="bar"><i style="width:${pct(finalDone, finalItems)}%"></i></div></a>
      </div>
      <div class="btn-row">
        <a class="btn primary" href="${lectures.length ? "#/lecture/" + lectures[0].num : "#/guide/" + sections[0].slug}">Start reading</a>
        <a class="btn" href="#/setup">Set up the labs</a>
        <a class="btn" href="${REPO_URL}/archive/refs/heads/main.zip">Download the kit (.zip)</a>
      </div>
      <h2>Exam sections</h2>
      <div class="section-list">${rows}</div>
      <h2>How to study</h2>`;
    const how = KIT.readme.split(/^## /m).find((p) => /^Suggested study plan/.test(p));
    if (how) app.appendChild(md(how.replace(/^.*\n/, "")));
    app.appendChild(el(`<div class="footer">Progress lives in this browser only. <a href="#" id="resetAll">Reset all progress</a></div>`));
    document.getElementById("resetAll").onclick = (e) => { e.preventDefault(); if (confirm("Clear all checkboxes, lab statuses and best times?")) { state = { obj: {}, labs: {}, best: {}, checks: {}, read: {}, theme: state.theme }; save(); route(); } };
  }

  function pageSetup() {
    app.innerHTML = `<div class="eyebrow">Getting started</div>`;
    const body = KIT.readme.replace(/^# .*\n/, "");
    app.appendChild(el(`<h1>Set up the lab kit</h1>`));
    app.appendChild(el(`<div class="btn-row"><a class="btn primary" href="${REPO_URL}/archive/refs/heads/main.zip">Download the kit (.zip)</a><a class="btn" href="${REPO_URL}">View on GitHub</a></div>`));
    app.appendChild(md(body));
  }

  function pageGuideIndex() {
    app.innerHTML = `<div class="eyebrow">Study guide</div><h1>${esc(KIT.guide.title)}</h1>`;
    app.appendChild(md(KIT.guide.intro));
    const list = el(`<div class="section-list"></div>`);
    for (const s of sections) list.appendChild(el(`<a class="card section-row" href="#/guide/${s.slug}" style="color:inherit;text-decoration:none"><div class="n">${s.num || "•"}</div><div class="t">${esc(s.title)}</div><div></div></a>`));
    app.appendChild(list);
  }

  function pageGuide(slug) {
    const i = sections.findIndex((s) => s.slug === slug);
    if (i < 0) return pageGuideIndex();
    const s = sections[i];
    app.innerHTML = `<div class="eyebrow">Study guide${s.num ? " · Section " + s.num : ""}</div><h1>${esc(s.title)}</h1>`;
    const lec = s.num && lectureByNum(s.num);
    if (lec) app.appendChild(el(`<div class="callout">This page is the quick reference. For the full explanation of how it all works, read <a href="#/lecture/${lec.num}">Lecture ${lec.num}: ${esc(lec.title)}</a> (about ${readMins(lec)} min).</div>`));
    if (s.labs.length) {
      app.appendChild(el(`<div class="btn-row">${s.labs.map((id) => { const l = labById(id); return `<a class="btn" href="#/lab/${id}">Practice: Lab ${id} · ${esc(shortTitle(l.title))} <span class="badge ${l.runtime}">${l.runtime === "vm" ? "VM" : "container"}</span></a>`; }).join("")}</div>`));
    }
    if (i === 0) app.appendChild(md(KIT.guide.intro));
    app.appendChild(md(s.body, { checkKey: "guide:" + s.slug }));
    const g = KIT.objectives.groups.find((x) => x.num === s.num);
    if (g) {
      app.appendChild(el(`<h2>Check yourself</h2>`));
      app.appendChild(el(`<p class="lede" style="margin-bottom:12px">Tick an objective when you can do it from memory, without the guide.</p>`));
      app.appendChild(objList(g));
    }
    app.appendChild(pager(i > 0 && sections[i - 1], sections[i + 1], (x) => "#/guide/" + x.slug, (x) => (x.num ? x.num + ". " : "") + x.title));
  }

  function pageLectureIndex() {
    app.innerHTML = `<div class="eyebrow">Lectures</div><h1>Lectures</h1>
      <p class="lede">Long-form reading, one lecture per exam section, organised by the official objective numbers. Each one explains what is going on underneath the commands, so you can reason your way through a task you have never seen. Read a lecture, skim the quick reference, then do the lab.</p>`;
    const list = el(`<div class="section-list"></div>`);
    for (const l of lectures) list.appendChild(el(`<a class="card section-row" href="#/lecture/${l.num}" style="color:inherit;text-decoration:none"><div class="n">${l.num}</div><div><div class="t">${esc(l.title)}</div><div class="s">about ${readMins(l)} min · ${l.words.toLocaleString()} words</div></div><div>${state.read[l.num] ? '<span class="badge done">✓ read</span>' : ""}</div></a>`));
    app.appendChild(list);
  }

  function pageLecture(num) {
    const i = lectures.findIndex((l) => l.num === num);
    if (i < 0) return pageLectureIndex();
    const l = lectures[i];
    const sec = numbered.find((s) => s.num === l.num);
    app.innerHTML = `<div class="eyebrow">Lecture ${l.num} · about ${readMins(l)} min read</div><h1>${esc(l.title)}</h1>`;
    const btns = [];
    if (sec) btns.push(`<a class="btn" href="#/guide/${sec.slug}">Quick reference</a>`);
    if (sec) for (const id of sec.labs) { const lb = labById(id); btns.push(`<a class="btn" href="#/lab/${id}">Practice: Lab ${id} · ${esc(shortTitle(lb.title))} <span class="badge ${lb.runtime}">${lb.runtime === "vm" ? "VM" : "container"}</span></a>`); }
    if (btns.length) app.appendChild(el(`<div class="btn-row">${btns.join("")}</div>`));
    const body = md(l.body, { checkKey: "lecture:" + l.num });
    const heads = [...body.querySelectorAll("h2")];
    const used = {};
    body.querySelectorAll("h2, h3").forEach((h) => { let id = "lec-" + slugId(h.textContent); used[id] = (used[id] || 0) + 1; if (used[id] > 1) id += "-" + used[id]; h.id = id; });
    if (heads.length > 2) {
      const toc = el(`<details class="spoiler toc" open><summary>Contents</summary><div class="inner"><ol></ol></div></details>`);
      for (const h of heads) {
        const a = el(`<li><a href="#">${esc(h.textContent)}</a></li>`);
        a.querySelector("a").onclick = (e) => { e.preventDefault(); h.scrollIntoView({ behavior: "smooth" }); };
        toc.querySelector("ol").appendChild(a);
      }
      app.appendChild(toc);
    }
    app.appendChild(body);
    const g = KIT.objectives.groups.find((x) => x.num === l.num);
    if (g) {
      app.appendChild(el(`<h2>Check yourself</h2>`));
      app.appendChild(el(`<p class="lede" style="margin-bottom:12px">Tick an objective when you can do it from memory, without the guide.</p>`));
      app.appendChild(objList(g));
    }
    const mark = el(`<div class="btn-row"><button class="btn${state.read[l.num] ? "" : " primary"}" id="markRead">${state.read[l.num] ? "✓ Read (click to undo)" : "Mark lecture as read"}</button></div>`);
    mark.querySelector("button").onclick = () => { if (state.read[l.num]) delete state.read[l.num]; else state.read[l.num] = true; save(); pageLecture(num); renderSidebar(location.hash); };
    app.appendChild(mark);
    app.appendChild(pager(i > 0 && lectures[i - 1], lectures[i + 1], (x) => "#/lecture/" + x.num, (x) => "Lecture " + x.num + " · " + x.title));
  }

  function objList(g) {
    const ul = el(`<ul class="obj-list"></ul>`);
    for (const o of g.items) {
      const li = el(`<li class="obj${state.obj[o.id] ? " checked" : ""}"><input type="checkbox" ${state.obj[o.id] ? "checked" : ""} aria-label="${esc(o.id)}"><span class="oid">${esc(o.id)}</span>
        <span class="otext"><span>${esc(o.text)}</span><span class="olabs">Practice: ${linkLabs(o.labs)}</span></span></li>`);
      const cb = li.querySelector("input");
      const toggle = (v) => { state.obj[o.id] = v; if (!v) delete state.obj[o.id]; save(); li.classList.toggle("checked", v); cb.checked = v; renderSidebar(location.hash || "#/"); updateCount(); };
      cb.onclick = (e) => { e.stopPropagation(); toggle(cb.checked); };
      li.onclick = (e) => { if (e.target.closest("a")) return; toggle(!cb.checked); };
      ul.appendChild(li);
    }
    return ul;
  }
  function updateCount() {
    document.querySelectorAll("[data-group-count]").forEach((n) => {
      const g = KIT.objectives.groups.find((x) => x.num === n.dataset.groupCount);
      n.textContent = `${objDone(g.items)} / ${g.items.length}`;
    });
    const tot = document.getElementById("objTotal");
    if (tot) { const d = objDone(allObjectives); tot.textContent = `${d} of ${allObjectives.length} checked off`; document.getElementById("objBar").style.width = pct(d, allObjectives.length) + "%"; }
  }

  function pageObjectives() {
    app.innerHTML = `<div class="eyebrow">Checklist</div><h1>EX200 objectives</h1>
      <div class="card" style="margin:12px 0 20px"><div style="display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap"><b id="objTotal"></b>
      <a href="#" id="objClear" style="font-size:13px">Clear checklist</a></div><div class="bar"><i id="objBar"></i></div></div>`;
    app.appendChild(md(KIT.objectives.intro));
    for (const g of KIT.objectives.groups) {
      const sec = numbered.find((s) => s.num === g.num);
      const box = el(`<section class="obj-group"><div class="obj-head"><h2>${g.num}. ${sec ? `<a href="#/guide/${sec.slug}">${esc(g.title)}</a>` : esc(g.title)}</h2><span class="count" data-group-count="${g.num}"></span></div></section>`);
      box.appendChild(objList(g));
      app.appendChild(box);
    }
    if (KIT.objectives.notes) app.appendChild(md(KIT.objectives.notes));
    updateCount();
    document.getElementById("objClear").onclick = (e) => { e.preventDefault(); if (confirm("Uncheck all 62 objectives?")) { state.obj = {}; save(); route(); } };
  }

  function pageLabs() {
    app.innerHTML = `<div class="eyebrow">Hands-on</div><h1>Labs</h1>
      <p class="lede">Each lab builds a scenario with working parts to configure and broken parts to fix, then grades you. Container labs run under Podman or Docker; VM labs need Vagrant because they touch the kernel, the bootloader or real disks.</p>`;
    const grid = el(`<div class="lab-cards"></div>`);
    for (const l of KIT.labs) {
      const st = state.labs[l.id];
      grid.appendChild(el(`<a class="card lab-card" href="#/lab/${l.id}"><div class="top"><span class="id">${l.id}</span>
        <span>${st === "done" ? '<span class="badge done">✓ passing</span> ' : ""}<span class="badge ${l.runtime}">${l.runtime === "vm" ? "VM" : "container"}</span></span></div>
        <div class="title">${esc(l.title)}</div>${state.best[l.id] ? `<div class="stat-label">Best time ${fmtTime(state.best[l.id])}</div>` : ""}</a>`));
    }
    app.appendChild(grid);
  }

  let timer = null;
  function pageLab(id) {
    const i = KIT.labs.findIndex((l) => l.id === id);
    if (i < 0) return pageLabs();
    const l = KIT.labs[i];
    const hasVars = /\{\{\w+\}\}/.test(l.tasks);
    const tasks = l.tasks.replace(/^# .*\n/, "").replace(/\*\*(\w+) = \{\{\1\}\}\*\*/g, "<var>$1</var>").replace(/\{\{(\w+)\}\}/g, "<var>$1</var>");
    const heading = (l.tasks.match(/^# (.*)/) || [, l.title])[1];
    app.innerHTML = `<div class="eyebrow">Lab ${l.id}</div>
      <div class="lab-head"><h1>${esc(heading.replace(/^Lab \d\d:\s*/, ""))}</h1></div>
      <div class="lab-head"><span class="badge ${l.runtime}">${l.runtime === "vm" ? "Runs in the VM" : "Runs in a container"}</span><code>labs/${esc(l.dir)}</code></div>
      <div class="card toolbar">
        <div class="seg" id="status">${[["todo", "Not started"], ["progress", "In progress"], ["done", "Passing"]].map(([v, t]) => `<button data-v="${v}" class="${(state.labs[l.id] || "todo") === v ? "on" : ""}">${t}</button>`).join("")}</div>
        <div class="timer"><span class="best" id="best"></span><span class="clock" id="clock">0:00</span>
          <button class="btn" id="tStart">Start timer</button><button class="btn" id="tStop" title="Stop and record">Stop</button></div>
      </div>`;
    const cmds = "```bash\n./lab start " + l.id + "     # build and boot the scenario, print the tasks\n./lab shell " + l.id + "     # root shell" +
      (l.runtime === "vm" ? " (vagrant ssh + sudo -i)" : "") + "\n./lab check " + l.id + "     # grade yourself, as often as you like\n./lab reset " + l.id + "     # start over\n```";
    app.appendChild(md(cmds));
    if (l.runtime === "vm") app.appendChild(el(`<div class="callout vm">This lab needs the Vagrant VM (real kernel, disks or bootloader). The grader re-checks after a reboot, so reboot before you call it done. See <a href="#/setup">setup</a>.</div>`));
    app.appendChild(el(`<h2>Tasks</h2>`));
    if (hasVars) app.appendChild(el(`<p class="callout">Boxed names such as <var>DISK1</var> or <var>IFACE</var> are placeholders: <code>./lab tasks ${l.id}</code> (or <code>sudo labctl tasks</code> in the VM) prints them with your VM's real device names.</p>`));
    app.appendChild(md(tasks));

    const sol = el(`<details class="spoiler solution"><summary>Show the solution <span class="hint">Try first. Grade with ./lab check ${l.id}.</span></summary><div class="inner"></div></details>`);
    sol.querySelector(".inner").appendChild(md(l.solution.replace(/^# .*\n/, "")));
    app.appendChild(sol);
    const files = Object.entries(l.files);
    if (files.length) {
      const f = el(`<details class="spoiler"><summary>Lab internals <span class="hint">setup and grader scripts (spoilers: they reveal what's broken)</span></summary><div class="inner"></div></details>`);
      for (const [name, src] of files) {
        f.querySelector(".inner").appendChild(el(`<h3><code>${esc(name)}</code></h3>`));
        f.querySelector(".inner").appendChild(md("```" + (name === "Dockerfile" ? "dockerfile" : "bash") + "\n" + src.replace(/```/g, "ˋˋˋ") + "\n```"));
      }
      app.appendChild(f);
    }
    const sec = numbered.filter((s) => s.labs.includes(l.id));
    if (sec.length) app.appendChild(el(`<p>Read first: ${sec.map((s) => `<a href="#/guide/${s.slug}">Section ${s.num}, ${esc(s.title)}</a>`).join(" · ")}</p>`));
    app.appendChild(pager(i > 0 && KIT.labs[i - 1], KIT.labs[i + 1], (x) => "#/lab/" + x.id, (x) => "Lab " + x.id + " · " + shortTitle(x.title)));

    // status
    app.querySelectorAll("#status button").forEach((b) => (b.onclick = () => {
      state.labs[l.id] = b.dataset.v; save();
      app.querySelectorAll("#status button").forEach((x) => x.classList.toggle("on", x === b));
      renderSidebar(location.hash);
    }));
    // timer: a stopwatch for timed redo runs; best time kept per lab
    const clock = document.getElementById("clock"), best = document.getElementById("best");
    const showBest = () => (best.textContent = state.best[l.id] ? "best " + fmtTime(state.best[l.id]) : "");
    showBest();
    let t0 = null;
    if (timer) clearInterval(timer);
    document.getElementById("tStart").onclick = (e) => {
      if (t0) { t0 = null; clearInterval(timer); e.target.textContent = "Start timer"; clock.textContent = "0:00"; return; }
      t0 = Date.now(); e.target.textContent = "Reset";
      timer = setInterval(() => (clock.textContent = fmtTime((Date.now() - t0) / 1000)), 500);
    };
    document.getElementById("tStop").onclick = () => {
      if (!t0) return;
      const secs = Math.floor((Date.now() - t0) / 1000); clearInterval(timer); t0 = null;
      document.getElementById("tStart").textContent = "Start timer";
      clock.textContent = fmtTime(secs);
      if (!state.best[l.id] || secs < state.best[l.id]) { state.best[l.id] = secs; save(); showBest(); }
    };
  }

  function pager(prev, next, href, label) {
    return el(`<nav class="pager">${prev ? `<a href="${href(prev)}"><small>← Previous</small>${esc(label(prev))}</a>` : ""}${next ? `<a class="next" href="${href(next)}"><small>Next →</small>${esc(label(next))}</a>` : ""}</nav>`);
  }

  /* ---------- search ---------- */
  const index = [];
  (function buildIndex() {
    const add = (where, title, href, text) => text.split(/\n/).forEach((line) => { if (line.trim()) index.push({ where, title, href, line }); });
    for (const l of lectures) add("Lecture " + l.num, l.title, "#/lecture/" + l.num, l.body);
    for (const s of sections) add("Study guide", s.title, "#/guide/" + s.slug, s.body);
    for (const o of allObjectives) index.push({ where: "Objective " + o.id, title: o.text, href: "#/objectives", line: o.text + " (lab " + o.labs + ")" });
    for (const l of KIT.labs) { add("Lab " + l.id + " tasks", l.title, "#/lab/" + l.id, l.tasks); add("Lab " + l.id + " solution", l.title, "#/lab/" + l.id, l.solution); }
    add("Setup", "Set up the lab kit", "#/setup", KIT.readme);
  })();
  const clean = (s) => s.replace(/<br>/g, " ").replace(/\\\|/g, "\u0001").replace(/^\s*[-*] \[[ x]\]\s*/, "").replace(/[*`|]/g, " ").replace(/\u0001/g, "|").replace(/\s+/g, " ").trim();
  function pageSearch(q) {
    const terms = q.toLowerCase().split(/\s+/).filter(Boolean);
    app.innerHTML = `<div class="eyebrow">Search</div><h1>“${esc(q)}”</h1>`;
    if (!terms.length) return;
    const hits = index.filter((r) => { const t = r.line.toLowerCase(); return terms.every((w) => t.includes(w)); });
    const seen = new Set(), out = [];
    for (const h of hits) { const k = h.href + "|" + h.line; if (!seen.has(k)) { seen.add(k); out.push(h); } if (out.length >= 80) break; }
    if (!out.length) { app.appendChild(el(`<p class="empty">No matches. Try a command name such as <code>semanage</code>, <code>nmcli</code> or <code>lvextend</code>.</p>`)); return; }
    app.appendChild(el(`<p class="lede">${hits.length > 80 ? "First 80 of " + hits.length : out.length} matching lines</p>`));
    const re = new RegExp("(" + terms.map((t) => t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|") + ")", "gi");
    for (const r of out) {
      let snip = clean(r.line); if (snip.length > 220) { const at = Math.max(0, snip.toLowerCase().indexOf(terms[0]) - 60); snip = (at ? "…" : "") + snip.slice(at, at + 220) + "…"; }
      app.appendChild(el(`<a class="card result" href="${r.href}"><div class="where">${esc(r.where)} · ${esc(shortTitle(r.title))}</div><div class="snip">${esc(snip).replace(re, "<mark>$1</mark>")}</div></a>`));
    }
  }
  let searchT;
  searchBox.addEventListener("input", () => {
    clearTimeout(searchT);
    searchT = setTimeout(() => { const q = searchBox.value.trim(); if (q) location.hash = "#/search/" + encodeURIComponent(q); else if (location.hash.startsWith("#/search/")) location.hash = "#/"; }, 200);
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === "/" && document.activeElement !== searchBox && !/input|textarea/i.test(document.activeElement.tagName)) { e.preventDefault(); searchBox.focus(); }
    if (e.key === "Escape" && document.activeElement === searchBox) { searchBox.value = ""; searchBox.blur(); }
  });

  /* ---------- theme ---------- */
  function applyTheme() {
    const root = document.documentElement;
    if (state.theme) root.setAttribute("data-theme", state.theme); else root.removeAttribute("data-theme");
    const dark = state.theme ? state.theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
    document.getElementById("hl-light").disabled = dark;
    document.getElementById("hl-dark").disabled = !dark;
  }
  document.getElementById("themeBtn").onclick = () => {
    const dark = state.theme ? state.theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
    state.theme = dark ? "light" : "dark"; save(); applyTheme();
  };
  matchMedia("(prefers-color-scheme: dark)").addEventListener?.("change", applyTheme);
  applyTheme();

  /* ---------- mobile nav ---------- */
  document.getElementById("menuBtn").onclick = () => document.body.classList.toggle("nav-open");
  document.getElementById("scrim").onclick = () => document.body.classList.remove("nav-open");

  /* ---------- router ---------- */
  function route() {
    if (timer) { clearInterval(timer); timer = null; }
    const h = location.hash || "#/";
    const [, page, arg] = h.match(/^#\/([^/]*)\/?(.*)$/) || [];
    document.body.classList.remove("nav-open");
    let navKey = h;
    if (page === "search") { const q = decodeURIComponent(arg); if (searchBox.value.trim() !== q) searchBox.value = q; pageSearch(q); }
    else if (page === "lecture" && arg) pageLecture(arg);
    else if (page === "lecture" || page === "lectures") pageLectureIndex();
    else if (page === "guide" && arg) pageGuide(arg);
    else if (page === "guide") pageGuideIndex();
    else if (page === "objectives") pageObjectives();
    else if (page === "labs") pageLabs();
    else if (page === "lab") pageLab(arg);
    else if (page === "setup") pageSetup();
    else { pageHome(); navKey = "#/"; }
    renderSidebar(navKey);
    const t = app.querySelector("h1");
    document.title = (t && navKey !== "#/" ? t.textContent + " · " : "") + "RHCSA Study Kit";
    if (page !== "search") window.scrollTo(0, 0);
    const a = sidebar.querySelector(".active"); if (a) a.scrollIntoView({ block: "nearest" });
    buildRail(["lecture", "guide", "lab"].includes(page) && arg ? page : null);
  }

  /* ---------- right rail (wide screens): "on this page" with scroll-spy ---------- */
  const rail = document.getElementById("rail");
  let spy = null;
  function buildRail(kind) {
    if (spy) { spy.disconnect(); spy = null; }
    rail.innerHTML = "";
    let heads = [...app.querySelectorAll(".md h2")];
    if (heads.length < 3) heads = [...app.querySelectorAll(".md h2, .md h3")];
    heads = heads.filter((h) => !h.closest("details:not(.toc)"));
    const on = !!kind && heads.length >= 2;
    document.querySelector(".layout").classList.toggle("has-rail", on);
    if (!on) return;
    const used = {};
    heads.forEach((h) => { if (!h.id) { let id = "h-" + slugId(h.textContent); used[id] = (used[id] || 0) + 1; if (used[id] > 1) id += "-" + used[id]; h.id = id; } });
    const box = el(`<div class="rail-box"><div class="rail-label">On this page</div><nav class="rail-toc"></nav></div>`);
    const nav = box.querySelector("nav");
    const links = new Map();
    for (const h of heads) {
      const a = el(`<a href="#" class="${h.tagName === "H3" ? "sub" : ""}">${esc(h.textContent)}</a>`);
      a.onclick = (e) => { e.preventDefault(); h.scrollIntoView({ behavior: "smooth" }); };
      nav.appendChild(a); links.set(h, a);
    }
    const top = el(`<a href="#" class="rail-top">↑ Back to top</a>`);
    top.onclick = (e) => { e.preventDefault(); window.scrollTo({ top: 0, behavior: "smooth" }); };
    box.appendChild(top);
    rail.appendChild(box);
    let current = null;
    const visible = new Set();
    spy = new IntersectionObserver((entries) => {
      entries.forEach((en) => (en.isIntersecting ? visible.add(en.target) : visible.delete(en.target)));
      let pick = heads.find((h) => visible.has(h));
      if (!pick) pick = [...heads].reverse().find((h) => h.getBoundingClientRect().top < 120) || heads[0];
      if (pick !== current) {
        if (current) links.get(current).classList.remove("on");
        current = pick; const a = links.get(pick); a.classList.add("on");
        a.scrollIntoView({ block: "nearest" });
      }
    }, { rootMargin: "-64px 0px -60% 0px" });
    heads.forEach((h) => spy.observe(h));
  }
  window.addEventListener("hashchange", route);
  route();
})();
