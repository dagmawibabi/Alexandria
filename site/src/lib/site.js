// @ts-nocheck
/** Wires up every control on the page. Runs once in the browser; returns its cleanup. */
export function initSite() {
  const life = new AbortController();
  const signal = life.signal;
  let alive = true;

  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch { /* per-viewer convenience only */ } },
  };
  const el = (tag, props = {}, kids = []) => {
    const n = Object.assign(document.createElement(tag), props);
    kids.forEach((k) => n.append(k));
    return n;
  };
  const shot = (name) => `/assets/shots/${name}.webp`;

  // This site has no service worker, so one found here in dev was left by another
  // project on the same localhost port, and would otherwise keep requesting its own file.
  if (import.meta.env.DEV && navigator.serviceWorker) {
    navigator.serviceWorker.getRegistrations().then((rs) => rs.forEach((r) => r.unregister()));
  }

  /* ---------- control clicks: a short tick from the Web Audio API, off by default ---------- */
  let audio = null;
  let clicks = store.get('clicks') === '1';
  const clickBtn = $('.click-toggle');
  const tick = (freq = 2100, gain = .05) => {
    if (!clicks) return;
    audio ||= new (window.AudioContext || window.webkitAudioContext)();
    const t = audio.currentTime;
    const o = audio.createOscillator();
    const g = audio.createGain();
    o.type = 'square';
    o.frequency.setValueAtTime(freq, t);
    o.frequency.exponentialRampToValueAtTime(freq * .4, t + .02);
    g.gain.setValueAtTime(gain, t);
    g.gain.exponentialRampToValueAtTime(.0001, t + .03);
    o.connect(g).connect(audio.destination);
    o.start(t);
    o.stop(t + .035);
  };
  const buzz = () => { if (navigator.vibrate) { try { navigator.vibrate(6); } catch { /* unsupported */ } } };
  const detent = () => { tick(); buzz(); };
  clickBtn.setAttribute('aria-pressed', clicks);
  clickBtn.addEventListener('click', () => {
    clicks = !clicks;
    clickBtn.setAttribute('aria-pressed', clicks);
    store.set('clicks', clicks ? '1' : '0');
    tick(1500, .07);
  });
  document.addEventListener('click', (e) => {
    if (e.target.closest('button, a.btn, input[type=checkbox]') && !e.target.closest('.click-toggle')) tick(1700, .035);
  }, { signal });

  /* ---------- wordmark: one word, fitted edge to edge, stamped in on load ---------- */
  const word = $('.word');
  const inner = $('.word-inner');
  const fitWord = () => {
    word.style.fontSize = '100px';
    const w = inner.getBoundingClientRect().width;
    const room = word.clientWidth;
    if (w > 0 && room > 0) word.style.fontSize = `${Math.floor((100 * room / w) * 10) / 10}px`;
  };
  fitWord();
  addEventListener('resize', fitWord, { signal });
  if (document.fonts?.ready) document.fonts.ready.then(fitWord);

  /* ---------- screws, placed at the corners of every plate; each one turns its own way ---------- */
  $$('.plate').forEach((p) => {
    [['14px', '14px', 'auto', 'auto'], ['14px', 'auto', 'auto', '14px'], ['auto', '14px', '14px', 'auto'], ['auto', 'auto', '14px', '14px']].forEach(([top, left, bottom, right]) => {
      const s = el('i', { className: 'screw' });
      Object.assign(s.style, { top, left, bottom, right, rotate: `${Math.round(Math.random() * 180)}deg` });
      s.style.setProperty('--turn', `${Math.random() > .5 ? '' : '-'}${180 + Math.round(Math.random() * 180)}deg`);
      s.setAttribute('aria-hidden', 'true');
      p.append(s);
    });
  });

  /* ---------- the ring: a five-position rotary selector for the phone's tabs ---------- */
  const TABS = [
    { name: 'Library', shot: 'library', alt: 'The Library screen: a continue-reading card above a grid of book covers.', note: 'Your books, audiobooks and shows on one shelf.' },
    { name: 'Books', shot: 'books', alt: 'The Books screen: free EPUBs from Project Gutenberg with a Get EPUB button on each.', note: 'Free EPUBs from Project Gutenberg, and the Open Library catalogue.' },
    { name: 'Audio', shot: 'audio', alt: 'The Audiobooks screen: continue listening above your audiobook shelf.', note: 'Your audio files, plus free audiobooks from LibriVox and the Internet Archive.' },
    { name: 'Podcast', shot: 'podcasts', alt: 'The Podcasts screen: your shows with new-episode counts, above top charts.', note: 'Shows, charts and queues, with global radio one tab over.' },
    { name: 'Config', shot: 'config', alt: 'The Config screen: grouped settings for appearance, reading, listening and data.', note: 'Every setting, from page colours to voices and backups.' },
  ];
  TABS.forEach((t) => { new Image().src = shot(t.shot); });

  const dial = $('#dial');
  const knobRot = $('.knob-rot');
  const scale = $('.dial-scale');
  const STEP = 60;
  const START = -120;
  const NS = 'http://www.w3.org/2000/svg';
  const svg = (tag, attrs) => { const n = document.createElementNS(NS, tag); Object.entries(attrs).forEach(([k, v]) => n.setAttribute(k, v)); return n; };
  const polar = (deg, r) => { const a = (deg - 90) * Math.PI / 180; return [200 + r * Math.cos(a), 200 + r * Math.sin(a)]; };
  for (let deg = START - 20; deg <= -START + 20; deg += 5) {
    const major = (deg - START) % STEP === 0 && deg >= START && deg <= -START;
    const [x1, y1] = polar(deg, major ? 136 : 142);
    const [x2, y2] = polar(deg, major ? 156 : 150);
    scale.append(svg('line', { x1, y1, x2, y2, class: major ? 'major' : 'minor', 'data-i': major ? (deg - START) / STEP : '' }));
  }
  TABS.forEach((t, i) => {
    const deg = START + i * STEP;
    const [x, y] = polar(deg, 178);
    const label = svg('text', { x, y, 'data-i': i });
    label.textContent = t.name;
    scale.append(label);
  });

  const heroA = $('#hero-a');
  const heroB = $('#hero-b');
  const wiper = $('.wiper');
  let tab = 0;
  let swapping = 0;
  const showTab = (i, quiet) => {
    if (i === tab && !quiet) return;
    tab = i;
    const t = TABS[i];
    dial.setAttribute('aria-valuenow', i + 1);
    dial.setAttribute('aria-valuetext', t.name);
    $('#dial-name').textContent = t.name;
    $('#dial-note').textContent = t.note;
    $$('.major, text', scale).forEach((n) => n.classList.toggle('on', +n.dataset.i === i && n.dataset.i !== ''));
    if (quiet) return;
    const job = ++swapping;
    heroB.hidden = false;
    heroB.classList.remove('go');
    wiper.classList.remove('go');
    heroB.src = shot(t.shot);
    heroB.alt = t.alt;
    void heroB.offsetWidth;
    heroB.classList.add('go');
    wiper.classList.add('go');
    setTimeout(() => {
      if (job !== swapping) return;
      heroA.src = heroB.src;
      heroA.alt = t.alt;
      heroB.hidden = true;
      heroB.removeAttribute('alt');
      heroB.classList.remove('go');
      wiper.classList.remove('go');
    }, 440);
  };
  const setAngle = (a) => knobRot.style.setProperty('--a', `${a}deg`);
  const goTab = (i) => {
    const n = Math.max(0, Math.min(TABS.length - 1, i));
    setAngle(START + n * STEP);
    if (n !== tab) { detent(); showTab(n); }
  };
  showTab(0, true);
  setAngle(START);

  let dragging = false;
  const angleAt = (e) => {
    const r = dial.getBoundingClientRect();
    let a = Math.atan2(e.clientX - (r.left + r.width / 2), -(e.clientY - (r.top + r.height / 2))) * 180 / Math.PI;
    return a;
  };
  dial.addEventListener('pointerdown', (e) => {
    const label = e.target.closest('text');
    if (label) { goTab(+label.dataset.i); return; }
    dragging = true;
    dial.setPointerCapture(e.pointerId);
    dial.classList.add('dragging');
  });
  dial.addEventListener('pointermove', (e) => {
    if (!dragging) return;
    const a = Math.max(START, Math.min(-START, angleAt(e)));
    setAngle(a);
    const n = Math.round((a - START) / STEP);
    if (n !== tab) { detent(); showTab(n); }
  });
  const dialUp = () => {
    if (!dragging) return;
    dragging = false;
    dial.classList.remove('dragging');
    setAngle(START + tab * STEP);
  };
  dial.addEventListener('pointerup', dialUp);
  dial.addEventListener('pointercancel', dialUp);
  dial.addEventListener('keydown', (e) => {
    const map = { ArrowRight: 1, ArrowUp: 1, ArrowLeft: -1, ArrowDown: -1 };
    if (e.key in map) { e.preventDefault(); goTab(tab + map[e.key]); }
    if (e.key === 'Home') { e.preventDefault(); goTab(0); }
    if (e.key === 'End') { e.preventDefault(); goTab(TABS.length - 1); }
  });

  /* ---------- range inputs paint their own filled track ---------- */
  const paint = (r) => r.style.setProperty('--fill', `${(r.value - r.min) / (r.max - r.min) * 100}%`);
  const fader = (id, fn) => {
    const r = $(id);
    const out = r.parentElement.querySelector('output');
    let last = r.value;
    const run = () => {
      paint(r);
      out.textContent = fn(+r.value);
      if (r.value !== last) { last = r.value; tick(2400, .018); }
    };
    r.addEventListener('input', run);
    run();
  };

  /* ---------- reader bench ---------- */
  const SURFACES = [
    ['Paper', '#F2EFE8', '#1C1B19'], ['White', '#FFFFFF', '#111111'], ['Sepia', '#F1E4C9', '#47392A'], ['Fog', '#E3E5E2', '#222624'],
    ['Sage', '#DCE3D5', '#26301F'], ['Concrete', '#BDBCB8', '#151515'], ['Graphite', '#2A2B2D', '#D9D8D3'], ['Slate', '#1B2128', '#C9D1DA'],
    ['Amber CRT', '#120F08', '#E7B867'], ['Phosphor', '#07110A', '#86E39A'], ['OLED', '#000000', '#B8B8B8'],
  ];
  const FACES = ['Literata', 'Source Serif 4', 'EB Garamond', 'Crimson Pro', 'Newsreader', 'IBM Plex Serif', 'Inter', 'IBM Plex Sans', 'Space Grotesk', 'Atkinson Hyperlegible', 'JetBrains Mono', 'IBM Plex Mono'];
  const MARKERS = ['#FFD54A', '#FF8A65', '#7FD1AE', '#7FB2FF', '#D59BFF'];
  const page = $('#page');
  const text = $('#page-text');
  const pressOne = (group, chosen) => $$('button', group).forEach((b) => b.setAttribute('aria-pressed', b === chosen));

  // The reading faces only load when someone reaches the bench.
  const loadFaces = () => {
    const fams = ['Literata:ital,wght@0,400;0,700', 'Source+Serif+4:wght@400;700', 'EB+Garamond:wght@400;700', 'Crimson+Pro:wght@400;700', 'Newsreader:wght@400;700', 'IBM+Plex+Serif:wght@400;700', 'Inter:wght@400;700', 'IBM+Plex+Sans:wght@400;700', 'Atkinson+Hyperlegible:wght@400;700', 'IBM+Plex+Mono:wght@400;500;700'];
    document.head.append(el('link', { rel: 'stylesheet', href: `https://fonts.googleapis.com/css2?${fams.map((f) => `family=${f}`).join('&')}&display=swap` }));
  };
  const nearFaces = new IntersectionObserver((es) => {
    if (es.some((e) => e.isIntersecting)) { loadFaces(); nearFaces.disconnect(); }
  }, { rootMargin: '900px' });
  nearFaces.observe($('#reader'));

  const luminanceOf = (hex) => {
    const c = [1, 3, 5].map((i) => parseInt(hex.substr(i, 2), 16) / 255).map((v) => (v <= .03928 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4));
    return .2126 * c[0] + .7152 * c[1] + .0722 * c[2];
  };
  const applySurface = ([name, bg, fg]) => {
    page.style.setProperty('--pg', bg);
    page.style.setProperty('--pg-ink', fg);
    page.classList.toggle('page-dark', luminanceOf(bg) < .2);
    $('#page-surface').textContent = name;
  };
  const surfaces = $('#surfaces');
  SURFACES.forEach((s, i) => {
    const b = el('button', { type: 'button', className: 'surface', title: s[0] }, ['Aa', el('small', { textContent: s[0] })]);
    b.style.setProperty('--c', s[1]);
    b.style.setProperty('--t', s[2]);
    b.setAttribute('aria-pressed', i === 0);
    b.setAttribute('aria-label', `${s[0]} surface`);
    b.addEventListener('click', () => { pressOne(surfaces, b); applySurface(s); });
    surfaces.append(b);
  });
  applySurface(SURFACES[0]);

  let face = 'Literata';
  let size = 19;
  const status = () => { $('#page-face').textContent = `${face}, ${size} pt`; };
  const faces = $('#faces');
  FACES.forEach((f, i) => {
    const b = el('button', { type: 'button', className: 'chip', textContent: f });
    b.style.fontFamily = `"${f}", var(--body)`;
    b.setAttribute('aria-pressed', i === 0);
    b.addEventListener('click', () => {
      pressOne(faces, b);
      face = f;
      text.style.setProperty('--face', `"${f}"`);
      status();
    });
    faces.append(b);
  });
  fader('#f-size', (v) => { size = v; text.style.setProperty('--size', v); status(); return v; });
  fader('#f-lead', (v) => { text.style.setProperty('--lead', v / 10); return (v / 10).toFixed(1); });
  fader('#f-marg', (v) => { text.style.setProperty('--pad', `${v}px`); return v; });
  fader('#f-warm', (v) => { page.style.setProperty('--warm', v / 100); return v; });
  $('#s-just').addEventListener('change', (e) => text.classList.toggle('just', e.target.checked));
  $('#s-indent').addEventListener('change', (e) => text.classList.toggle('indent', e.target.checked));

  let marker = 0;
  const markers = $('#markers');
  MARKERS.forEach((c, i) => {
    const b = el('button', { type: 'button', className: 'marker' });
    b.style.setProperty('--c', c);
    b.setAttribute('aria-pressed', i === 0);
    b.setAttribute('aria-label', `Marker colour ${i + 1}`);
    b.addEventListener('click', () => { pressOne(markers, b); marker = i; });
    markers.append(b);
  });
  const markSelection = () => {
    const sel = getSelection();
    if (!sel || sel.isCollapsed || !sel.rangeCount) return;
    const range = sel.getRangeAt(0);
    if (!text.contains(range.commonAncestorContainer)) return;
    const m = el('mark');
    m.dataset.c = marker;
    try {
      range.surroundContents(m);
      sel.removeAllRanges();
      tick(1300, .04);
    } catch { /* the selection crosses a paragraph or another mark, so leave it as it is */ }
  };
  text.addEventListener('pointerup', () => setTimeout(markSelection, 0));
  text.addEventListener('click', (e) => {
    const m = e.target.closest('mark');
    if (!m || !getSelection().isCollapsed) return;
    m.replaceWith(...m.childNodes);
    text.normalize();
  });

  /* ---------- swipe, auto-scroll and tap zones ---------- */
  const PASSAGES = [
    'Call me Ishmael. Some years ago, never mind how long precisely, having little or no money in my purse, and nothing particular to interest me on shore, I thought I would sail about a little and see the watery part of the world.',
    'It is a way I have of driving off the spleen and regulating the circulation. Whenever I find myself growing grim about the mouth; whenever it is a damp, drizzly November in my soul;',
    'whenever I find myself involuntarily pausing before coffin warehouses, and bringing up the rear of every funeral I meet; then, I account it high time to get to sea as soon as I can.',
    'This is my substitute for pistol and ball. With a philosophical flourish Cato throws himself upon his sword; I quietly take to the ship. There is nothing surprising in this.',
    'If they but knew it, almost all men in their degree, some time or other, cherish very nearly the same feelings towards the ocean with me.',
  ];
  const swipe = $('#swipe');
  PASSAGES.forEach((p, i) => {
    const bar = el('div', { className: 'bar-s' }, [el('i')]);
    bar.firstChild.style.width = `${(i + 1) / PASSAGES.length * 100}%`;
    swipe.append(el('div', { className: 'card-s' }, [
      el('span', { textContent: 'Loomings' }),
      el('p', { textContent: p }),
      el('footer', {}, [el('span', { textContent: `000${i + 1} / 000${PASSAGES.length}` }), el('span', { textContent: `${PASSAGES.length - 1 - i} left in chapter` })]),
      bar,
    ]));
  });
  let lastCard = 0;
  swipe.addEventListener('scroll', () => {
    const n = Math.round(swipe.scrollTop / swipe.clientHeight);
    if (n !== lastCard) { lastCard = n; detent(); }
  }, { passive: true });

  const auto = $('#auto');
  const autoText = $('#auto-text');
  autoText.append(...[...PASSAGES, ...PASSAGES].map((p) => el('p', { textContent: p })));
  let speed = 40;
  let held = false;
  let autoY = 0;
  let autoLast = 0;
  let autoSeen = false;
  fader('#auto-speed', (v) => { speed = v; return `${v} px/s`; });
  auto.addEventListener('pointerdown', () => { held = true; });
  addEventListener('pointerup', () => { held = false; }, { signal });
  auto.addEventListener('pointerleave', () => { held = false; });
  new IntersectionObserver(([e]) => { autoSeen = e.isIntersecting; }).observe(auto);
  const autoFrame = (now) => {
    const dt = Math.min(64, now - autoLast);
    autoLast = now;
    if (autoSeen && !held && !reduced) {
      autoY += speed * dt / 1000;
      const half = autoText.scrollHeight / 2;
      if (half > 0 && autoY > half) autoY -= half;
      autoText.style.transform = `translateY(${-autoY}px)`;
    }
    if (alive) requestAnimationFrame(autoFrame);
  };
  requestAnimationFrame(autoFrame);

  $$('.zone').forEach((z) => z.addEventListener('click', () => {
    z.classList.add('hit');
    detent();
    setTimeout(() => z.classList.remove('hit'), 240);
  }));

  /* ---------- selection menu ---------- */
  const SELECTION = [
    ['Define', 'A dictionary entry and the Wikipedia summary, without leaving the page.'],
    ['Explain', 'The AI companion explains the passage where it sits in the book.'],
    ['Speak', 'Reads the selection aloud in the voice you picked.'],
    ['Note', 'Saves a highlight with your own note attached.'],
    ['Card', 'Opens the passage as a share card.'],
    ['Find', 'Searches the rest of the book for those words.'],
    ['Copy', 'Copies the text, as you would expect.'],
  ];
  const selmenu = $('#selmenu');
  const selOut = $('#selmenu-out');
  const pickSel = (b, t) => { pressOne(selmenu, b); selOut.textContent = t; };
  SELECTION.forEach(([n, t], i) => {
    const b = el('button', { type: 'button', textContent: n });
    b.setAttribute('aria-pressed', false);
    b.addEventListener('click', () => pickSel(b, t));
    b.addEventListener('pointerenter', (e) => { if (e.pointerType === 'mouse') pickSel(b, t); });
    selmenu.append(b);
    if (i === 1) pickSel(b, t);
  });

  /* ---------- tuner: the listening bands ---------- */
  const BANDS = [
    { name: 'Audiobooks', a: ['audio', 'Your audiobook shelf, with continue listening at the top.'], b: ['player', 'The player: cover, chapter, speed, sleep timer, chapters and read along.'],
      items: ['Add your own audio files, or stream free books from LibriVox and the Internet Archive.', 'Download whole books or single chapters for offline listening.', 'Speed control, chapters, a sleep timer, ratings and timestamped notes.', 'Attach the ebook to read along, and the page follows the narrator.'] },
    { name: 'Read aloud', a: ['voices', 'The voice picker: device voice, Addis AI and ElevenLabs.'], b: ['zen-reader', 'The reader in the Zen look with the listening control in its toolbar.'],
      items: ['Turn any book into speech, and keep listening with the screen off.', "Your phone's own voice is free and works offline.", 'Add a key for ElevenLabs voices in 30+ languages, or Addis AI for Amharic, Afaan Oromo and Tigrinya.', 'Search voices by name, language or accent, and set the speed and pitch.'] },
    { name: 'Podcasts', a: ['podcasts', 'The podcast shelf with new-episode counts above the top charts.'], b: ['history', 'A search bar with its list of recent searches open.'],
      items: ['Search the Apple directory, browse top charts by genre, or add any show by RSS link.', 'A reorderable queue, downloads, and played tracking.', 'New-episode alerts on the schedule you set, checked in the background.', 'Rate, favourite, take notes on and file each show.'] },
    { name: 'Radio', a: ['radio', 'Global radio: stations listed with their genre and country.'], b: null,
      items: ['Stations from around the world, sorted by what people play most.', 'Pick a country from a list with flags, or narrow it by genre.', 'Favourites and recently played are one tap away.', 'If the main directory is down, a fallback directory takes over by itself.'] },
  ];
  const tuner = $('#tuner');
  const stops = $('.tuner-stops');
  const needle = $('.needle');
  const bandBox = $('.band');
  const bandA = $('#band-a');
  const bandB = $('#band-b');
  let band = -1;
  const showBand = (i) => {
    if (i === band) return;
    const first = band < 0;
    band = i;
    const b = BANDS[i];
    tuner.setAttribute('aria-valuenow', i + 1);
    tuner.setAttribute('aria-valuetext', b.name);
    $$('button', stops).forEach((s, n) => s.classList.toggle('on', n === i));
    const fill = () => {
      $('#band-title').textContent = b.name;
      $('#band-list').replaceChildren(...b.items.map((t) => el('li', { textContent: t })));
      bandA.src = shot(b.a[0]); bandA.alt = b.a[1];
      bandBox.classList.toggle('single', !b.b);
      if (b.b) { bandB.src = shot(b.b[0]); bandB.alt = b.b[1]; } else { bandB.removeAttribute('src'); bandB.alt = ''; }
      bandBox.classList.remove('switching');
    };
    if (first) { fill(); return; }
    bandBox.classList.add('switching');
    setTimeout(fill, 170);
  };
  const needleAt = (i) => needle.style.setProperty('--x', `${(i + .5) / BANDS.length * 100}%`);
  const goBand = (i) => {
    const n = Math.max(0, Math.min(BANDS.length - 1, i));
    needleAt(n);
    if (n !== band) { detent(); showBand(n); }
  };
  BANDS.forEach((b, i) => {
    const s = el('button', { type: 'button', textContent: b.name, tabIndex: -1 });
    s.addEventListener('click', () => goBand(i));
    stops.append(s);
  });
  showBand(0);
  needleAt(0);
  let tuning = false;
  const tuneTo = (e) => {
    const r = tuner.getBoundingClientRect();
    const f = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width));
    needle.style.setProperty('--x', `${f * 100}%`);
    const n = Math.min(BANDS.length - 1, Math.floor(f * BANDS.length));
    if (n !== band) { detent(); showBand(n); }
  };
  tuner.addEventListener('pointerdown', (e) => {
    tuning = true;
    tuner.setPointerCapture(e.pointerId);
    tuner.classList.add('dragging');
    tuneTo(e);
  });
  tuner.addEventListener('pointermove', (e) => { if (tuning) tuneTo(e); });
  const tuneUp = () => {
    if (!tuning) return;
    tuning = false;
    tuner.classList.remove('dragging');
    needleAt(band);
  };
  tuner.addEventListener('pointerup', tuneUp);
  tuner.addEventListener('pointercancel', tuneUp);
  tuner.addEventListener('keydown', (e) => {
    const map = { ArrowRight: 1, ArrowUp: 1, ArrowLeft: -1, ArrowDown: -1 };
    if (e.key in map) { e.preventDefault(); goBand(band + map[e.key]); }
  });

  /* ---------- goal gauge ---------- */
  const gauge = $('#gauge');
  fader('#gauge-goal', (v) => {
    gauge.style.setProperty('--v', Math.min(1, 56 / v));
    $('#gauge-of').textContent = `of ${v} min`;
    return `${v} min`;
  });

  /* ---------- share cards, using the app's eight styles ---------- */
  const STYLES = [
    { n: 'Spec', bg: '#EDEBE6', fg: '#151515', f: 'Space Grotesk' },
    { n: 'Mono', bg: '#000000', fg: '#FFFFFF', f: 'JetBrains Mono' },
    { n: 'Marker', bg: '#FAF9F6', fg: '#151515', f: 'Literata', c: 'marker' },
    { n: 'Noir', bg: '#0E0E0E', fg: '#F0EEE8', f: 'EB Garamond' },
    { n: 'Signal', bg: '#FF5A1F', fg: '#141414', f: 'Space Grotesk' },
    { n: 'Blueprint', bg: '#1D3F8F', fg: '#E8EEFF', f: 'IBM Plex Mono', c: 'grid' },
    { n: 'Paper', bg: '#F1E4C9', fg: '#3E3020', f: 'Crimson Pro' },
    { n: 'Cover', bg: '#111111', fg: '#FFFFFF', f: 'Newsreader', c: 'cover' },
  ];
  const QUOTES = [
    ['whenever it is a damp, drizzly November in my soul; then, I account it high time to get to sea as soon as I can.', 'Moby-Dick', 'Herman Melville'],
    ['Beware; for I am fearless, and therefore powerful.', 'Frankenstein', 'Mary Shelley'],
    ['I went to the woods because I wished to live deliberately.', 'Walden', 'Henry David Thoreau'],
    ['Listen to them, the children of the night. What music they make!', 'Dracula', 'Bram Stoker'],
  ];
  const quote = $('#quote');
  const quoteText = $('#quote-text');
  const styles = $('#card-styles');
  const sizes = $('#card-sizes');
  let q = 0;
  const showQuote = () => {
    const [t, b, a] = QUOTES[q];
    quoteText.replaceChildren(el('span', { textContent: t }));
    $('#quote-book').textContent = b;
    $('#quote-author').textContent = a;
  };
  STYLES.forEach((s, i) => {
    const b = el('button', { type: 'button', className: 'chip', textContent: s.n });
    b.setAttribute('aria-pressed', i === 0);
    b.addEventListener('click', () => {
      pressOne(styles, b);
      quote.classList.remove('marker', 'grid', 'cover');
      if (s.c) quote.classList.add(s.c);
      quote.style.setProperty('--q-bg', s.bg);
      quote.style.setProperty('--q-fg', s.fg);
      quote.style.setProperty('--q-font', `"${s.f}"`);
    });
    styles.append(b);
  });
  [['1:1 post', ''], ['4:5 feed', 'wide-4x5'], ['9:16 story', 'wide-9x16']].forEach(([n, c], i) => {
    const b = el('button', { type: 'button', className: 'chip', textContent: n });
    b.setAttribute('aria-pressed', i === 0);
    b.addEventListener('click', () => {
      pressOne(sizes, b);
      quote.classList.remove('wide-4x5', 'wide-9x16');
      if (c) quote.classList.add(c);
    });
    sizes.append(b);
  });
  showQuote();
  $('#card-next').addEventListener('click', () => { q = (q + 1) % QUOTES.length; showQuote(); });

  /* ---------- accent, carried across the whole site ---------- */
  const ACCENTS = [
    ['Signal orange', '#FF5A1F'], ['Safety yellow', '#FFC300'], ['Klein blue', '#2D6BFF'], ['Instrument green', '#00A86B'], ['Stop red', '#E5243B'], ['Aluminium', '#9B9B93'],
    ['Violet', '#7B61FF'], ['Teal', '#00B3C7'], ['Magenta', '#FF4F9A'], ['Bronze', '#8A6A3B'], ['White', '#FFFFFF'],
  ];
  const accents = $('#accents');
  const applyAccent = ([name, hex], b) => {
    const light = luminanceOf(hex) > .5;
    const colours = [hex === '#FFFFFF' ? '#141414' : hex, hex !== '#FFFFFF' && light ? '#141414' : '#FFFFFF'];
    document.documentElement.style.setProperty('--signal', colours[0]);
    document.documentElement.style.setProperty('--on-signal', colours[1]);
    store.set('accentColours', JSON.stringify(colours));
    $('#accent-name').textContent = hex === '#FFFFFF' ? 'White, which follows the ink on a light page, just as the app does' : name;
    pressOne(accents, b);
    store.set('accent', name);
  };
  ACCENTS.forEach((a) => {
    const b = el('button', { type: 'button', className: 'accent', title: a[0] });
    b.style.setProperty('--c', a[1]);
    b.setAttribute('aria-label', a[0]);
    b.setAttribute('aria-pressed', false);
    b.addEventListener('click', () => applyAccent(a, b));
    accents.append(b);
  });
  const savedAccent = ACCENTS.findIndex((a) => a[0] === store.get('accent'));
  applyAccent(ACCENTS[Math.max(0, savedAccent)], accents.children[Math.max(0, savedAccent)]);

  /* ---------- Industrial and Zen comparison, with monochrome and dark ---------- */
  const compare = $('#compare');
  const cmpScreen = $('.screen', compare);
  const cmpA = $('#cmp-a');
  const setCmp = (v) => {
    const p = Math.max(0, Math.min(100, v));
    compare.style.setProperty('--p', `${p}%`);
    compare.setAttribute('aria-valuenow', Math.round(p));
    compare.setAttribute('aria-valuetext', `${Math.round(p)}% Zen`);
  };
  setCmp(50);
  let cmpDrag = false;
  const cmpTo = (e) => {
    const r = cmpScreen.getBoundingClientRect();
    setCmp((e.clientX - r.left) / r.width * 100);
  };
  compare.addEventListener('pointerdown', (e) => { cmpDrag = true; compare.setPointerCapture(e.pointerId); cmpTo(e); });
  compare.addEventListener('pointermove', (e) => { if (cmpDrag) cmpTo(e); });
  compare.addEventListener('pointerup', () => { cmpDrag = false; });
  compare.addEventListener('pointercancel', () => { cmpDrag = false; });
  compare.addEventListener('keydown', (e) => {
    const map = { ArrowRight: 5, ArrowUp: 5, ArrowLeft: -5, ArrowDown: -5 };
    if (e.key in map) {
      e.preventDefault();
      setCmp(+compare.getAttribute('aria-valuenow') + map[e.key]);
    }
  });
  const monoS = $('#s-mono');
  const darkS = $('#s-dark');
  const updateLook = () => {
    // The app's own screens for each combination; there is no light monochrome capture, so mono shows the dark one.
    cmpA.src = shot(monoS.checked ? 'mono' : darkS.checked ? 'library' : 'library-light');
    cmpA.alt = `The Library in the Industrial look${monoS.checked ? ', monochrome' : darkS.checked ? ', dark' : ''}.`;
    document.documentElement.classList.toggle('site-mono', monoS.checked);
  };
  monoS.addEventListener('change', updateLook);
  darkS.addEventListener('change', updateLook);

  /* ---------- data sheet ---------- */
  const SHEET = [
    ['Formats', ['PDF, EPUB and DOCX', 'PDFs reflow to text, or show their original pages', 'Open files from other apps with "Read in Alexandria"', 'Share files in with "Add to Alexandria"', 'Covers and details fetched from Open Library and Google Books', 'Edit book info and set your own cover']],
    ['Type', ['12 reading typefaces, including Atkinson Hyperlegible', 'Size from 11 to 40 pt', 'Leading, paragraph gap, tracking and weight', 'Margins, justified or ragged, indented paragraphs', 'Show or hide images']],
    ['Light', ['11 page surfaces, plus a custom page and ink colour', 'Separate day and night surfaces', 'Night mode that can follow the system', 'Warmth filter and super dim', 'Brightness control inside the app']],
    ['Motion', ['Auto-scroll from 5 to 400 px/s, pausing while you touch', 'Swipe mode: fit to screen or fixed words per card', 'Swipe up or sideways, with auto-advance by WPM', 'Tap zones for turning the page', 'Volume keys turn pages: choose the direction, or switch them off', 'Slide the screen edge for brightness or font size', 'Immersive mode, keep-awake, status line and clock']],
    ['Navigate', ['Table of contents', 'Search in book', 'Position slider and time left', 'Bookmarks, highlights and notes in one list']],
    ['Marks', ['Highlights in 5 marker colours', 'Notes on any highlight', 'Bookmarks you can rename', 'Ratings, favourites and reading status', 'Define with a dictionary and Wikipedia, right from the selection']],
    ['AI companion', ['Uses your own key from Google or Vercel AI Gateway', 'Gemini, GPT, Claude and Grok models, and search for more', 'Chat about a book or a passage', 'Explain a selection, recap what you read, or ask what a book is about', 'Spoiler guard based on how far you have read', 'Simple, clear or expert answers in your language', 'Usage log with tokens, characters and estimated cost']],
    ['Audiobooks', ['Your own audio files, or free books from LibriVox and the Internet Archive', 'Stream, or download whole books and single chapters', 'Downloads resume after a restart', 'Playback speed, chapters and sleep timer', 'Read along with the attached ebook', 'Timestamped notes, ratings and favourites', 'Background playback with lock-screen controls']],
    ['Read aloud', ['Your phone\'s voice, free and offline', 'ElevenLabs voices in 30+ languages, with your key', 'Addis AI voices for Amharic, Afaan Oromo and Tigrinya, with your key', 'Search voices by name, language or accent', 'Speed and pitch controls', 'Keeps reading with the screen off']],
    ['Podcasts', ['Search the Apple podcast directory', 'Top charts and genres', 'Add any show by RSS link', 'Subscriptions with new-episode counts', 'Reorderable queue and episode downloads', 'Background checks with new-episode alerts', 'Played tracking, plus marking older episodes as played', 'Share cards for shows and episodes']],
    ['Radio', ['Stations from around the world', 'Country picker with flags', 'Genres from news and talk to lo-fi and afrobeats', 'Favourites, recents, ratings and notes', 'Automatic fallback directory if the main one is down']],
    ['Find', ['Free EPUBs from Project Gutenberg, downloaded in one tap', 'Open Library catalogue search', 'A want-to-read list', 'Browse by topic, or hit Surprise me', 'Recent searches on every search bar, removable one by one']],
    ['Organise', ['Folders that hold books, audiobooks and shows together', 'Smart rows for favourites and items not in a folder', 'Folder covers made from what is inside, or your own picture', 'Grid or list, with adjustable columns and sorting', 'Filters for books, audiobooks, podcasts and radio']],
    ['Stats', ['Daily goal ring and streaks', 'Yearly goals for books and audiobooks, weekly for episodes', 'Time by kind, and 14-day bars', 'Per-book reading speed and time left', 'Four home-screen widgets with your own font and colours']],
    ['Share', ['8 card styles, from Spec to Blueprint', 'Sizes for posts, feeds and stories', 'Any background colour and typeface', 'Cards for excerpts, highlights and bookmarks', 'Cards for audiobooks, podcasts and stations']],
    ['Look', ['Industrial and Zen designs for every screen', 'Monochrome mode', 'Light, dark or system theme', '11 accents, or any colour from a full picker', 'Corner radius, five interface fonts and the dot grid', 'Haptics you can turn off']],
    ['Desktop', ['A Windows app as well as Android', 'Side rail of tabs and two-pane pages on wide windows', 'Arrow keys, Page Up, Page Down and Space turn pages; Esc steps back', 'Right-click for the same actions as a long press', 'Open books from File Explorer with Open with']],
    ['Your data', ['No account and no sign-in', 'Everything stored on your phone', 'Export or import everything as one JSON file', 'Catalogue pages saved on your phone, so they open when offline', 'Keys for AI and voices are yours and only needed for those features']],
  ];
  const sheetBody = $('#sheet-body');
  const groups = SHEET.map(([title, rows]) => {
    const items = rows.map((r) => el('li', { textContent: r }));
    const g = el('div', { className: 'sheet-group' }, [el('h3', { textContent: title }), el('ul', { className: 'sheet-rows' }, items)]);
    sheetBody.append(g);
    return { g, title, items, rows };
  });
  const none = el('p', { className: 'sheet-none', hidden: true });
  sheetBody.append(none);
  const qBox = $('#sheet-q');
  const qN = $('#sheet-n');
  const total = SHEET.reduce((a, [, r]) => a + r.length, 0);
  const paintHit = (li, text, term) => {
    if (!term) { li.textContent = text; return; }
    const at = text.toLowerCase().indexOf(term);
    if (at < 0) { li.textContent = text; return; }
    li.replaceChildren(text.slice(0, at), el('em', { textContent: text.slice(at, at + term.length) }), text.slice(at + term.length));
  };
  const filterSheet = () => {
    const term = qBox.value.trim().toLowerCase();
    let shown = 0;
    groups.forEach(({ g, title, items, rows }) => {
      const whole = term && title.toLowerCase().includes(term);
      let inGroup = 0;
      items.forEach((li, i) => {
        const hit = !term || whole || rows[i].toLowerCase().includes(term);
        li.hidden = !hit;
        paintHit(li, rows[i], term);
        if (hit) inGroup++;
      });
      g.hidden = inGroup === 0;
      shown += inGroup;
    });
    qN.textContent = term ? `${shown} of ${total}` : `${total} features`;
    none.hidden = shown > 0;
    none.textContent = shown ? '' : `Nothing matches "${qBox.value.trim()}". Try a shorter word.`;
  };
  qBox.addEventListener('input', filterSheet);
  filterSheet();

  /* ---------- screens open like a shutter as they arrive ---------- */
  const shutters = new IntersectionObserver((es) => {
    es.forEach((e) => {
      if (e.isIntersecting) { e.target.classList.add('in'); shutters.unobserve(e.target); }
    });
  }, { threshold: .18 });
  $$('.shutter').forEach((s) => shutters.observe(s));

  /* ---------- status line: the reader's progress bar, reading this page ---------- */
  const hud = $('#hud');
  const hudTrack = $('#hud-track');
  const SECTIONS = [['top', 'Alexandria'], ['reader', 'Read'], ['companion', 'Ask'], ['listen', 'Listen'], ['track', 'Track'], ['share', 'Share'], ['desktop', 'Desktop'], ['looks', 'Looks'], ['sheet', 'Data sheet'], ['download', 'Download']];
  const navLinks = $$('.links a');
  let ticking = false;
  const updateHud = () => {
    ticking = false;
    const max = document.documentElement.scrollHeight - innerHeight;
    const f = max > 0 ? Math.min(1, scrollY / max) : 0;
    hud.style.setProperty('--pct', `${f * 100}%`);
    hudTrack.style.setProperty('--pct', `${f * 100}%`);
    $('#hud-pct').textContent = `${(f * 100).toFixed(1)}%`;
    const left = Math.round((1 - f) * max / 450);
    $('#hud-left').textContent = left > 0 ? `~${left} min left` : 'End of page';
    let cur = SECTIONS[0];
    SECTIONS.forEach((s) => {
      const n = document.getElementById(s[0]);
      if (n && n.getBoundingClientRect().top < innerHeight * .4) cur = s;
    });
    $('#hud-sec').textContent = cur[1];
    navLinks.forEach((a) => a.classList.toggle('on', a.getAttribute('href') === `#${cur[0]}`));
  };
  addEventListener('scroll', () => {
    if (!ticking) { ticking = true; requestAnimationFrame(updateHud); }
  }, { passive: true, signal });
  addEventListener('resize', updateHud, { signal });
  updateHud();

  let hudDrag = false;
  const hudTo = (e) => {
    const r = hudTrack.getBoundingClientRect();
    const f = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width));
    scrollTo({ top: f * (document.documentElement.scrollHeight - innerHeight), behavior: 'instant' });
  };
  hudTrack.addEventListener('pointerdown', (e) => { hudDrag = true; hudTrack.setPointerCapture(e.pointerId); hudTo(e); });
  hudTrack.addEventListener('pointermove', (e) => { if (hudDrag) hudTo(e); });
  hudTrack.addEventListener('pointerup', () => { hudDrag = false; });
  hudTrack.addEventListener('pointercancel', () => { hudDrag = false; });

  return () => {
    alive = false;
    life.abort();
  };
}
