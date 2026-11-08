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
  let state = { obj: {}, labs: {}, best: {}, checks: {}, read: {}, notes: {}, history: {}, theme: null };
  try { Object.assign(state, JSON.parse(localStorage.getItem(STORE_KEY) || "{}")); } catch (e) {}
  state.read = state.read || {}; state.notes = state.notes || {}; state.history = state.history || {}; state.pins = state.pins || {};
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
    // Stable heading ids (from the heading text) so a page can be linked, and refreshed, at a section.
    const usedIds = {};
    wrap.querySelectorAll("h2, h3, h4").forEach((h) => { let id = "h-" + slugId(h.textContent); usedIds[id] = (usedIds[id] || 0) + 1; if (usedIds[id] > 1) id += "-" + usedIds[id]; h.id = id; });
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
      <a class="nav-link${active("#/host")}" href="#/host"><span class="nav-text">Lab host</span><span class="dot ${hostDotClass()}" id="hostDot" title="${esc(hostDotTitle())}"></span></a>
      <a class="nav-link${active("#/notes")}" href="#/notes"><span class="nav-text">My notes</span><span class="nav-num">${Object.values(state.notes).filter((n) => n.text.trim()).length || ""}</span></a>
      <a class="nav-link${active("#/review")}" href="#/review"><span class="nav-text">Pinned &amp; tests</span><span class="nav-num">${Object.keys(state.pins).filter((k) => pinInfo(k)).length || ""}</span></a>
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

  /* ---------- pins: mark guide sections, lectures (or a lecture's subsections) and labs for review or a test ---------- */
  const PIN_TAGS = { review: "Review", test: "Test me", both: "Review + test" };
  const objGroup = (num) => KIT.objectives.groups.find((g) => g.num === num);
  const labIdsIn = (text) => [...new Set((String(text).match(/\b(0\d|1[01])\b(?=\s*tasks?\b)/g) || []))];
  function pinInfo(key) {
    const [kind, rest] = [key.slice(0, key.indexOf(":")), key.slice(key.indexOf(":") + 1)];
    if (kind === "guide") {
      const s = sections.find((x) => x.slug === rest); if (!s) return null;
      const g = s.num && objGroup(s.num);
      return { kind: "Study guide", title: (s.num ? s.num + ". " : "") + s.title, href: "#/guide/" + s.slug, objs: g ? g.items : [], labs: s.labs || [] };
    }
    if (kind === "lecture") {
      const [num, sub] = rest.split("#"); const l = lectureByNum(num); if (!l) return null;
      const g = objGroup(l.num), sec = numbered.find((s) => s.num === l.num);
      let subTitle = "";
      if (sub) { const m = l.body.split("\n").find((line) => /^## /.test(line) && "lec-" + slugId(line.slice(3).replace(/[*`_]/g, "")) === sub); if (!m) return null; subTitle = m.slice(3).replace(/[*`]/g, ""); }
      return { kind: sub ? "Lecture subsection" : "Lecture", title: "Lecture " + l.num + ": " + l.title + (subTitle ? " › " + subTitle : ""), href: "#/lecture/" + l.num, objs: sub ? allObjectives.filter((o) => subTitle.startsWith(o.id + " ")) : g ? g.items : [], labs: sec ? sec.labs : [], sub: subTitle };
    }
    if (kind === "lab") {
      const l = labById(rest); if (!l) return null;
      return { kind: "Lab", title: "Lab " + l.id + ": " + shortTitle(l.title), href: "#/lab/" + l.id, objs: allObjectives.filter((o) => labIdsIn(o.labs).includes(l.id)), labs: [l.id] };
    }
    return null;
  }
  function setPin(key, tag) {
    if (tag) state.pins[key] = { t: (state.pins[key] && state.pins[key].t) || Date.now(), tag };
    else delete state.pins[key];
    save(); renderSidebar(curKey);
  }
  function pinBar(key) {
    const box = el(`<div class="pin-bar"></div>`);
    const draw = () => {
      const p = state.pins[key];
      box.innerHTML = p
        ? `<span class="pin-on">📌 Pinned</span><select aria-label="Pin tag">${Object.entries(PIN_TAGS).map(([v, t]) => `<option value="${v}"${p.tag === v ? " selected" : ""}>${t}</option>`).join("")}</select><button class="link-btn" type="button">Unpin</button><a href="#/review">See pinned</a>`
        : `<button class="btn" type="button" title="Pin this for review or to generate a test from">📌 Pin for review / test</button>`;
      if (p) { box.querySelector("select").onchange = (e) => setPin(key, e.target.value); box.querySelector(".link-btn").onclick = () => { setPin(key, null); draw(); }; }
      else box.querySelector("button").onclick = () => { setPin(key, "review"); draw(); };
    };
    draw();
    return box;
  }
  function subPinBtn(key) {
    const b = el(`<button class="sub-pin" type="button"></button>`);
    const draw = () => { const on = !!state.pins[key]; b.classList.toggle("on", on); b.textContent = on ? "📌" : "📍"; b.title = on ? "Pinned. Click to unpin" : "Pin this subsection for review / test"; };
    b.onclick = (e) => { e.stopPropagation(); setPin(key, state.pins[key] ? null : "review"); draw(); };
    draw();
    return b;
  }

  function pageReview() {
    const keys = Object.keys(state.pins).filter((k) => pinInfo(k)).sort((a, b) => state.pins[b].t - state.pins[a].t);
    app.innerHTML = `<div class="eyebrow">Review</div><h1>Pinned &amp; tests</h1>
      <p class="lede">Pin a lecture, a lecture subsection, a study-guide section or a lab with the 📌 button on its page. Tag each one <b>Review</b> or <b>Test me</b>, then copy a test request for Claude below. Claude writes the test, waits for your answers, and grades them. For hands-on questions it can build the scenario on your lab host.</p>`;
    if (!keys.length) { app.appendChild(el(`<div class="card empty">Nothing pinned yet. Open any lecture, guide section or lab and press <b>📌 Pin for review / test</b>.</div>`)); return; }
    const list = el(`<div class="pin-list"></div>`);
    for (const k of keys) {
      const info = pinInfo(k), p = state.pins[k];
      const row = el(`<div class="card pin-row"><label class="pin-pick"><input type="checkbox" data-k="${esc(k)}" ${p.tag !== "review" ? "checked" : ""}></label>
        <div class="pin-main"><a href="${info.href}">${esc(info.title)}</a><div class="s">${esc(info.kind)}${info.objs.length ? " · objectives " + esc(info.objs.map((o) => o.id).join(", ")) : ""}</div></div>
        <select aria-label="Tag">${Object.entries(PIN_TAGS).map(([v, t]) => `<option value="${v}"${p.tag === v ? " selected" : ""}>${t}</option>`).join("")}</select>
        <button class="link-btn" type="button">Unpin</button></div>`);
      row.querySelector("select").onchange = (e) => { setPin(k, e.target.value); row.querySelector("input").checked = e.target.value !== "review"; };
      row.querySelector(".link-btn").onclick = () => { setPin(k, null); pageReview(); };
      list.appendChild(row);
    }
    app.appendChild(list);
    const gen = el(`<section class="card test-gen"><h2>Generate a test</h2>
      <p class="muted">Ticked items above go into the test. Items tagged <b>Test me</b> are ticked by default.</p>
      <div class="test-opts">
        <label><span>Questions</span><select id="tN"><option>5</option><option selected>10</option><option>20</option><option>30</option></select></label>
        <label><span>Style</span><select id="tStyle"><option value="mixed">Mixed: concepts and hands-on</option><option value="mc">Multiple choice</option><option value="short">Short answer: commands and concepts</option><option value="hands">Hands-on tasks on my lab host</option><option value="exam">Mini EX200: timed exam-style tasks</option></select></label>
        <label><span>Difficulty</span><select id="tDiff"><option value="exam">Exam level</option><option value="easier">Warm-up</option><option value="harder">Harder than the exam</option></select></label>
      </div>
      <label class="ask-term"><input type="checkbox" id="tWeak" checked> Focus on objectives I haven't checked off yet</label>
      <div class="ask-actions"><button class="btn primary" type="button" id="tCopy">Copy test request for Claude</button><button class="link-btn" type="button" id="tPrev">Preview</button><span class="ask-st muted" id="tSt"></span></div>
      <pre class="ask-prev" id="tOut" hidden></pre></section>`);
    app.appendChild(gen);
    const build = () => {
      const picked = [...list.querySelectorAll("input[data-k]:checked")].map((c) => c.dataset.k);
      if (!picked.length) return "";
      const n = gen.querySelector("#tN").value, style = gen.querySelector("#tStyle").value, diff = gen.querySelector("#tDiff").value, weak = gen.querySelector("#tWeak").checked;
      const styleText = {
        mixed: "a mix of concept questions and short hands-on tasks",
        mc: "multiple-choice questions (4 options each, one correct)",
        short: "short-answer questions where I type the command or explain the concept",
        hands: "hands-on tasks I do on my lab host. Set up whatever each task needs in a lab container or the lab VM, then grade by inspecting the real system",
        exam: "EX200-style tasks: state only the required end state, never the command, and give me a time limit for the whole set. Set them up on my lab host and grade the final state, after a reboot where it matters",
      }[style];
      const diffText = { exam: "at real EX200 difficulty", easier: "as a warm-up, a bit easier than the exam", harder: "harder than the real exam, with edge cases and traps" }[diff];
      const lines = [
        `Make me an RHCSA (EX200, RHEL 10) practice test: ${n} questions, ${styleText}, ${diffText}.`,
        "Don't show any answers yet. Number the questions, then wait for my answers. When I send them, grade each one, explain what I got wrong, and give me a score.",
        hostStatus && !hostStatus.error && hostStatus.host ? `My lab host is ${hostStatus.host} (kit at ~/rhcsa-lab-kit).` : "",
        "", "Cover only these pinned topics:",
      ];
      const objIds = new Set();
      for (const k of picked) {
        const info = pinInfo(k);
        lines.push(`- ${info.kind}: ${info.title}`);
        for (const o of info.objs) { objIds.add(o.id); lines.push(`    - ${o.id} ${o.text}${state.obj[o.id] ? " (I've checked this off)" : ""}`); }
      }
      if (weak) {
        const open = allObjectives.filter((o) => objIds.has(o.id) && !state.obj[o.id]).map((o) => o.id);
        if (open.length) lines.push("", "Weight the test toward objectives I haven't checked off yet: " + open.join(", ") + ".");
      }
      const hist = [...new Set(picked.flatMap((k) => pinInfo(k).labs))].map((id) => { const h = (state.history[id] || []).slice(-1)[0]; return h && h.fails && h.fails.length ? `Lab ${id} (last ${h.p}/${h.n}): ` + h.fails.slice(0, 8).join("; ") : ""; }).filter(Boolean);
      if (hist.length) lines.push("", "Checks I failed last time in related labs:", ...hist.map((x) => "- " + x));
      return lines.filter((x, i, a) => x !== "" || a[i - 1] !== "").join("\n").trim();
    };
    const out = gen.querySelector("#tOut"), st = gen.querySelector("#tSt"), prev = gen.querySelector("#tPrev");
    const refresh = () => { if (!out.hidden) out.textContent = build() || "Tick at least one pinned item."; };
    prev.onclick = () => { out.hidden = !out.hidden; prev.textContent = out.hidden ? "Preview" : "Hide preview"; refresh(); };
    list.addEventListener("change", refresh); gen.addEventListener("change", refresh);
    gen.querySelector("#tCopy").onclick = async () => {
      const text = build();
      if (!text) { st.textContent = "Tick at least one pinned item."; return; }
      try { await navigator.clipboard.writeText(text); st.textContent = "Copied. Paste it into Claude."; }
      catch (e) { out.hidden = false; out.textContent = text; prev.textContent = "Hide preview"; const r = document.createRange(); r.selectNodeContents(out); getSelection().removeAllRanges(); getSelection().addRange(r); st.textContent = "Couldn't copy automatically. It's selected below: press Ctrl+C."; }
      setTimeout(() => (st.textContent = ""), 4000);
    };
  }

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
    document.getElementById("resetAll").onclick = (e) => { e.preventDefault(); if (confirm("Clear all checkboxes, lab statuses, grader history and best times? (Your notes are kept.)")) { state = { obj: {}, labs: {}, best: {}, checks: {}, read: {}, notes: state.notes, history: {}, theme: state.theme, pins: state.pins }; save(); route(); } };
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
    app.appendChild(pinBar("guide:" + s.slug));
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
    attachNotes(("guide-" + s.slug).slice(0, 64).replace(/-+$/, ""), "Study guide: " + s.title);
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
    app.appendChild(pinBar("lecture:" + l.num));
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
    for (const h of heads) if (pinInfo("lecture:" + l.num + "#" + h.id)) h.appendChild(subPinBtn("lecture:" + l.num + "#" + h.id));
    const g = KIT.objectives.groups.find((x) => x.num === l.num);
    if (g) {
      app.appendChild(el(`<h2>Check yourself</h2>`));
      app.appendChild(el(`<p class="lede" style="margin-bottom:12px">Tick an objective when you can do it from memory, without the guide.</p>`));
      app.appendChild(objList(g));
    }
    const mark = el(`<div class="btn-row"><button class="btn${state.read[l.num] ? "" : " primary"}" id="markRead">${state.read[l.num] ? "✓ Read (click to undo)" : "Mark lecture as read"}</button></div>`);
    mark.querySelector("button").onclick = () => { if (state.read[l.num]) delete state.read[l.num]; else state.read[l.num] = true; save(); pageLecture(num); renderSidebar(curKey); };
    app.appendChild(mark);
    attachNotes("lecture-" + l.num, "Lecture " + l.num + ": " + l.title);
    app.appendChild(pager(i > 0 && lectures[i - 1], lectures[i + 1], (x) => "#/lecture/" + x.num, (x) => "Lecture " + x.num + " · " + x.title));
  }

  function objList(g) {
    const ul = el(`<ul class="obj-list"></ul>`);
    for (const o of g.items) {
      const li = el(`<li class="obj${state.obj[o.id] ? " checked" : ""}"><input type="checkbox" ${state.obj[o.id] ? "checked" : ""} aria-label="${esc(o.id)}"><span class="oid">${esc(o.id)}</span>
        <span class="otext"><span>${esc(o.text)}</span><span class="olabs">Practice: ${linkLabs(o.labs)}</span></span></li>`);
      const cb = li.querySelector("input");
      const toggle = (v) => { state.obj[o.id] = v; if (!v) delete state.obj[o.id]; save(); li.classList.toggle("checked", v); cb.checked = v; renderSidebar(curKey); updateCount(); };
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
    app.querySelector(".toolbar").before(pinBar("lab:" + l.id));
    const cmds = "```bash\n./lab start " + l.id + "     # build and boot the scenario, print the tasks\n./lab shell " + l.id + "     # root shell" +
      (l.runtime === "vm" ? " (vagrant ssh + sudo -i)" : "") + "\n./lab check " + l.id + "     # grade yourself, as often as you like\n./lab reset " + l.id + "     # start over\n```";
    const cmdBox = md(cmds); cmdBox.classList.add("lab-cmds"); app.appendChild(cmdBox);
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

    buildConsole(l);
    // status
    app.querySelectorAll("#status button").forEach((b) => (b.onclick = () => {
      state.labs[l.id] = b.dataset.v; save();
      app.querySelectorAll("#status button").forEach((x) => x.classList.toggle("on", x === b));
      renderSidebar(curKey);
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


  /* ======================================================================
     Lab host: talks to agent/labkit-agent.py on your lab machine
     ====================================================================== */
  const HOST_KEY = "rhcsa-agent-v1";
  let host = { url: "", token: "" };
  try { Object.assign(host, JSON.parse(localStorage.getItem(HOST_KEY) || "{}")); } catch (e) {}
  const servedByAgent = /^https?:$/.test(location.protocol) && !/github\.io$/.test(location.hostname);
  const hostUrl = () => (host.url || (servedByAgent ? location.origin : "")).replace(/\/+$/, "");
  const hostReady = () => !!(hostUrl() && host.token);
  const saveHost = () => { try { localStorage.setItem(HOST_KEY, JSON.stringify(host)); } catch (e) {} };
  let hostStatus = null;
  const wideMQ = matchMedia("(min-width: 1280px)");

  async function api(path, opts = {}) {
    const r = await fetch(hostUrl() + "/api/" + path, { ...opts, cache: "no-store",
      headers: { Authorization: "Bearer " + host.token, ...(opts.body ? { "Content-Type": "application/json" } : {}) } });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(j.error || "HTTP " + r.status);
    return j;
  }
  async function refreshStatus() {
    if (!hostReady()) { hostStatus = null; updateHostDot(); return null; }
    try { hostStatus = await api("status"); } catch (e) { hostStatus = { error: e.message === "Failed to fetch" ? "can't reach the agent (is it running, and is this device on your tailnet?)" : e.message }; }
    updateHostDot();
    return hostStatus;
  }
  function hostDotClass() { return !hostReady() ? "" : !hostStatus ? "progress" : hostStatus.error ? "bad" : "done"; }
  function hostDotTitle() { return !hostReady() ? "Not set up" : !hostStatus ? "Connecting…" : hostStatus.error ? hostStatus.error : "Connected to " + hostStatus.host; }
  function updateHostDot() { const d = document.getElementById("hostDot"); if (d) { d.className = "dot " + hostDotClass(); d.title = hostDotTitle(); } }
  const stripAnsi = (t) => t.replace(/\x1b\[[0-9;?]*[ -\/]*[@-~]/g, "").replace(/\x1b[()][A-Z0-9]/g, "").replace(/\r(?!\n)/g, "\n");
  const ago = (ms) => { const s = (Date.now() - ms) / 1000; return s < 60 ? "just now" : s < 3600 ? Math.round(s / 60) + " min ago" : s < 86400 ? Math.round(s / 3600) + " h ago" : Math.round(s / 86400) + " d ago"; };

  function pageHost() {
    app.innerHTML = `<div class="eyebrow">Interactive labs</div><h1>Lab host</h1>
      <p class="lede">Connect this site to <code>labkit-agent</code> on your lab machine. Lab pages then get Start, Check and Reset buttons and a root shell in the browser, and your notes are backed up to git. The address and token are stored only in this browser.</p>
      <div class="card host-form">
        <label><span>Agent URL</span><input id="hUrl" type="url" spellcheck="false" placeholder="${servedByAgent ? esc(location.origin) + " (this page)" : "https://labhost.your-tailnet.ts.net"}"></label>
        <label><span>Token</span><input id="hTok" type="password" spellcheck="false" autocomplete="off" placeholder="python3 agent/labkit-agent.py token"></label>
        <div class="btn-row"><button class="btn primary" id="hSave">Save and test</button><button class="btn" id="hForget">Forget this host</button></div>
        <div id="hOut"></div>
      </div>`;
    const u = document.getElementById("hUrl"), t = document.getElementById("hTok"), out = document.getElementById("hOut");
    u.value = host.url; t.value = host.token;
    const show = () => {
      if (!hostReady()) { out.innerHTML = `<p class="callout">Not connected. Set up the agent with the steps below.</p>`; return; }
      if (!hostStatus) { out.innerHTML = `<p class="callout">Connecting…</p>`; return; }
      if (hostStatus.error) { out.innerHTML = `<p class="callout bad">✗ ${esc(hostStatus.error)}</p>`; return; }
      const s = hostStatus, n = s.notes || {};
      out.innerHTML = `<div class="callout ok"><b>✓ Connected to ${esc(s.host)}</b> · agent ${esc(s.version)} · ${esc(s.engine)}</div>
        <div class="host-facts">
          <div><span>Lab containers running</span><b>${s.containers.length ? s.containers.map((c) => `<a href="#/lab/${c}">Lab ${c}</a>`).join(", ") : "none"}</b></div>
          <div><span>Lab VM</span><b>${esc(s.vm.replace(/_/g, " "))}${s.vm_lab ? ` · last set up for <a href="#/lab/${s.vm_lab}">Lab ${s.vm_lab}</a>` : ""}</b></div>
          <div><span>Running now</span><b>${s.busy ? esc(s.busy.action + " lab " + s.busy.lab) : "nothing"}</b></div>
          <div><span>Notes backup</span><b>${!n.git ? "notes folder is not a git repo" : (n.last_commit ? "last commit " + ago(n.last_commit) : "no commits yet") + (n.remote ? (n.unpushed ? ` · ${n.unpushed} not pushed yet` : " · pushed") : " · no remote yet (see below)")}</b></div>
        </div>`;
    };
    document.getElementById("hSave").onclick = async () => {
      host.url = u.value.trim().replace(/\/+$/, ""); host.token = t.value.trim(); saveHost();
      if (host.url && location.protocol === "https:" && /^http:/.test(host.url) && !/^http:\/\/(localhost|127\.0\.0\.1)(:|$)/.test(host.url)) {
        out.innerHTML = `<p class="callout bad">This page is HTTPS, so the browser will block a plain-http agent. Use <code>tailscale serve</code> for an https://…ts.net address, or http://localhost.</p>`; return;
      }
      hostStatus = null; show(); await refreshStatus(); show();
      if (hostStatus && !hostStatus.error) syncAllNotes();
    };
    document.getElementById("hForget").onclick = () => { host = { url: "", token: "" }; saveHost(); hostStatus = null; u.value = t.value = ""; updateHostDot(); show(); };
    show(); if (hostReady()) refreshStatus().then(show);
    app.appendChild(el(`<h2>Set up the agent</h2>`));
    app.appendChild(md((KIT.agent || "").replace(/^# .*\n/, "")));
  }

  /* ---------- lab console: buttons, job output, browser terminal ---------- */
  let con = null; // { l, root, term, fit, ws, poll, ro }
  function teardownConsole() {
    if (!con) return;
    clearTimeout(con.poll);
    if (con.ws) { con.ws.onclose = null; con.ws.close(); }
    if (con.ro) con.ro.disconnect();
    if (con.term) con.term.dispose();
    wideMQ.removeEventListener?.("change", con.place);
    con.root.remove(); con = null;
    rail.innerHTML = "";
    document.querySelector(".layout").classList.remove("has-console");
  }

  function buildConsole(l) {
    const ready = hostReady();
    const root = el(`<section class="console card" aria-label="Lab console">
      <div class="con-bar">
        <span class="con-state" id="cState">${ready ? "Connecting…" : "No lab host"}</span>
        <div class="con-btns">
          <button class="btn primary" data-a="start" title="./lab start ${l.id}">Start</button>
          <button class="btn" data-a="check" title="./lab check ${l.id}">Check</button>
          <button class="btn" data-a="reset" title="./lab reset ${l.id}">Reset</button>
          <button class="btn" data-a="stop" title="./lab stop ${l.id}">Stop</button>
        </div>
      </div>
      <div class="con-tabs" role="tablist"><button data-t="term" class="on">Terminal</button><button data-t="out">Output <span class="con-score" id="cScore"></span></button><button data-t="notes">Notes</button><button data-t="hist">History</button><button data-t="ask">Ask Claude</button></div>
      <div class="con-pane" data-p="term"><div class="term-wrap"><div class="term" id="cTerm"></div>
        <div class="term-cover" id="cCover">${ready
          ? `<button class="btn primary" id="cOpen">Open root shell</button><p>Runs <code>./lab shell ${l.id}</code> on your lab host${l.runtime === "vm" ? " (the VM, as root)" : " (inside the lab container)"}. Start the lab first.</p>`
          : `<p><b>Run this lab from the browser.</b> Connect your lab machine on the <a href="#/host">Lab host</a> page to get Start/Check/Reset and a root shell here.</p><p>Until then, use the commands on the left in your own terminal.</p>`}</div></div></div>
      <div class="con-pane" data-p="out" hidden><pre class="job-out" id="cOut">Output from Start, Check and Reset appears here.</pre></div>
      <div class="con-pane" data-p="notes" hidden></div>
      <div class="con-pane" data-p="hist" hidden></div>
      <div class="con-pane" data-p="ask" hidden></div>
    </section>`);
    con = { l, root };
    root.querySelector('[data-p="notes"]').appendChild(notesEditor("lab-" + l.id, "Lab " + l.id + ": " + shortTitle(l.title)));
    root.querySelector('[data-p="ask"]').appendChild(askPane(l));
    const tabs = root.querySelectorAll(".con-tabs button");
    const showTab = (t) => {
      tabs.forEach((b) => b.classList.toggle("on", b.dataset.t === t));
      root.querySelectorAll(".con-pane").forEach((p) => (p.hidden = p.dataset.p !== t));
      if (t === "term" && con.fit) setTimeout(() => con && con.fit && con.fit.fit(), 0);
      if (t === "hist") renderHistory(l, root.querySelector('[data-p="hist"]'));
    };
    con.showTab = showTab;
    tabs.forEach((b) => (b.onclick = () => showTab(b.dataset.t)));
    root.querySelectorAll(".con-btns button").forEach((b) => {
      b.disabled = !ready;
      b.onclick = () => runAction(b.dataset.a);
    });
    if (ready) root.querySelector("#cOpen").onclick = openTerm;

    // Wide screens: console fills the right column next to the tasks. Narrow: inline under the toolbar.
    con.place = () => {
      const lay = document.querySelector(".layout");
      if (wideMQ.matches) { rail.innerHTML = ""; rail.appendChild(root); lay.classList.add("has-console"); }
      else { lay.classList.remove("has-console"); const after = app.querySelector(".lab-cmds"); after ? after.after(root) : app.appendChild(root); }
      if (con.fit) setTimeout(() => con && con.fit && con.fit.fit(), 50);
    };
    con.place();
    wideMQ.addEventListener?.("change", con.place);
    if (ready) refreshStatus().then(updateConState);
  }

  function updateConState() {
    if (!con) return;
    const st = con.root.querySelector("#cState"), id = con.l.id;
    if (!hostStatus) return;
    if (hostStatus.error) { st.className = "con-state bad"; st.textContent = "Lab host unreachable"; st.title = hostStatus.error; return; }
    const up = con.l.runtime === "vm" ? hostStatus.vm === "running" && hostStatus.vm_lab === id : hostStatus.containers.includes(id);
    const busy = hostStatus.busy;
    st.className = "con-state " + (busy ? "busy" : up ? "ok" : "");
    st.textContent = busy ? `${busy.action}ing lab ${busy.lab}…` : up ? "Lab running" : con.l.runtime === "vm" && hostStatus.vm === "running" ? (hostStatus.vm_lab ? `VM has lab ${hostStatus.vm_lab}` : "VM running") : "Lab not running";
    st.title = hostStatus.host;
  }

  async function runAction(a) {
    if (!con) return;
    const l = con.l;
    if (a === "reset" && !confirm(`Throw away lab ${l.id} and rebuild it from scratch?`)) return;
    const out = con.root.querySelector("#cOut");
    const btns = con.root.querySelectorAll(".con-btns button");
    con.showTab("out");
    out.textContent = `$ ./lab ${a} ${l.id}\n`;
    let job;
    try { job = (await api(`labs/${l.id}/${a}`, { method: "POST" })).job; }
    catch (e) { out.textContent += "✗ " + e.message + "\n"; return; }
    if (a !== "check") btns.forEach((b) => (b.disabled = true));
    if ((a === "start" || a === "reset") && (state.labs[l.id] || "todo") === "todo") setLabStatus(l.id, "progress");
    const st = con.root.querySelector("#cState"); st.className = "con-state busy"; st.textContent = a === "check" ? "Grading…" : `${a}ing…`;
    let off = 0, text = "";
    const tick = async () => {
      if (!con || con.l !== l) return;
      let j;
      try { j = await api(`jobs/${job}?offset=${off}`); } catch (e) { out.textContent += "\n✗ " + e.message; btns.forEach((b) => (b.disabled = false)); return; }
      off = j.offset; text += j.output;
      const nearBottom = out.scrollHeight - out.scrollTop - out.clientHeight < 40;
      out.textContent = `$ ./lab ${a} ${l.id}\n` + stripAnsi(text);
      if (nearBottom) out.scrollTop = out.scrollHeight;
      if (!j.done) { con.poll = setTimeout(tick, 700); return; }
      btns.forEach((b) => (b.disabled = false));
      out.textContent += `\n[exit ${j.rc}]`;
      if (a === "check") gradeResult(l, stripAnsi(text));
      await refreshStatus(); updateConState();
      if ((a === "start" || a === "reset") && j.rc === 0) { con.showTab("term"); if (con.ws) { con.ws.close(); } else openTerm(); }
    };
    tick();
  }

  function setLabStatus(id, v) {
    state.labs[id] = v; save();
    app.querySelectorAll("#status button").forEach((x) => x.classList.toggle("on", x.dataset.v === v));
    renderSidebar(curKey);
  }

  function gradeResult(l, text) {
    const m = text.match(/Score:\s*(\d+)\s*\/\s*(\d+)/);
    const badge = con.root.querySelector("#cScore");
    if (!m) { badge.textContent = "?"; badge.className = "con-score"; return; }
    const p = +m[1], n = +m[2];
    con.lastCheck = { t: Date.now(), text };
    const fails = (text.match(/^\s*FAIL .*$/gm) || []).map((x) => x.trim().replace(/^FAIL\s+/, ""));
    (state.history[l.id] = state.history[l.id] || []).push({ t: Date.now(), p, n, fails: fails.slice(0, 30) });
    if (state.history[l.id].length > 50) state.history[l.id].shift();
    save();
    badge.textContent = `${p}/${n}`; badge.className = "con-score " + (p === n ? "ok" : "bad");
    if (p === n && state.labs[l.id] !== "done") setLabStatus(l.id, "done");
  }

  /* "Ask Claude": builds a paste-ready help request (lab, question, grader result, recent terminal). Never includes the agent URL or token. */
  function termTail(n) {
    if (!con || !con.term) return "";
    const b = con.term.buffer.active, lines = [];
    for (let i = Math.max(0, b.length - 400); i < b.length; i++) lines.push(b.getLine(i).translateToString(true));
    while (lines.length && !lines[lines.length - 1].trim()) lines.pop();
    return lines.slice(-n).join(NL);
  }
  const NL = "\n";
  function helpRequest(l, mode, q, withTerm) {
    const h = (state.history[l.id] || []).slice(-1)[0];
    const lc = con && con.lastCheck;
    const ask = mode === "grade"
      ? "Please grade my work: run the check yourself, look at what I actually did, and tell me what's wrong and why. Full explanations are fine."
      : "Please give me hints, not the solution. Look at what I actually did and point me in the right direction. Only show the answer if I ask.";
    let up = "unknown";
    if (hostStatus && !hostStatus.error) up = l.runtime === "vm" ? (hostStatus.vm === "running" ? `VM running${hostStatus.vm_lab ? " (lab " + hostStatus.vm_lab + ")" : ""}` : "VM not running") : (hostStatus.containers.includes(l.id) ? "running" : "not running");
    const parts = [
      `I need help with RHCSA lab ${l.id}: ${shortTitle(l.title)}.`,
      `Lab host: ${(hostStatus && hostStatus.host) || "my lab host"}, kit at ~/rhcsa-lab-kit (use ./lab check ${l.id} and ./lab shell ${l.id}). Lab is ${up}.`,
      "", ask, "", "My question: " + (q.trim() || "(none, just see where I am)"),
    ];
    if (h) parts.push("", `Last grade (${new Date(h.t).toLocaleString()}): ${h.p}/${h.n}` + (h.fails && h.fails.length ? NL + "Failing checks:" + NL + h.fails.map((f) => "- " + f).join(NL) : ""));
    if (lc) parts.push("", "Last check output:", "```", lc.text.trim().split(NL).slice(-60).join(NL), "```");
    const tt = withTerm ? termTail(40) : "";
    if (tt) parts.push("", "My recent terminal:", "```", tt, "```");
    return parts.join(NL);
  }
  function askPane(l) {
    const box = el(`<div class="ask">
      <p class="muted">Copies everything Claude needs (lab, your question, latest grade, recent terminal) so you can paste it into your Claude chat. Claude can then log into your lab host to look.</p>
      <div class="ask-mode" role="radiogroup"><label><input type="radio" name="askMode" value="hint" checked> Hints only</label><label><input type="radio" name="askMode" value="grade"> Grade me and explain</label></div>
      <textarea spellcheck="true" placeholder="What are you stuck on? (optional)"></textarea>
      <label class="ask-term"><input type="checkbox" checked> Include last 40 lines of my terminal</label>
      <div class="ask-actions"><button class="btn primary" type="button">Copy for Claude</button><button class="link-btn" type="button">Preview</button><span class="ask-st muted"></span></div>
      <pre class="ask-prev" hidden></pre></div>`);
    const ta = box.querySelector("textarea"), [copy, prevBtn] = box.querySelectorAll(".ask-actions button"), st = box.querySelector(".ask-st"), pv = box.querySelector(".ask-prev"), term = box.querySelector(".ask-term input");
    const build = () => helpRequest(l, box.querySelector('input[name="askMode"]:checked').value, ta.value, term.checked);
    prevBtn.onclick = () => { pv.hidden = !pv.hidden; prevBtn.textContent = pv.hidden ? "Preview" : "Hide preview"; if (!pv.hidden) pv.textContent = build(); };
    box.addEventListener("input", () => { if (!pv.hidden) pv.textContent = build(); });
    copy.onclick = async () => {
      const text = build();
      try { await navigator.clipboard.writeText(text); st.textContent = "Copied. Paste it into Claude."; }
      catch (e) { pv.hidden = false; pv.textContent = text; prevBtn.textContent = "Hide preview"; const r = document.createRange(); r.selectNodeContents(pv); getSelection().removeAllRanges(); getSelection().addRange(r); st.textContent = "Couldn't copy automatically. It's selected below: press Ctrl+C."; }
      setTimeout(() => (st.textContent = ""), 4000);
    };
    return box;
  }

  function renderHistory(l, box) {
    const h = (state.history[l.id] || []).slice().reverse();
    if (!h.length) { box.innerHTML = `<p class="empty">No graded runs yet. Press <b>Check</b> to grade your work; every run is recorded here.</p>`; return; }
    const best = Math.max(...h.map((r) => r.p / r.n));
    box.innerHTML = `<div class="hist-sum">${h.length} graded run${h.length > 1 ? "s" : ""} · best ${Math.round(best * 100)}%</div>` +
      h.map((r) => `<details class="hist-row"><summary><span class="hist-bar"><i style="width:${pct(r.p, r.n)}%" class="${r.p === r.n ? "ok" : ""}"></i></span><b>${r.p}/${r.n}</b><span class="muted">${new Date(r.t).toLocaleString()}</span></summary>${r.fails && r.fails.length ? `<ul>${r.fails.map((f) => `<li>${esc(f)}</li>`).join("")}</ul>` : "<p>All checks passed.</p>"}</details>`).join("");
  }

  function openTerm() {
    if (!con || con.ws) return;
    if (typeof Terminal === "undefined") { alert("Terminal library failed to load."); return; }
    const l = con.l, box = con.root.querySelector("#cTerm");
    con.root.querySelector("#cCover").hidden = true;
    if (!con.term) {
      con.term = new Terminal({ fontFamily: '"JetBrains Mono", ui-monospace, monospace', fontSize: 13.5, lineHeight: 1.15, cursorBlink: true, scrollback: 5000, allowProposedApi: false,
        theme: { background: "#0e0f11", foreground: "#e6e6e6", cursor: "#ff5468", selectionBackground: "#ff546855" } });
      con.fit = new FitAddon.FitAddon(); con.term.loadAddon(con.fit); con.term.open(box);
      const enc = new TextEncoder();
      con.term.onData((d) => con.ws && con.ws.readyState === 1 && con.ws.send(enc.encode(d)));
      con.term.onBinary((d) => con.ws && con.ws.readyState === 1 && con.ws.send(Uint8Array.from(d, (c) => c.charCodeAt(0) & 255)));
      con.term.onResize(({ cols, rows }) => con.ws && con.ws.readyState === 1 && con.ws.send(JSON.stringify({ cols, rows })));
      con.ro = new ResizeObserver(() => { try { con.fit.fit(); } catch (e) {} }); con.ro.observe(box);
    }
    try { con.fit.fit(); } catch (e) {}
    const term = con.term;
    term.write(`\x1b[2mConnecting to lab ${l.id}…\x1b[0m\r\n`);
    const ws = new WebSocket(hostUrl().replace(/^http/, "ws") + "/api/term?lab=" + l.id);
    ws.binaryType = "arraybuffer"; con.ws = ws;
    ws.onopen = () => ws.send(JSON.stringify({ token: host.token, cols: term.cols, rows: term.rows }));
    ws.onmessage = (e) => {
      if (typeof e.data === "string") { try { const m = JSON.parse(e.data); if (m.error) term.write(`\r\n\x1b[31m${m.error}\x1b[0m\r\n`); } catch (x) {} return; }
      term.write(new Uint8Array(e.data));
    };
    ws.onclose = () => {
      if (!con || con.ws !== ws) return;
      con.ws = null;
      term.write("\r\n\x1b[2m[shell closed]\x1b[0m\r\n");
      const cover = con.root.querySelector("#cCover"); cover.hidden = false;
      cover.querySelector("p").textContent = "The shell ended (you logged out, the lab was reset, or the connection dropped).";
      cover.querySelector("button").textContent = "Reconnect";
    };
    term.focus();
  }

  /* ---------- notes: Markdown, saved in this browser and synced to the lab host's git repo ---------- */
  let notesEl = null, currentNoteKey = null;
  function attachNotes(key, title) {
    currentNoteKey = key;
    notesEl = notesEditor(key, title);
    notesEl.classList.add("page-notes");
    placeNotes(false);
  }
  function placeNotes(railOn) {
    if (!notesEl) return;
    if (railOn && wideMQ.matches) { rail.appendChild(notesEl); notesEl.classList.add("in-rail"); }
    else { notesEl.classList.remove("in-rail"); const pg = app.querySelector(".pager"); pg ? pg.before(notesEl) : app.appendChild(notesEl); }
  }
  wideMQ.addEventListener?.("change", () => { if (notesEl) placeNotes(document.querySelector(".layout").classList.contains("has-rail")); });

  const pushTimers = {};
  function pushNote(key, cb) {
    const n = state.notes[key];
    if (!n || !hostReady()) { cb && cb(hostReady() ? "" : "Saved in this browser only (no lab host)"); return; }
    api("notes/" + key, { method: "PUT", body: JSON.stringify({ text: n.text, updated: n.updated }) })
      .then((r) => { n.synced = r.updated; save(); cb && cb("Synced to lab host"); })
      .catch((e) => cb && cb("Saved in this browser · sync failed: " + e.message));
  }
  async function syncAllNotes() {
    if (!hostReady()) return 0;
    let changed = 0;
    try {
      const remote = (await api("notes")).notes;
      for (const [k, t] of Object.entries(remote)) {
        const n = state.notes[k];
        if (!n || (t > (n.updated || 0) && t !== n.synced)) { const r = await api("notes/" + k); state.notes[k] = { text: r.text, updated: r.updated, synced: r.updated }; changed++; }
      }
      for (const [k, n] of Object.entries(state.notes)) if ((n.updated || 0) > (n.synced || 0) && (!remote[k] || n.updated > remote[k])) { await new Promise((ok) => pushNote(k, ok)); changed++; }
      save();
    } catch (e) {}
    return changed;
  }

  function notesEditor(key, title) {
    const n = state.notes[key] || { text: "", updated: 0, synced: 0 };
    const box = el(`<div class="notes">
      <div class="notes-head"><span class="rail-label">My notes</span><span class="notes-st"></span><button class="link-btn" type="button">Preview</button></div>
      <textarea spellcheck="true" placeholder="Notes for ${esc(title)}. Markdown works. Saved as you type${hostReady() ? " and backed up to your lab host" : ""}."></textarea>
      <div class="notes-prev" hidden></div></div>`);
    const ta = box.querySelector("textarea"), st = box.querySelector(".notes-st"), pv = box.querySelector(".notes-prev"), tog = box.querySelector(".link-btn");
    const status = (t) => (st.textContent = t || "");
    ta.value = n.text;
    const grow = () => { if (!box.classList.contains("in-rail") && !box.closest(".console")) { ta.style.height = "auto"; ta.style.height = Math.max(160, ta.scrollHeight + 4) + "px"; } };
    setTimeout(grow, 0);
    ta.addEventListener("input", () => {
      n.text = ta.value; n.updated = Date.now(); state.notes[key] = n; save(); grow();
      status("Saving…");
      clearTimeout(pushTimers[key]);
      pushTimers[key] = setTimeout(() => pushNote(key, (m) => status(m || "Saved")), 1200);
      ghSchedule(key, status);
    });
    ta.addEventListener("keydown", (e) => { if (e.key === "Tab") { e.preventDefault(); ta.setRangeText("  ", ta.selectionStart, ta.selectionEnd, "end"); ta.dispatchEvent(new Event("input")); } });
    tog.onclick = () => {
      const show = pv.hidden;
      pv.hidden = !show; ta.hidden = show; tog.textContent = show ? "Edit" : "Preview";
      if (show) { pv.innerHTML = ""; pv.appendChild(n.text.trim() ? md(n.text) : el(`<p class="empty">Nothing yet.</p>`)); }
    };
    if (hostReady()) {
      api("notes/" + key).then((r) => {
        if (r.updated > (n.updated || 0) && r.text !== n.text && document.activeElement !== ta) {
          Object.assign(n, { text: r.text, updated: r.updated, synced: r.updated }); state.notes[key] = n; save(); ta.value = r.text; grow(); status("Loaded from lab host");
        } else if ((n.updated || 0) > (n.synced || 0) && n.text) pushNote(key, status);
        else status(r.updated || n.text ? "Synced" : "");
      }).catch(() => status(n.text ? "Saved in this browser (lab host offline)" : ""));
    } else status(n.text ? "Saved in this browser" : "");
    if (ghReady()) ghPullOne(key).then((r) => {
      if (r === "pulled") { ta.value = state.notes[key].text; Object.assign(n, state.notes[key]); grow(); status("Loaded from GitHub"); }
      else if (r === "pushed") status("Backed up to GitHub");
    }).catch((e) => status("GitHub: " + e.message));
    return box;
  }

  const noteSource = (k) => {
    let m;
    if ((m = k.match(/^lecture-(\d+)$/)) && lectureByNum(m[1])) return { title: "Lecture " + m[1] + ": " + lectureByNum(m[1]).title, href: "#/lecture/" + m[1], order: "1" + m[1].padStart(2, "0") };
    if ((m = k.match(/^lab-(\d\d)$/)) && labById(m[1])) return { title: "Lab " + m[1] + ": " + shortTitle(labById(m[1]).title), href: "#/lab/" + m[1], order: "3" + m[1] };
    if ((m = k.match(/^guide-(.+)$/))) { const s = sections.find((x) => ("guide-" + x.slug).slice(0, 64).replace(/-+$/, "") === k); if (s) return { title: "Study guide: " + s.title, href: "#/guide/" + s.slug, order: "2" + String(sections.indexOf(s)).padStart(2, "0") }; }
    return { title: k, href: null, order: "9" + k };
  };
  function pageNotes() {
    app.innerHTML = `<div class="eyebrow">Notes</div><h1>My notes</h1>
      <p class="lede">Every lecture, study guide section and lab has a notes box, and they are all collected here. Notes save in this browser as you type${ghReady() ? ", are committed to <a href=\"https://github.com/" + esc(ghCfg.repo) + "\">" + esc(ghCfg.repo) + "</a> on GitHub" : ""}${hostReady() ? " and are synced to your lab host" : ""}.</p>
      <div class="btn-row"><button class="btn" id="nDl">Download all (.md)</button>${ghReady() || hostReady() ? `<button class="btn" id="nSync">Sync now</button>` : ""}<span class="muted" id="nMsg"></span></div>`;
    app.appendChild(ghCard(() => pageNotes()));
    app.appendChild(el(`<div id="nList"></div>`));
    const render = () => {
      const list = document.getElementById("nList"); if (!list) return;
      const items = Object.entries(state.notes).filter(([, n]) => n.text.trim()).map(([k, n]) => ({ k, n, ...noteSource(k) })).sort((a, b) => a.order.localeCompare(b.order));
      list.innerHTML = items.length ? "" : `<p class="empty">No notes yet. Open any lecture or lab and start typing in the notes box.</p>`;
      for (const it of items) {
        const c = el(`<section class="card note-card"><div class="note-top">${it.href ? `<a href="${it.href}"><b>${esc(it.title)}</b></a>` : `<b>${esc(it.title)}</b>`}<span class="muted">${ago(it.n.updated)}</span></div></section>`);
        c.appendChild(md(it.n.text)); list.appendChild(c);
      }
      return items;
    };
    let items = render();
    document.getElementById("nDl").onclick = () => {
      const txt = "# RHCSA notes\n\n" + items.map((it) => `## ${it.title}\n\n${it.n.text.trim()}\n`).join("\n");
      const a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([txt], { type: "text/markdown" })); a.download = "rhcsa-notes.md"; a.click();
    };
    const syncBtn = document.getElementById("nSync");
    const doSync = async () => {
      const msg = document.getElementById("nMsg"); if (msg) msg.textContent = "Syncing…";
      let c = 0, err = "";
      if (ghReady()) { try { c += await ghSyncAll(); } catch (e) { err = "GitHub: " + e.message; } }
      if (hostReady()) { c += await syncAllNotes(); try { await api("notes/sync", { method: "POST" }); } catch (e) {} }
      if (document.getElementById("nMsg")) { document.getElementById("nMsg").textContent = err || (c ? `${c} note(s) synced` : "Everything is backed up"); items = render(); }
    };
    if (syncBtn) { syncBtn.onclick = doSync; doSync(); }
  }


  /* ---------- notes backup straight to a private GitHub repo (works without a lab host) ---------- */
  const GH_KEY = "rhcsa-ghnotes-v1";
  let ghCfg = { repo: "Braden-Develops/rhcsa-notes", token: "" };
  try { Object.assign(ghCfg, JSON.parse(localStorage.getItem(GH_KEY) || "{}")); } catch (e) {}
  const ghReady = () => !!(ghCfg.repo && ghCfg.token);
  const ghSave = () => { try { localStorage.setItem(GH_KEY, JSON.stringify(ghCfg)); } catch (e) {} };
  async function gh(path, opts = {}) {
    const r = await fetch(`https://api.github.com/repos/${ghCfg.repo}${path}`, { ...opts, cache: "no-store",
      headers: { Authorization: "Bearer " + ghCfg.token, Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28" } });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) { const e = new Error(r.status === 401 ? "token rejected (expired or wrong?)" : r.status === 404 ? "repo not found, or the token can't see it" : j.message || "HTTP " + r.status); e.status = r.status; e.body = j; throw e; }
    return j;
  }
  const b64enc = (str) => { const b = new TextEncoder().encode(str); let s = ""; for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode.apply(null, b.subarray(i, i + 0x8000)); return btoa(s); };
  const b64dec = (c) => new TextDecoder().decode(Uint8Array.from(atob(c.replace(/\s/g, "")), (x) => x.charCodeAt(0)));
  const ghPending = (n) => (n.updated || 0) > (n.ghAt || 0);

  async function ghPush(key) {
    const n = state.notes[key]; if (!n) return;
    const at = n.updated;
    const body = (sha) => JSON.stringify({ message: "Notes: " + noteSource(key).title, content: b64enc(n.text), ...(sha ? { sha } : {}) });
    let r;
    try { r = await gh(`/contents/${key}.md`, { method: "PUT", body: body(n.ghSha) }); }
    catch (e) {
      if (e.status !== 409 && e.status !== 422) throw e;
      // our sha is stale (edited on another device): this browser's newer text wins, on top of the latest version
      let sha; try { sha = (await gh(`/contents/${key}.md`)).sha; } catch (x) { if (x.status !== 404) throw x; }
      r = await gh(`/contents/${key}.md`, { method: "PUT", body: body(sha) });
    }
    n.ghSha = r.content.sha; n.ghAt = at; save();
  }
  const ghTimers = {};
  function ghSchedule(key, status) {
    if (!ghReady()) return;
    clearTimeout(ghTimers[key]);
    ghTimers[key] = setTimeout(() => { delete ghTimers[key]; ghPush(key).then(() => status && status("Backed up to GitHub")).catch((e) => status && status("GitHub backup failed: " + e.message)); }, 15000);
  }
  // Flush pending GitHub pushes when the tab is hidden or closed.
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState !== "hidden") return;
    for (const k of Object.keys(ghTimers)) { clearTimeout(ghTimers[k]); delete ghTimers[k]; ghPush(k).catch(() => {}); }
  });

  // One note: pull it if GitHub has a version this browser hasn't seen and we have no unsynced edits; push if we do.
  async function ghPullOne(key) {
    const n = state.notes[key];
    let f = null;
    try { f = await gh(`/contents/${key}.md`); } catch (e) { if (e.status !== 404) throw e; }
    if (f && (!n || (f.sha !== n.ghSha && !ghPending(n)))) {
      state.notes[key] = Object.assign(n || {}, { text: b64dec(f.content), updated: Date.now(), ghSha: f.sha }); state.notes[key].ghAt = state.notes[key].updated; save();
      return "pulled";
    }
    if (n && n.text && (ghPending(n) || !f)) { await ghPush(key); return "pushed"; }
    return "same";
  }
  async function ghSyncAll() {
    let list = [];
    try { list = await gh("/contents/"); } catch (e) { if (!(e.status === 404 && /empty/i.test((e.body && e.body.message) || ""))) throw e; }
    let c = 0;
    const remote = new Map(list.filter((f) => f.type === "file" && /^[a-z0-9][a-z0-9-]{0,63}\.md$/.test(f.name) && f.name !== "README.md").map((f) => [f.name.slice(0, -3), f.sha]));
    for (const [k, sha] of remote) {
      const n = state.notes[k];
      if (!n || (sha !== n.ghSha && !ghPending(n))) { const f = await gh(`/contents/${k}.md`); state.notes[k] = Object.assign(n || {}, { text: b64dec(f.content), updated: Date.now(), ghSha: f.sha }); state.notes[k].ghAt = state.notes[k].updated; c++; }
    }
    for (const [k, n] of Object.entries(state.notes)) if (n.text && (ghPending(n) || !remote.has(k))) { await ghPush(k); c++; }
    save();
    return c;
  }

  function ghCard(onChange) {
    const box = el(`<details class="spoiler gh-card"${ghReady() ? "" : " open"}><summary>GitHub backup <span class="hint">${ghReady() ? "on: " + esc(ghCfg.repo) : "off: notes are only in this browser"}</span></summary><div class="inner">
      <p>The site commits each note to a <b>private</b> repo, about 15 seconds after you stop typing (and when you leave the page). It uses a fine-grained token that can only read and write that one repo. Your notes follow you to any browser where you paste the token.</p>
      <ol>
        <li>Create an empty private repo, for example <code>rhcsa-notes</code>.</li>
        <li><a href="https://github.com/settings/personal-access-tokens/new" target="_blank" rel="noopener">Create a fine-grained token</a>: Repository access → <b>Only select repositories</b> → that repo; Permissions → <b>Contents: Read and write</b>. Nothing else.</li>
        <li>Paste it below.</li>
      </ol>
      <div class="host-form" style="box-shadow:none;border:0;padding:0">
        <label><span>Repo (owner/name)</span><input id="gRepo" spellcheck="false"></label>
        <label><span>Token</span><input id="gTok" type="password" spellcheck="false" autocomplete="off" placeholder="github_pat_…"></label>
        <div class="btn-row"><button class="btn primary" id="gSave">Save and sync</button>${ghReady() ? `<button class="btn" id="gOff">Turn off on this browser</button>` : ""}</div>
        <div id="gOut"></div>
      </div>
      <p class="muted">The token is kept in this browser's local storage. Every site under braden-develops.github.io shares that storage, which is fine as long as they are all yours; the token can't touch anything except the notes repo.</p>
    </div></details>`);
    const repo = box.querySelector("#gRepo"), tok = box.querySelector("#gTok"), out = box.querySelector("#gOut");
    repo.value = ghCfg.repo; tok.value = ghCfg.token;
    box.querySelector("#gSave").onclick = async () => {
      ghCfg.repo = repo.value.trim().replace(/^https:\/\/github\.com\//, "").replace(/\.git$|\/+$/g, ""); ghCfg.token = tok.value.trim();
      out.innerHTML = `<p class="callout">Checking…</p>`;
      try {
        const info = await gh("");
        if (!info.private) { out.innerHTML = `<p class="callout bad">${esc(ghCfg.repo)} is <b>public</b>. Make it private (Settings → Danger zone) before putting notes in it.</p>`; return; }
        if (info.permissions && !info.permissions.push) { out.innerHTML = `<p class="callout bad">The token can read the repo but not write to it. Give it Contents: Read and write.</p>`; return; }
        ghSave();
        out.innerHTML = `<p class="callout">Connected. Syncing…</p>`;
        const c = await ghSyncAll();
        out.innerHTML = `<p class="callout ok">✓ Backing up to ${esc(ghCfg.repo)}. ${c} note(s) synced.</p>`;
        setTimeout(onChange, 1200);
      } catch (e) { out.innerHTML = `<p class="callout bad">✗ ${esc(e.message)}</p>`; }
    };
    const off = box.querySelector("#gOff");
    if (off) off.onclick = () => { ghCfg.token = ""; ghSave(); onChange(); };
    return box;
  }
  if (ghReady()) ghSyncAll().catch(() => {});

  // Connect in the background on load, so the sidebar dot and notes are current.
  if (hostReady()) refreshStatus().then((s) => { if (s && !s.error) syncAllNotes(); });

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

  /* ---------- router ----------
     Page routes may carry a trailing section: #/lecture/3/lec-3-2-..., #/guide/<slug>/h-..., #/lab/04/h-...,
     #/setup/h-... . While you read, the hash follows the heading you are in (replaceState, so no history
     entries pile up), and a refresh or a shared link lands back on that section. */
  const SECTION_PAGES = { lecture: 1, guide: 1, lab: 1, setup: 0 };  // value: whether the page takes an item argument first
  let curKey = "#/", firstRoute = true;
  history.scrollRestoration = "manual";
  function splitHash(h) {
    const [, page, rest = ""] = h.match(/^#\/([^/]*)\/?(.*)$/) || [];
    if (!(page in SECTION_PAGES)) return { page, arg: rest, sec: "", base: h };
    let arg = rest, sec = "";
    if (SECTION_PAGES[page]) { const i = rest.indexOf("/"); if (i >= 0) { arg = rest.slice(0, i); sec = rest.slice(i + 1); } }
    else { arg = ""; sec = rest; }
    return { page, arg, sec: decodeURIComponent(sec), base: "#/" + page + (arg ? "/" + arg : "") };
  }
  function sectionHeads() {
    return [...app.querySelectorAll(".md h2[id], .md h3[id]")].filter((h) => h.offsetParent !== null && !h.closest("details:not([open])"));
  }
  function goToSection(id) {
    const t = id && document.getElementById(id);
    if (!t || !app.contains(t)) return false;
    t.scrollIntoView({ block: "start" });
    return true;
  }
  let hashT = 0, landing = null;
  // After a refresh, keep re-landing on the section while late layout (fonts, highlighting, the rail) settles,
  // and leave the hash alone meanwhile. Any wheel, touch, key or click by the reader ends that at once.
  function landOn(id) {
    landing = id;
    const again = () => { if (landing === id) goToSection(id); };
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(() => requestAnimationFrame(again));
    [100, 300, 700].forEach((ms) => setTimeout(again, ms));
    setTimeout(() => { if (landing === id) landing = null; }, 1000);
  }
  ["wheel", "touchstart", "keydown", "mousedown"].forEach((ev) => window.addEventListener(ev, () => { landing = null; }, { passive: true }));
  function syncHashToScroll() {
    hashT = 0;
    if (landing) return;
    // Pages with no headings to tag still come back to the same spot on refresh (this tab only).
    try { sessionStorage.setItem("rhcsa-scroll", JSON.stringify({ key: curKey, y: Math.round(scrollY) })); } catch (e) {}
    const { page, base } = splitHash(location.hash || "#/");
    if (!(page in SECTION_PAGES) || base !== curKey) return;
    let cur = null;
    for (const h of sectionHeads()) { if (h.getBoundingClientRect().top <= 90) cur = h; else break; }
    const want = cur ? base + "/" + cur.id : base;
    if (want !== location.hash) history.replaceState(history.state, "", want);
  }
  window.addEventListener("scroll", () => { if (!hashT) hashT = setTimeout(syncHashToScroll, 150); }, { passive: true });

  function route() {
    const sp = splitHash(location.hash || "#/");
    if (sp.page in SECTION_PAGES && sp.base === curKey && app.childElementCount) { if (!goToSection(sp.sec)) window.scrollTo(0, 0); return; }
    if (timer) { clearInterval(timer); timer = null; }
    teardownConsole();
    notesEl = null; currentNoteKey = null;
    const { page, arg, sec, base: h } = sp;
    document.body.classList.remove("nav-open");
    let navKey = h;
    curKey = h;
    if (page === "search") { const q = decodeURIComponent(arg); if (searchBox.value.trim() !== q) searchBox.value = q; pageSearch(q); }
    else if (page === "lecture" && arg) pageLecture(arg);
    else if (page === "lecture" || page === "lectures") pageLectureIndex();
    else if (page === "guide" && arg) pageGuide(arg);
    else if (page === "guide") pageGuideIndex();
    else if (page === "objectives") pageObjectives();
    else if (page === "labs") pageLabs();
    else if (page === "lab") pageLab(arg);
    else if (page === "setup") pageSetup();
    else if (page === "host") pageHost();
    else if (page === "notes") pageNotes();
    else if (page === "review") pageReview();
    else { pageHome(); navKey = curKey = "#/"; }
    renderSidebar(navKey);
    const t = app.querySelector("h1");
    document.title = (t && navKey !== "#/" ? t.textContent + " · " : "") + "RHCSA Study Kit";
    const a = sidebar.querySelector(".active"); if (a) a.scrollIntoView({ block: "nearest" });
    buildRail(["lecture", "guide"].includes(page) && arg ? page : null, currentNoteKey);
    landing = null;
    let saved = null;
    if (firstRoute) { try { saved = JSON.parse(sessionStorage.getItem("rhcsa-scroll")); } catch (e) {} }
    firstRoute = false;
    if (sec && goToSection(sec)) landOn(sec);
    else if (saved && saved.key === h && saved.y > 0) { window.scrollTo(0, saved.y); setTimeout(() => { if (!scrollY) window.scrollTo(0, saved.y); }, 300); }
    else if (page !== "search") window.scrollTo(0, 0);
  }

  /* ---------- right rail (wide screens): "on this page" with scroll-spy ---------- */
  const rail = document.getElementById("rail");
  let spy = null;
  function buildRail(kind, noteKey) {
    if (spy) { spy.disconnect(); spy = null; }
    if (rail.querySelector(".console")) return;  // lab pages: the console owns the rail
    rail.innerHTML = "";
    document.querySelector(".layout").classList.remove("has-console");
    let heads = [...app.querySelectorAll(".md h2")];
    if (heads.length < 3) heads = [...app.querySelectorAll(".md h2, .md h3")];
    heads = heads.filter((h) => !h.closest("details:not(.toc)"));
    const on = !!kind && (heads.length >= 2 || !!noteKey);
    document.querySelector(".layout").classList.toggle("has-rail", on);
    placeNotes(on);
    if (!on || heads.length < 2) return;
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
    rail.insertBefore(box, rail.firstChild);
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
