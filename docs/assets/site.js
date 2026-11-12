// Legroom website effects. No dependencies. Everything degrades to a static page
// with prefers-reduced-motion or without JavaScript.
(() => {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];

  // ---------- squarified treemap (Bruls, Huizing & van Wijk), as in the app ----------
  function squarify(values, x, y, w, h) {
    const total = values.reduce((a, b) => a + b.v, 0) || 1;
    const items = values.map(d => ({ ...d, a: d.v / total * w * h })).sort((a, b) => b.a - a.a);
    const out = [];
    let row = [], rect = { x, y, w, h };
    const worst = (r, side) => {
      const s = r.reduce((a, b) => a + b.a, 0), mx = Math.max(...r.map(d => d.a)), mn = Math.min(...r.map(d => d.a));
      return Math.max(side * side * mx / (s * s), (s * s) / (side * side * mn));
    };
    const layout = (r) => {
      const s = r.reduce((a, b) => a + b.a, 0);
      if (rect.w >= rect.h) {
        const cw = s / rect.h; let cy = rect.y;
        r.forEach(d => { const ch = d.a / cw; out.push({ ...d, x: rect.x, y: cy, w: cw, h: ch }); cy += ch; });
        rect = { x: rect.x + cw, y: rect.y, w: rect.w - cw, h: rect.h };
      } else {
        const ch = s / rect.w; let cx = rect.x;
        r.forEach(d => { const cw = d.a / ch; out.push({ ...d, x: cx, y: rect.y, w: cw, h: ch }); cx += cw; });
        rect = { x: rect.x, y: rect.y + ch, w: rect.w, h: rect.h - ch };
      }
    };
    for (const it of items) {
      const side = Math.min(rect.w, rect.h);
      if (!row.length || worst([...row, it], side) <= worst(row, side)) row.push(it);
      else { layout(row); row = [it]; }
    }
    if (row.length) layout(row);
    return out;
  }

  // ---------- hero: living treemap that "moves things to the Trash" ----------
  const tree = $(".tree");
  if (tree) {
    let id = 0;
    const rnd = () => Math.pow(Math.random(), 1.6) * 90 + 6;
    let data = Array.from({ length: 34 }, () => ({ id: id++, v: rnd() }));
    const els = new Map();
    const GAP = 6;
    const draw = () => {
      const W = tree.clientWidth, H = tree.clientHeight;
      const laid = squarify(data, 0, 0, W, H);
      const seen = new Set();
      laid.forEach(d => {
        seen.add(d.id);
        let el = els.get(d.id);
        if (!el) { el = document.createElement("div"); el.className = "blk gone"; tree.appendChild(el); els.set(d.id, el);
          requestAnimationFrame(() => requestAnimationFrame(() => el.classList.remove("gone"))); }
        Object.assign(el.style, { left: d.x + GAP / 2 + "px", top: d.y + GAP / 2 + "px",
          width: Math.max(0, d.w - GAP) + "px", height: Math.max(0, d.h - GAP) + "px" });
      });
      for (const [k, el] of els) if (!seen.has(k)) { el.remove(); els.delete(k); }
    };
    draw();
    addEventListener("resize", () => draw(), { passive: true });
    if (!reduce) {
      setInterval(() => {
        if (document.hidden) return;
        // highlight one block, then send it to the Trash and let the rest take the room
        const candidates = data.filter(d => d.v > 10);
        const pick = candidates[Math.floor(Math.random() * candidates.length)];
        const el = els.get(pick.id); if (!el) return;
        el.classList.add("hot");
        setTimeout(() => {
          el.classList.add("gone");
          setTimeout(() => {
            data = data.filter(d => d.id !== pick.id);
            if (data.length < 30) data.push({ id: id++, v: rnd() }, { id: id++, v: rnd() * .5 });
            draw();
          }, 450);
        }, 900);
      }, 2600);
    }
  }

  // ---------- nav background on scroll ----------
  const nav = $(".nav");
  const onScroll = () => nav && nav.classList.toggle("scrolled", scrollY > 30);
  addEventListener("scroll", onScroll, { passive: true }); onScroll();

  // ---------- hero window: tilt flattens as it scrolls into view ----------
  const win = $(".window");
  if (win && !reduce) {
    let ticking = false;
    const tilt = () => {
      ticking = false;
      const r = win.getBoundingClientRect();
      const p = Math.min(1, Math.max(0, 1 - (r.top - innerHeight * .18) / (innerHeight * .7)));
      win.style.setProperty("--tilt", (18 * (1 - p)).toFixed(2) + "deg");
      win.style.setProperty("--scale", (.94 + .06 * p).toFixed(3));
    };
    addEventListener("scroll", () => { if (!ticking) { ticking = true; requestAnimationFrame(tilt); } }, { passive: true });
    tilt();
  }

  // ---------- reveal + per-section triggers ----------
  const io = new IntersectionObserver((entries) => {
    entries.forEach(e => {
      if (!e.isIntersecting) return;
      e.target.classList.add("in");
      e.target.dispatchEvent(new CustomEvent("enter"));
      io.unobserve(e.target);
    });
  }, { threshold: .18 });
  $$(".rv, [data-enter]").forEach(el => io.observe(el));

  // count-up numbers
  $$("[data-count]").forEach(el => {
    const to = parseFloat(el.dataset.count), dec = +(el.dataset.dec || 0), suf = el.dataset.suffix || "";
    const fmt = new Intl.NumberFormat(document.documentElement.lang, { minimumFractionDigits: dec, maximumFractionDigits: dec });
    const host = el.closest("[data-enter]") || el;
    host.addEventListener("enter", () => {
      if (reduce) { el.textContent = fmt.format(to) + suf; return; }
      const t0 = performance.now(), dur = 1500;
      const step = (t) => { const k = Math.min(1, (t - t0) / dur), e = 1 - Math.pow(1 - k, 4);
        el.textContent = fmt.format(to * e) + suf; if (k < 1) requestAnimationFrame(step); };
      requestAnimationFrame(step);
    });
  });

  // ---------- bento: cursor spotlight ----------
  $$(".cell").forEach(c => c.addEventListener("pointermove", (e) => {
    const r = c.getBoundingClientRect();
    c.style.setProperty("--mx", e.clientX - r.left + "px");
    c.style.setProperty("--my", e.clientY - r.top + "px");
  }));

  // ---------- bento: mini treemap with labels; hover a block to "drill in" ----------
  const mini = $(".mini-tree");
  if (mini) {
    const apps = JSON.parse(mini.dataset.items);
    const palette = ["124,140,255", "96,165,250", "52,211,153", "167,139,250", "45,212,191", "129,140,248", "56,189,248", "110,231,183"];
    const els = apps.map((a, i) => {
      const el = document.createElement("div"); el.className = "blk";
      el.style.background = `rgba(${palette[i % palette.length]},.30)`;
      el.innerHTML = `<div>${a.n}<small>${a.s}</small></div>`; mini.appendChild(el); return el;
    });
    let focus = -1;
    const lay = () => {
      const W = mini.clientWidth, H = mini.clientHeight;
      const vals = apps.map((a, i) => ({ id: i, v: a.v * (i === focus ? 2.4 : 1) }));
      squarify(vals, 0, 0, W, H).forEach(d => Object.assign(els[d.id].style,
        { left: d.x + 2 + "px", top: d.y + 2 + "px", width: d.w - 4 + "px", height: d.h - 4 + "px" }));
    };
    els.forEach((el, i) => { el.addEventListener("pointerenter", () => { focus = i; lay(); }); });
    mini.addEventListener("pointerleave", () => { focus = -1; lay(); });
    lay(); addEventListener("resize", lay, { passive: true });
  }

  // ---------- bento: uninstall — leftovers get checked, then go to the Trash ----------
  const ul = $(".ulist");
  if (ul) {
    const items = $$("li", ul), total = $("[data-utotal]");
    const run = () => {
      if (reduce) { items.forEach(li => li.classList.add("on")); return; }
      items.forEach(li => li.classList.remove("on", "out"));
      items.forEach((li, i) => setTimeout(() => li.classList.add("on"), 300 + i * 260));
      setTimeout(() => items.forEach((li, i) => setTimeout(() => li.classList.add("out"), i * 90)), 300 + items.length * 260 + 900);
      setTimeout(() => { items.forEach(li => li.classList.remove("on", "out")); }, 300 + items.length * 260 + 900 + items.length * 90 + 1300);
    };
    ul.closest("[data-enter]").addEventListener("enter", () => {
      run(); if (!reduce) setInterval(() => !document.hidden && run(), 300 + items.length * 350 + 3600);
    });
    if (total) total.textContent = total.dataset.v;
  }

  // ---------- bento: clutter — duplicates light up in pairs ----------
  const dupes = $$(".dupe");
  if (dupes.length && !reduce) {
    const pairs = [[0, 5], [2, 7], [1, 6], [3, 4]];
    let k = 0;
    setInterval(() => {
      if (document.hidden) return;
      dupes.forEach(d => d.classList.remove("same"));
      pairs[k % pairs.length].forEach(i => dupes[i].classList.add("same"));
      k++;
    }, 1600);
  }

  // ---------- showcase tabs (auto-advance, pause on hover) ----------
  const show = $(".show");
  if (show) {
    const tabs = $$(".tab", show), imgs = $$(".screens img", show), cap = $(".caption", show);
    let cur = 0, timer;
    const go = (i) => {
      cur = i;
      tabs.forEach((t, j) => { t.setAttribute("aria-selected", j === i); const p = $(".prog", t); p.style.animation = "none"; p.offsetWidth; p.style.animation = ""; });
      imgs.forEach((im, j) => im.classList.toggle("on", j === i));
      cap.textContent = tabs[i].dataset.caption;
      clearTimeout(timer); if (!reduce) timer = setTimeout(() => !show.classList.contains("paused") && go((cur + 1) % tabs.length), 6000);
    };
    tabs.forEach((t, i) => t.addEventListener("click", () => go(i)));
    show.addEventListener("pointerenter", () => show.classList.add("paused"));
    show.addEventListener("pointerleave", () => { show.classList.remove("paused"); go(cur); });
    go(0);
  }

  // ---------- manifesto: words light up as you scroll ----------
  const man = $(".manifesto");
  if (man && !reduce) {
    const words = $$(".w", man);
    let ticking = false;
    const lit = () => {
      ticking = false;
      const r = man.getBoundingClientRect();
      const p = Math.min(1, Math.max(0, (innerHeight * .85 - r.top) / (r.height + innerHeight * .35)));
      const n = Math.round(p * words.length);
      words.forEach((w, i) => w.classList.toggle("lit", i < n));
    };
    addEventListener("scroll", () => { if (!ticking) { ticking = true; requestAnimationFrame(lit); } }, { passive: true });
    lit();
  }

  // ---------- under the hood: the terminal types itself ----------
  const pre = $(".term pre");
  if (pre) {
    const html = pre.innerHTML;
    if (!reduce) {
      pre.innerHTML = '<span class="caret"></span>';
      pre.closest("[data-enter]").addEventListener("enter", () => {
        // type plain text, then swap in the highlighted version
        const tmp = document.createElement("div"); tmp.innerHTML = html; const text = tmp.textContent;
        let i = 0;
        const tick = () => {
          i = Math.min(text.length, i + (text[i] === "\n" ? 1 : 3));
          pre.textContent = text.slice(0, i); pre.insertAdjacentHTML("beforeend", '<span class="caret"></span>');
          if (i < text.length) setTimeout(tick, text[i - 1] === "\n" ? 140 : 16);
          else pre.innerHTML = html + '<span class="caret"></span>';
        };
        tick();
      });
    }
  }

  // ---------- live data from GitHub: stars, latest version and size ----------
  const REPO = "rafabittt/legroom";
  const cache = (k, f) => {
    try { const c = JSON.parse(sessionStorage.getItem(k)); if (c && Date.now() - c.t < 6e5) return Promise.resolve(c.v); } catch {}
    return f().then(v => { try { sessionStorage.setItem(k, JSON.stringify({ t: Date.now(), v })); } catch {} return v; });
  };
  const get = (u) => fetch(u, { headers: { Accept: "application/vnd.github+json" } }).then(r => r.ok ? r.json() : Promise.reject(r.status));
  cache("lg-repo", () => get(`https://api.github.com/repos/${REPO}`).then(j => ({ stars: j.stargazers_count })))
    .then(({ stars }) => stars >= 10 && $$("[data-stars]").forEach(el => { el.querySelector("b").textContent = new Intl.NumberFormat(document.documentElement.lang, { notation: "compact" }).format(stars); el.hidden = false; }))
    .catch(() => {});
  cache("lg-rel", () => get(`https://api.github.com/repos/${REPO}/releases/latest`).then(j => {
    const dmg = (j.assets || []).find(a => a.name.endsWith(".dmg"));
    return { tag: j.tag_name, url: dmg && dmg.browser_download_url, size: dmg && dmg.size };
  })).then(({ tag, url, size }) => {
    if (url) $$("[data-dl]").forEach(a => a.href = url);
    const v = (tag || "").replace(/^v/, "");
    $$("[data-version]").forEach(el => el.textContent = v);
    if (size) $$("[data-size]").forEach(el => el.textContent = (size / 1e6).toLocaleString(document.documentElement.lang, { maximumFractionDigits: 1 }) + " MB");
  }).catch(() => {});
})();
