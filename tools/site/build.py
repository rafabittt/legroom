#!/usr/bin/env python3
"""Builds the Legroom website into docs/ (served by GitHub Pages).

    python3 tools/site/build.py

Writes docs/index.html (English) and docs/pt/index.html (Brazilian Portuguese),
plus sitemap.xml and robots.txt. Styles and effects live in docs/assets/site.css
and docs/assets/site.js. No dependencies.
"""
import hashlib
import html
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "docs")
SITE = "https://rafabittt.github.io/legroom/"
REPO = "https://github.com/rafabittt/legroom"
LATEST = REPO + "/releases/latest"
VERSION = "0.9.8"   # fallback; the page reads the latest release from the GitHub API
SIZE = "3.8 MB"

APPLE = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16.37 12.8c-.02-2.2 1.8-3.26 1.88-3.31-1.03-1.5-2.62-1.7-3.18-1.73-1.35-.14-2.64.8-3.33.8-.69 0-1.74-.78-2.87-.76-1.47.02-2.83.86-3.59 2.18-1.53 2.66-.39 6.6 1.1 8.76.73 1.06 1.6 2.24 2.73 2.2 1.1-.04 1.51-.71 2.84-.71 1.32 0 1.7.71 2.86.69 1.18-.02 1.93-1.07 2.65-2.14.84-1.23 1.18-2.42 1.2-2.48-.03-.01-2.3-.88-2.32-3.5zM14.2 6.33c.6-.73 1.01-1.75.9-2.76-.87.04-1.92.58-2.54 1.31-.56.64-1.05 1.67-.92 2.66.97.08 1.96-.49 2.56-1.21z"/></svg>'
GITHUB = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 .5a11.5 11.5 0 0 0-3.64 22.41c.58.1.79-.25.79-.56v-2c-3.2.7-3.88-1.37-3.88-1.37-.52-1.33-1.28-1.69-1.28-1.69-1.05-.72.08-.7.08-.7 1.16.08 1.77 1.19 1.77 1.19 1.03 1.77 2.7 1.26 3.36.96.1-.75.4-1.26.73-1.55-2.55-.29-5.24-1.28-5.24-5.69 0-1.26.45-2.29 1.19-3.09-.12-.29-.52-1.46.11-3.05 0 0 .97-.31 3.17 1.18a11 11 0 0 1 5.77 0c2.2-1.49 3.17-1.18 3.17-1.18.63 1.59.23 2.76.11 3.05.74.8 1.19 1.83 1.19 3.09 0 4.42-2.69 5.39-5.26 5.68.41.36.78 1.06.78 2.14v3.17c0 .31.21.67.8.56A11.5 11.5 0 0 0 12 .5z"/></svg>'
STAR = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" style="width:14px;height:14px"><path d="M12 2.5l2.9 6.1 6.6.8-4.9 4.5 1.3 6.6L12 17.3 6.1 20.5l1.3-6.6L2.5 9.4l6.6-.8z"/></svg>'
CHECK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>'

MINI_TREE = [
    {"n": "Xcode", "s": "3.97 GB", "v": 397}, {"n": "Final Cut Pro", "s": "3.1 GB", "v": 310},
    {"n": "Chrome", "s": "1.55 GB", "v": 155}, {"n": "Blender", "s": "1 GB", "v": 100},
    {"n": "VS Code", "s": "986 MB", "v": 98}, {"n": "Docker", "s": "820 MB", "v": 82},
    {"n": "Slack", "s": "540 MB", "v": 54}, {"n": "Spotify", "s": "380 MB", "v": 38},
    {"n": "Figma", "s": "320 MB", "v": 32}, {"n": "Notion", "s": "290 MB", "v": 29},
]

EN = dict(
    lang="en", path="", other="pt/", other_label="Português", other_hreflang="pt-BR",
    title="Legroom — free, open-source storage manager for Mac",
    desc="See what's filling your Mac's disk, clean up caches safely and uninstall apps completely. Free and open source. Everything goes to the Trash; nothing runs on its own.",
    skip="Skip to content",
    nav=[("#features", "Features"), ("#tour", "Tour"), ("#principles", "Principles"), ("#open-source", "Open source")],
    star="Star", download="Download",
    eyebrow="Free & open source · macOS 14 or later",
    h1='Give your Mac some <em>legroom</em>.',
    lead="See what's filling your disk, clean up what your Mac recreates on its own, and uninstall apps completely. Everything goes to the Trash. Nothing runs without you.",
    cta="Download for Mac", cta2="View on GitHub",
    meta='Version <span data-version>{v}</span> · <span data-size>{s}</span> · Apple silicon &amp; Intel · Notarized by Apple',
    shot_alt="Legroom's Overview: disk health, memory, CPU with temperature, network and space freed so far",
    chip1='<span class="n">−2.12 GB</span> moved to the Trash', chip2='Disk is healthy · <span class="n">178 GB</span> free',
    trust=["Notarized by Apple", "Everything goes to the Trash", "No telemetry, no account", "MIT licensed"],
    f_kicker="Features", f_h="Six questions. One quiet app.", f_p="Each screen answers one thing you actually want to know about your disk — and reads only the folders it needs.",
    map_tag="Map", map_h="What's taking up my disk?", map_p="A full scan as a treemap and a list. The last scan is saved, so it reopens instantly next time.",
    un_tag="Apps", un_h="Uninstall means uninstall.", un_p="Legroom finds what an app leaves behind — support data, caches, preferences, launch agents, even the installer in Downloads — and lets you review it first.",
    un_items=[("Blender.app", "1 GB"), ("~/Library/Application Support/Blender", "864 KB"), ("…/C/org.blenderfoundation.blender", "755 MB"), ("~/Library/Caches/Blender", "504 KB"), ("~/Downloads/blender-5.3.0-macos-arm64.dmg", "360 MB")],
    un_total="to the Trash", un_total_v="2.12 GB",
    cl_tag="Cleanup", cl_h="What can I safely clean up?", cl_p="Caches, logs and developer leftovers your Mac rebuilds. Open JSON rules, each with a plain explanation.",
    cl_rows=[("App caches", "6.63 GB", 64, ""), ("iOS DeviceSupport", "14.39 GB", 100, "review first"), ("Xcode DerivedData", "840 MB", 18, ""), ("npm, Cargo, Gradle", "5.82 GB", 52, "")],
    ov_tag="Overview", ov_h="How is my Mac doing?", ov_p="Disk health, memory, CPU with chip temperature, network — and how much Legroom has freed.",
    ov_ring="64%", ov_m=[("Memory", "22.3", " GB"), ("Chip", "48", " °C"), ("Freed", "10.8", " GB")],
    cu_tag="Clutter", cu_h="Where's the clutter?", cu_p="Duplicates confirmed by content, downloads you never opened again, old installers and piles of screenshots.",
    wd_tag="Menu bar & widgets", wd_h="At a glance, without opening it.", wd_p="A compact Overview in the menu bar, and widgets for the desktop and Notification Center.",
    ck_tag="Check-up", ck_h="Is anything running that shouldn't be?", ck_p="Your Mac's built-in defenses, the result of Apple's own malware checks, and everything that opens on its own, grouped by who signed it. No alarms: it shows what runs and why something is worth a look, and you decide.",
    ck_defs=[("System Integrity", "On", 1), ("Gatekeeper", "On", 1), ("FileVault", "On", 1), ("Firewall", "Off", 0), ("XProtect", "5372", 1), ("Security updates", "On", 1)],
    ck_items=[("com.example.helper", "Runs a script · added today", "Worth a look", 1), ("com.google.keystone.agent", "Its program no longer exists", "Leftover", 2), ("com.valvesoftware.steam", "Valve Corporation", "Identified developer", 0)],
    t_kicker="Tour", t_h="A closer look.", t_p="Native SwiftUI, light and dark, English and Portuguese.",
    tabs=[("Map", "map", "Dive into folders and see exactly what takes up space."),
          ("Cleanup", "cleanup", "A conservative selection is pre-checked; the rest is your call."),
          ("Light mode", "overview-light", "Light and dark, following your Mac — or your choice.")],
    p_kicker="Principles",
    manifesto=[("Most", ""), ("Mac", ""), ("cleaners", ""), ("are", ""), ("subscriptions", ""), ("wrapped", ""), ("in", ""), ("scare", ""), ("tactics.", ""),
               ("Legroom", "g"), ("shows", "g"), ("you", "g"), ("what's", "g"), ("there", "g"), ("and", "g"), ("lets", "g"), ("you", "g"), ("decide.", "g")],
    rules=[("Nothing runs on its own", "Every scan starts when you ask. The main scan even needs a press-and-hold."),
           ("Everything goes to the Trash", "Nothing is deleted for good, and Legroom never empties the Trash."),
           ("Everything is explained", "Full path, size on disk, logical size, dates — and what well-known folders are."),
           ("Nothing phones home", "No account, no analytics. The only request is the speed test, when you click it.")],
    h_kicker="Under the hood", h_h="Built like a system tool.", h_p="No helper running as root, no login items, no background agents. One native process.",
    facts=[("<code>fts(3)</code>, like <code>du</code>", "Allocated sizes, the space you actually get back. Hard links count once; APFS clones and sparse files show up."),
           ("A saved map in ~35 MB", "Four million nodes in a compact binary tree, LZFSE-compressed. Reopens in about a second."),
           ("Signed updates", "Notarized by Apple, updated with Sparkle and EdDSA-signed releases.")],
    o_mono="The code is open source", o_h="Take it, or build it with us.",
    o_p="Legroom is MIT-licensed. Read how it works, open an issue, translate it into your language, or send a pull request.",
    o_cta="Star on GitHub", o_cta2="Download",
    faq_h="Questions",
    faq=[("Is it really free?", "Yes. No trial, no subscription, no in-app purchases. The code is on GitHub under the MIT license."),
         ("Is it safe?", "Legroom never deletes anything permanently: everything goes to the Trash, where you can put it back. It's signed with a Developer ID and notarized by Apple."),
         ("Why does it ask for Full Disk Access?", "macOS hides some folders (Mail, Messages, some app containers) from every app. With Full Disk Access the scan is complete; without it, Legroom tells you what it couldn't read."),
         ("Why isn't it on the Mac App Store?", "The App Store requires the sandbox, which makes a full disk scan, the process list and complete uninstalls impossible."),
         ("How do updates work?", "Legroom › Check for Updates…, or automatic checks if you allow them. Updates are the same notarized releases published on GitHub.")],
    foot_made="Made in Brazil by Rafael Bittencourt.", foot_links=[("GitHub", REPO), ("Releases", REPO + "/releases"), ("Issues", REPO + "/issues"), ("License", REPO + "/blob/main/LICENSE")],
)

PT = dict(
    lang="pt-BR", path="pt/", other="", other_label="English", other_hreflang="en",
    title="Legroom — gerenciador de armazenamento grátis e open source para Mac",
    desc="Veja o que ocupa o disco do seu Mac, limpe caches com segurança e desinstale apps por completo. Grátis e open source. Tudo vai para o Lixo; nada roda sozinho.",
    skip="Pular para o conteúdo",
    nav=[("#features", "Recursos"), ("#tour", "Tour"), ("#principles", "Princípios"), ("#open-source", "Open source")],
    star="Star", download="Baixar",
    eyebrow="Grátis e open source · macOS 14 ou superior",
    h1='Seu Mac com <em>folga</em> de novo.',
    lead="Veja o que ocupa o disco, limpe o que o Mac recria sozinho e desinstale apps por completo. Tudo vai para o Lixo. Nada roda sem você.",
    cta="Baixar para Mac", cta2="Ver no GitHub",
    meta='Versão <span data-version>{v}</span> · <span data-size>{s}</span> · Apple silicon e Intel · Notarizado pela Apple',
    shot_alt="Resumo do Legroom: saúde do disco, memória, processador com temperatura, rede e espaço já liberado",
    chip1='<span class="n">−2,12 GB</span> foram para o Lixo', chip2='Disco saudável · <span class="n">178 GB</span> livres',
    trust=["Notarizado pela Apple", "Tudo vai para o Lixo", "Sem telemetria, sem conta", "Licença MIT"],
    f_kicker="Recursos", f_h="Seis perguntas. Um app tranquilo.", f_p="Cada tela responde a uma coisa que você quer saber sobre o disco — e lê só as pastas de que precisa.",
    map_tag="Mapa", map_h="O que ocupa meu disco?", map_p="Uma leitura completa em blocos e em lista. A última leitura fica salva e reabre na hora.",
    un_tag="Apps", un_h="Desinstalar é desinstalar.", un_p="O Legroom acha o que o app deixa para trás — dados, caches, preferências, agentes de inicialização, até o instalador em Downloads — e mostra antes de mexer.",
    un_items=[("Blender.app", "1 GB"), ("~/Library/Application Support/Blender", "864 KB"), ("…/C/org.blenderfoundation.blender", "755 MB"), ("~/Library/Caches/Blender", "504 KB"), ("~/Downloads/blender-5.3.0-macos-arm64.dmg", "360 MB")],
    un_total="para o Lixo", un_total_v="2,12 GB",
    cl_tag="Limpeza", cl_h="O que posso limpar sem medo?", cl_p="Caches, logs e restos de ferramentas que o Mac refaz. Regras abertas em JSON, cada uma com explicação.",
    cl_rows=[("Caches dos apps", "6,63 GB", 64, ""), ("DeviceSupport do iOS", "14,39 GB", 100, "revise antes"), ("DerivedData do Xcode", "840 MB", 18, ""), ("npm, Cargo, Gradle", "5,82 GB", 52, "")],
    ov_tag="Resumo", ov_h="Como está meu Mac?", ov_p="Saúde do disco, memória, processador com a temperatura do chip, rede — e quanto o Legroom já liberou.",
    ov_ring="64%", ov_m=[("Memória", "22,3", " GB"), ("Chip", "48", " °C"), ("Liberado", "10,8", " GB")],
    cu_tag="Bagunça", cu_h="Onde está a bagunça?", cu_p="Duplicados confirmados pelo conteúdo, downloads esquecidos, instaladores antigos e pilhas de capturas de tela.",
    wd_tag="Barra de menus e widgets", wd_h="De relance, sem abrir o app.", wd_p="Um Resumo compacto na barra de menus e widgets para a Mesa e a Central de Notificações.",
    ck_tag="Check-up", ck_h="Tem algo rodando que não deveria?", ck_p="As defesas que já vêm no Mac, o resultado das checagens de malware da própria Apple e tudo o que abre sozinho, agrupado por quem assinou. Sem alarme: mostra o que roda e por que algo vale uma olhada, e quem decide é você.",
    ck_defs=[("Integridade do Sistema", "Ligado", 1), ("Gatekeeper", "Ligado", 1), ("FileVault", "Ligado", 1), ("Firewall", "Desligado", 0), ("XProtect", "5372", 1), ("Atualizações de segurança", "Ligado", 1)],
    ck_items=[("com.example.helper", "Roda um script · adicionado hoje", "Vale uma olhada", 1), ("com.google.keystone.agent", "O programa não existe mais", "Sobra", 2), ("com.valvesoftware.steam", "Valve Corporation", "Desenvolvedor identificado", 0)],
    t_kicker="Tour", t_h="Olhando de perto.", t_p="SwiftUI nativo, claro e escuro, português e inglês.",
    tabs=[("Mapa", "map", "Entre nas pastas e veja exatamente o que ocupa espaço."),
          ("Limpeza", "cleanup", "Uma seleção conservadora vem marcada; o resto é com você."),
          ("Tema claro", "overview-light", "Claro e escuro, acompanhando o Mac — ou como você preferir.")],
    p_kicker="Princípios",
    manifesto=[("A", ""), ("maioria", ""), ("dos", ""), ("“limpadores”", ""), ("de", ""), ("Mac", ""), ("é", ""), ("assinatura", ""), ("embrulhada", ""), ("em", ""), ("susto.", ""),
               ("O", "g"), ("Legroom", "g"), ("mostra", "g"), ("o", "g"), ("que", "g"), ("tem", "g"), ("e", "g"), ("deixa", "g"), ("você", "g"), ("decidir.", "g")],
    rules=[("Nada roda sozinho", "Toda leitura começa quando você pede. A principal ainda pede para segurar o botão."),
           ("Tudo vai para o Lixo", "Nada é apagado de vez, e o Legroom nunca esvazia o Lixo."),
           ("Tudo é explicado", "Caminho completo, tamanho em disco, tamanho lógico, datas — e o que são as pastas conhecidas."),
           ("Nada sai do seu Mac", "Sem conta, sem análise de uso. A única conexão é o teste de velocidade, quando você clica.")],
    h_kicker="Por dentro", h_h="Feito como ferramenta de sistema.", h_p="Sem processo auxiliar como root, sem itens de login, sem agentes em segundo plano. Um processo nativo.",
    facts=[("<code>fts(3)</code>, como o <code>du</code>", "Tamanho alocado, o espaço que realmente volta. Hard links contam uma vez; clones APFS e arquivos esparsos aparecem."),
           ("Um mapa salvo em ~35 MB", "Quatro milhões de nós numa árvore binária compacta, comprimida com LZFSE. Reabre em cerca de um segundo."),
           ("Atualizações assinadas", "Notarizado pela Apple, atualizado com Sparkle e versões assinadas com EdDSA.")],
    o_mono="O código é aberto", o_h="Use, ou construa com a gente.",
    o_p="O Legroom tem licença MIT. Veja como funciona, abra uma issue, traduza para o seu idioma ou mande um pull request.",
    o_cta="Dar star no GitHub", o_cta2="Baixar",
    faq_h="Perguntas",
    faq=[("É grátis mesmo?", "Sim. Sem teste, sem assinatura, sem compras dentro do app. O código está no GitHub, com licença MIT."),
         ("É seguro?", "O Legroom nunca apaga nada de vez: tudo vai para o Lixo, de onde você pode devolver. É assinado com Developer ID e notarizado pela Apple."),
         ("Por que pede Acesso Total ao Disco?", "O macOS esconde algumas pastas (Mail, Mensagens, contêineres de apps) de todos os apps. Com o acesso a leitura fica completa; sem ele, o Legroom avisa o que não conseguiu ler."),
         ("Por que não está na Mac App Store?", "A App Store exige sandbox, o que impede ler o disco inteiro, listar processos e desinstalar apps por completo."),
         ("Como funcionam as atualizações?", "Legroom › Procurar Atualizações…, ou verificação automática se você permitir. São as mesmas versões notarizadas publicadas no GitHub.")],
    foot_made="Feito no Brasil por Rafael Bittencourt.", foot_links=[("GitHub", REPO), ("Versões", REPO + "/releases"), ("Issues", REPO + "/issues"), ("Licença", REPO + "/blob/main/LICENSE")],
)


def asset_v(name):
    """Short content hash, so browsers and the GitHub Pages CDN pick up changes."""
    return hashlib.sha1(open(os.path.join(OUT, "assets", name), "rb").read()).hexdigest()[:8]


def page(t):
    R = "../" if t["path"] else ""
    lang_img = "en" if t["lang"] == "en" else "pt-BR"
    e = html.escape
    canonical = SITE + t["path"]
    other_url = SITE + t["other"]
    nav = "".join(f'<a href="{h}">{e(l)}</a>' for h, l in t["nav"])
    stars_btn = f'<a class="btn btn-ghost btn-sm" href="{REPO}" aria-label="GitHub">{GITHUB}<span class="lbl">GitHub</span><span class="stars" data-stars hidden>{STAR}<b></b></span></a>'
    trust = "".join(f"<span>{CHECK}{e(x)}</span>" for x in t["trust"])
    un = "".join(f'<li><span class="bx"></span><span>{e(p)}</span><span class="sz">{e(s)}</span></li>' for p, s in t["un_items"])
    ckdefs = "".join(f'<div class="def{"" if on else " off"}"><small>{e(n)}</small><b>{e(v)}</b></div>' for n, v, on in t["ck_defs"])
    ckitems = "".join(f'<div class="srow k{k}"><code>{e(lbl)}</code><span>{e(sub)}</span><em>{e(tag)}</em></div>' for lbl, sub, tag, k in t["ck_items"])
    rows = "".join(f'<div class="row"><b>{e(n)}{f"<span class=pill>{e(tag)}</span>" if tag else ""}</b><span>{e(s)}</span><div class="bar"><i style="--w:{w}%"></i></div></div>' for n, s, w, tag in t["cl_rows"])
    metrics = "".join(f'<div class="metric"><small>{e(n)}</small><b><span data-count="{v.replace(",", ".")}" data-dec="{1 if "," in v or "." in v else 0}">0</span><i>{suf}</i></b></div>' for n, v, suf in t["ov_m"])
    dupes = "".join(f'<div class="dupe">{n}</div>' for n in ["IMG_2041", "report.pdf", "song.m4a", "deck.key", "deck.key", "IMG_2041", "song.m4a", "report.pdf"])
    tabs = "".join(f'<button class="tab" role="tab" aria-selected="{"true" if i == 0 else "false"}" data-caption="{e(c)}">{e(l)}<span class="prog"></span></button>' for i, (l, _, c) in enumerate(t["tabs"]))
    imgs = "".join(f'<img src="{R}assets/{k}-{lang_img}.webp" alt="{e(l)}" width="1600" height="1085" loading="lazy" decoding="async"{" class=on" if i == 0 else ""}>' for i, (l, k, _) in enumerate(t["tabs"]))
    words = " ".join(f'<span class="w{" g" if g else ""}">{e(w)}</span>' for w, g in t["manifesto"])
    rules = "".join(f'<div class="rule rv d{i % 4}"><b>{e(a)}</b><p>{e(b)}</p></div>' for i, (a, b) in enumerate(t["rules"]))
    facts = "".join(f'<div class="fact rv d{i}"><b>{a}</b><p>{e(b)}</p></div>' for i, (a, b) in enumerate(t["facts"]))
    faq = "".join(f"<details><summary>{e(q)}</summary><p>{e(a)}</p></details>" for q, a in t["faq"])
    foot = "".join(f'<a href="{u}">{e(l)}</a>' for l, u in t["foot_links"])
    ld = json.dumps({
        "@context": "https://schema.org", "@type": "SoftwareApplication", "name": "Legroom",
        "operatingSystem": "macOS 14 or later", "applicationCategory": "UtilitiesApplication",
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
        "description": t["desc"], "url": canonical, "downloadUrl": LATEST,
        "license": "https://opensource.org/licenses/MIT", "codeRepository": REPO, "inLanguage": t["lang"],
        "image": SITE + "assets/og.png", "author": {"@type": "Person", "name": "Rafael Bittencourt"},
    }, ensure_ascii=False)
    term = (
        '<span class="k">▸ Map</span> · full scan of <span class="s">/</span>\n'
        '  <span class="c">fts(3) · physical walk · allocated sizes</span>\n'
        '  3,071,882 files · 368.94 GB · 2 min 31 s\n'
        '  saved map: 3.97M nodes → 35 MB <span class="c">(LZFSE)</span>\n\n'
        '<span class="k">▸ Apps</span> · uninstall <span class="s">Nod</span>\n'
        '  <span class="c">dev.nod.desktop + helpers · exact names only</span>\n'
        '  ~/.nod-desktop                       4.83 GB\n'
        '  ~/Library/Application Support/nod    1.88 GB\n'
        '  ~/Downloads/nod-arm64.dmg            337 MB\n'
        '  → 7 items, 8.1 GB moved to the Trash <span class="c">(never deleted)</span>'
    )
    return f"""<!doctype html>
<html lang="{t['lang']}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{e(t['title'])}</title>
<meta name="description" content="{e(t['desc'])}">
<link rel="canonical" href="{canonical}">
<link rel="alternate" hreflang="{t['lang']}" href="{canonical}">
<link rel="alternate" hreflang="{t['other_hreflang']}" href="{other_url}">
<link rel="alternate" hreflang="x-default" href="{SITE}">
<meta name="theme-color" content="#07070a">
<meta property="og:type" content="website">
<meta property="og:title" content="{e(t['title'])}">
<meta property="og:description" content="{e(t['desc'])}">
<meta property="og:url" content="{canonical}">
<meta property="og:image" content="{SITE}assets/og.png">
<meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" type="image/png" href="{R}assets/favicon.png">
<link rel="apple-touch-icon" href="{R}assets/icon-180.png">
<link rel="stylesheet" href="{R}assets/site.css?v={asset_v("site.css")}">
<link rel="preload" as="image" href="{R}assets/overview-{lang_img}.webp" fetchpriority="high">
<script type="application/ld+json">{ld}</script>
</head>
<body>
<a class="skip" href="#main">{e(t['skip'])}</a>
<header class="nav">
  <a class="brand" href="{R if R else './'}"><img src="{R}assets/icon-180.png" alt="" width="28" height="28">Legroom</a>
  <nav class="links" aria-label="Sections">{nav}</nav>
  <a class="lang" href="{R}{t['other']}" hreflang="{t['other_hreflang']}" lang="{t['other_hreflang']}">{e(t['other_label'])}</a>
  {stars_btn}
  <a class="btn btn-primary btn-sm" href="{LATEST}" data-dl>{e(t['download'])}</a>
</header>

<main id="main">
<section class="hero" aria-labelledby="h1" style="padding-top:150px">
  <div class="tree" aria-hidden="true"></div>
  <div class="wrap hero-in">
    <span class="eyebrow"><span class="dot"></span>{e(t['eyebrow'])}</span>
    <h1 id="h1">{t['h1']}</h1>
    <p class="lead">{e(t['lead'])}</p>
    <div class="ctas">
      <a class="btn btn-primary" href="{LATEST}" data-dl>{APPLE}{e(t['cta'])}</a>
      <a class="btn btn-ghost" href="{REPO}">{GITHUB}{e(t['cta2'])}<span class="stars" data-stars hidden>{STAR}<b></b></span></a>
    </div>
    <p class="meta">{t['meta'].format(v=VERSION, s=SIZE)}</p>
  </div>
  <div class="stage">
    <div class="chip c1">{t['chip1']}</div>
    <div class="chip c2">{t['chip2']}</div>
    <div class="window"><img src="{R}assets/overview-{lang_img}.webp" alt="{e(t['shot_alt'])}" width="1600" height="1085" fetchpriority="high"></div>
  </div>
  <div class="wrap trust">{trust}</div>
</section>

<section id="features" aria-labelledby="f-h">
  <div class="wrap">
    <div class="head rv"><span class="kicker">{e(t['f_kicker'])}</span><h2 id="f-h">{e(t['f_h'])}</h2><p>{e(t['f_p'])}</p></div>
    <div class="bento">
      <article class="cell w4 rv">
        <span class="tag">{e(t['map_tag'])}</span><h3>{e(t['map_h'])}</h3><p>{e(t['map_p'])}</p>
        <div class="viz"><div class="mini-tree" data-items='{html.escape(json.dumps(MINI_TREE), quote=True)}' aria-hidden="true"></div></div>
      </article>
      <article class="cell rv d1" data-enter>
        <span class="tag">{e(t['ov_tag'])}</span><h3>{e(t['ov_h'])}</h3><p>{e(t['ov_p'])}</p>
        <div class="viz"><div class="ring" style="--to:64" data-v="{e(t['ov_ring'])}" aria-hidden="true"></div><div class="metrics">{metrics}</div></div>
      </article>
      <article class="cell w3 rv" data-enter>
        <span class="tag">{e(t['un_tag'])}</span><h3>{e(t['un_h'])}</h3><p>{e(t['un_p'])}</p>
        <div class="viz"><ul class="ulist" aria-hidden="true">{un}</ul>
        <div class="utotal"><span>{e(t['un_total'])}</span><b data-utotal data-v="{e(t['un_total_v'])}">{e(t['un_total_v'])}</b></div></div>
      </article>
      <article class="cell w3 rv d1" data-enter>
        <span class="tag">{e(t['cl_tag'])}</span><h3>{e(t['cl_h'])}</h3><p>{e(t['cl_p'])}</p>
        <div class="viz rows">{rows}</div>
      </article>
      <article class="cell w3 rv">
        <span class="tag">{e(t['cu_tag'])}</span><h3>{e(t['cu_h'])}</h3><p>{e(t['cu_p'])}</p>
        <div class="viz"><div class="dupes" aria-hidden="true">{dupes}</div></div>
      </article>
      <article class="cell w3 rv d1">
        <span class="tag">{e(t['wd_tag'])}</span><h3>{e(t['wd_h'])}</h3><p>{e(t['wd_p'])}</p>
        <div class="viz widgets"><img src="{R}assets/widget-small.webp" alt="" width="416" height="416" loading="lazy" class="ws"><img src="{R}assets/widget-medium.webp" alt="" width="776" height="416" loading="lazy" class="wm"></div>
      </article>
      <article class="cell w6 split rv" data-enter>
        <div><span class="tag">{e(t['ck_tag'])}</span><h3>{e(t['ck_h'])}</h3><p>{e(t['ck_p'])}</p></div>
        <div class="viz"><div class="defs" aria-hidden="true">{ckdefs}</div><div class="srows" aria-hidden="true">{ckitems}</div></div>
      </article>
    </div>
  </div>
</section>

<section id="tour" aria-labelledby="t-h">
  <div class="wrap show">
    <div class="head center rv"><span class="kicker">{e(t['t_kicker'])}</span><h2 id="t-h">{e(t['t_h'])}</h2><p>{e(t['t_p'])}</p></div>
    <div class="tabs" role="tablist">{tabs}</div>
    <div class="screens rv">{imgs}</div>
    <p class="caption" aria-live="polite"></p>
  </div>
</section>

<section id="principles" aria-labelledby="p-h">
  <div class="wrap">
    <span class="kicker">{e(t['p_kicker'])}</span>
    <h2 id="p-h" class="manifesto" style="margin-top:18px">{words}</h2>
    <div class="rules">{rules}</div>
  </div>
</section>

<section aria-labelledby="hood-h">
  <div class="wrap">
    <div class="head rv"><span class="kicker">{e(t['h_kicker'])}</span><h2 id="hood-h">{e(t['h_h'])}</h2><p>{e(t['h_p'])}</p></div>
    <div class="hood">
      <div class="term rv" data-enter><div class="bar"><i></i><i></i><i></i></div><pre aria-label="Example output">{term}</pre></div>
      <div class="facts">{facts}</div>
    </div>
  </div>
</section>

<section id="open-source" class="oss" aria-labelledby="o-h">
  <div class="wrap">
    <div class="oss-card rv">
      <p class="mono">{e(t['o_mono'])}</p>
      <h2 id="o-h">{e(t['o_h'])}</h2>
      <p>{e(t['o_p'])}</p>
      <div class="ctas">
        <a class="btn btn-primary" href="{REPO}">{GITHUB}{e(t['o_cta'])}<span class="stars" data-stars hidden>{STAR}<b></b></span></a>
        <a class="btn btn-ghost" href="{LATEST}" data-dl>{APPLE}{e(t['o_cta2'])}</a>
      </div>
    </div>
  </div>
</section>

<section aria-labelledby="faq-h">
  <div class="wrap faq">
    <div class="head center"><h2 id="faq-h">{e(t['faq_h'])}</h2></div>
    {faq}
  </div>
</section>
</main>

<footer>
  <div class="wrap foot"><span>{e(t['foot_made'])}</span><nav aria-label="Footer">{foot}<a href="{R}{t['other']}" hreflang="{t['other_hreflang']}">{e(t['other_label'])}</a></nav></div>
  <div class="giant" aria-hidden="true">Legroom</div>
</footer>
<script src="{R}assets/site.js?v={asset_v("site.js")}" defer></script>
</body>
</html>
"""


def main():
    os.makedirs(os.path.join(OUT, "pt"), exist_ok=True)
    open(os.path.join(OUT, "index.html"), "w").write(page(EN))
    open(os.path.join(OUT, "pt", "index.html"), "w").write(page(PT))
    open(os.path.join(OUT, "robots.txt"), "w").write(f"User-agent: *\nAllow: /\nSitemap: {SITE}sitemap.xml\n")
    open(os.path.join(OUT, "sitemap.xml"), "w").write(f"""<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
  <url><loc>{SITE}</loc><xhtml:link rel="alternate" hreflang="pt-BR" href="{SITE}pt/"/></url>
  <url><loc>{SITE}pt/</loc><xhtml:link rel="alternate" hreflang="en" href="{SITE}"/></url>
</urlset>
""")
    # GitHub Pages: serve files as-is (no Jekyll processing)
    open(os.path.join(OUT, ".nojekyll"), "w").write("")
    print("✓ docs/index.html, docs/pt/index.html")


if __name__ == "__main__":
    main()
