<script>
	import { onMount } from 'svelte';
	import { initSite } from '#lib/site.js';
	import './site.css';

	onMount(initSite);
</script>

<svelte:head>
	<title>Alexandria: read and listen on Android</title>
	<meta name="description" content="A reader and listener built like a tool. PDF, EPUB and DOCX, audiobooks, podcasts and world radio in one Android app. Free, with no account.">
	<meta name="theme-color" content="#E8E6E1">
	<meta property="og:title" content="Alexandria">
	<meta property="og:description" content="One machine for everything you read and hear.">
	<meta property="og:image" content="/assets/shots/library.webp">
	<link rel="preconnect" href="https://fonts.googleapis.com">
	<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous">
	<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Big+Shoulders+Display:wght@700;800;900&family=JetBrains+Mono:wght@400;500;700&family=Space+Grotesk:wght@400;500;700&display=swap">
</svelte:head>

<a class="skip" href="#reader">Skip to the tour</a>

<header class="bar">
  <a class="brand" href="#top" aria-label="Alexandria, back to top"><i class="ring-mark" aria-hidden="true"></i><span>Alexandria</span></a>
  <nav class="links" aria-label="Sections">
    <a href="#reader">Read</a>
    <a href="#companion">Ask</a>
    <a href="#listen">Listen</a>
    <a href="#track">Track</a>
    <a href="#share">Share</a>
    <a href="#looks">Looks</a>
    <a href="#sheet">Data sheet</a>
  </nav>
  <div class="bar-tools">
    <button class="click-toggle" type="button" aria-pressed="false" title="Turn control clicks on or off"><i class="led" aria-hidden="true"></i><span>Clicks</span></button>
    <a class="btn btn-signal btn-small" data-download href="https://github.com/dagmawibabi/Alexandria/releases">Download</a>
  </div>
</header>

<main id="top">

<section class="hero plate" aria-labelledby="wordmark">
  <h1 id="wordmark" class="word" aria-label="Alexandria"><span class="word-inner" aria-hidden="true"><span class="ch" style="--i:0"><b>A</b></span><span class="ch" style="--i:1"><b>L</b></span><span class="ch" style="--i:2"><b>E</b></span><span class="ch" style="--i:3"><b>X</b></span><span class="ch" style="--i:4"><b>A</b></span><span class="ch" style="--i:5"><b>N</b></span><span class="ch" style="--i:6"><b>D</b></span><span class="ch" style="--i:7"><b>R</b></span><span class="ch" style="--i:8"><b>I</b></span><span class="ch" style="--i:9"><b>A</b></span></span></h1>

  <div class="hero-grid">
    <div class="hero-copy">
      <p class="lede">One machine for everything you read and hear.</p>
      <p class="sub">Read PDF, EPUB and DOCX. Listen to audiobooks, podcasts and radio from around the world. Free, with no account.</p>
      <div class="cta">
        <a class="btn btn-signal" data-download href="https://github.com/dagmawibabi/Alexandria/releases">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M11 3h2v10.2l3.6-3.6L18 11l-6 6-6-6 1.4-1.4 3.6 3.6zM4 19h16v2H4z"/></svg>
          Download for Android
        </a>
        <a class="btn" href="https://github.com/dagmawibabi/Alexandria">Source on GitHub</a>
      </div>
    </div>

    <div class="dial-wrap">
      <div class="dial" id="dial" role="slider" tabindex="0" aria-label="Choose an app screen" aria-valuemin="1" aria-valuemax="5" aria-valuenow="1" aria-valuetext="Library">
        <svg class="dial-scale" viewBox="0 0 400 400" aria-hidden="true"></svg>
        <div class="knob"><div class="knob-rot"><i class="knob-notch"></i></div><div class="knob-sheen"></div></div>
      </div>
      <p class="readout" aria-live="polite"><i class="led on" aria-hidden="true"></i><span id="dial-name">Library</span><small id="dial-note">Your books, audiobooks and shows on one shelf.</small></p>
      <p class="hint">Turn the ring, or use the arrow keys.</p>
    </div>

    <div class="hero-phone">
      <figure class="phone" id="hero-phone">
        <div class="screen">
          <img class="layer" id="hero-a" src="/assets/shots/library.webp" width="660" height="1429" alt="The Library screen of Alexandria: a continue-reading card above a grid of book covers." fetchpriority="high">
          <img class="layer top" id="hero-b" alt="" hidden>
          <i class="wiper" aria-hidden="true"></i>
        </div>
      </figure>
    </div>
  </div>
</section>

<section id="reader" class="plate" aria-labelledby="reader-h">
  <div class="wrap">
    <div class="head">
      <h2 id="reader-h">Set the page the way you read</h2>
      <p>Every control on this bench is in the app. Move one and the page answers.</p>
    </div>

    <div class="bench" id="bench">
      <article class="page" id="page" style="--pg:#F2EFE8;--pg-ink:#1C1B19">
        <div class="page-status"><span id="page-face">Literata, 19 pt</span><span id="page-surface">Paper</span></div>
        <div class="page-text" id="page-text">
          <h3>Loomings</h3>
          <p>Call me Ishmael. Some years ago, never mind how long precisely, having little or no money in my purse, and nothing particular to interest me on shore, I thought I would sail about a little and see the watery part of the world.</p>
          <p>It is a way I have of driving off the spleen and regulating the circulation. Whenever I find myself growing grim about the mouth; <mark data-c="0">whenever it is a damp, drizzly November in my soul</mark>; then, I account it high time to get to sea as soon as I can.</p>
          <p>This is my substitute for pistol and ball. With a philosophical flourish Cato throws himself upon his sword; I quietly take to the ship.</p>
        </div>
        <i class="warm" aria-hidden="true"></i>
      </article>

      <div class="panel" aria-label="Reader controls">
        <fieldset>
          <legend>Page surface</legend>
          <div class="surfaces" id="surfaces"></div>
        </fieldset>
        <fieldset>
          <legend>Typeface</legend>
          <div class="chips" id="faces"></div>
        </fieldset>
        <div class="faders">
          <label class="fader"><span>Size</span><input id="f-size" type="range" min="11" max="40" value="19"><output>19</output></label>
          <label class="fader"><span>Leading</span><input id="f-lead" type="range" min="12" max="22" value="16"><output>1.6</output></label>
          <label class="fader"><span>Margins</span><input id="f-marg" type="range" min="8" max="64" value="24"><output>24</output></label>
          <label class="fader"><span>Warmth</span><input id="f-warm" type="range" min="0" max="60" value="0"><output>0</output></label>
        </div>
        <div class="row-switches">
          <label class="switch"><input id="s-just" type="checkbox"><i></i><span>Justified</span></label>
          <label class="switch"><input id="s-indent" type="checkbox"><i></i><span>Indent paragraphs</span></label>
        </div>
        <fieldset>
          <legend>Marker colour</legend>
          <div class="markers" id="markers"></div>
          <p class="note">Select words on the page to mark them. Tap a mark to clear it.</p>
        </fieldset>
      </div>
    </div>

    <h3 class="sub-h">Three ways through a book</h3>
    <div class="modes">
      <div class="mode">
        <!-- svelte-ignore a11y_no_noninteractive_tabindex (it scrolls, so the keyboard must reach it) -->
        <div class="slate slate-dark" id="swipe" tabindex="0" aria-label="Swipe mode demo. Scroll to move between cards."></div>
        <h4>Swipe</h4>
        <p>The book as a stack of cards, each filled to fit your screen. Go up or sideways, or let them advance at your own words per minute.</p>
      </div>
      <div class="mode">
        <div class="slate" id="auto" aria-label="Auto-scroll demo"><div class="auto-text" id="auto-text"></div></div>
        <h4>Auto-scroll</h4>
        <label class="fader fader-wide"><span>Speed</span><input id="auto-speed" type="range" min="5" max="400" value="40"><output>40 px/s</output></label>
        <p>Hands free, from a crawl to a sprint. Put a finger on the page and it holds.</p>
      </div>
      <div class="mode">
        <figure class="phone phone-flat zones" id="zones">
          <div class="screen"><img src="/assets/shots/reader.webp" loading="lazy" width="660" height="1429" alt="The reader on a paper surface, with two highlighted passages and the control bar open.">
            <button type="button" class="zone" data-z="Previous page">Previous page</button>
            <button type="button" class="zone" data-z="Show controls">Show controls</button>
            <button type="button" class="zone" data-z="Next page">Next page</button>
          </div>
        </figure>
        <h4>Tap and slide</h4>
        <p>Tap zones turn the page. Slide the screen edge for brightness or text size, on whichever side you choose.</p>
      </div>
    </div>

    <h3 class="sub-h">Eleven surfaces, and every setting</h3>
    <div class="triptych">
      <figure class="phone phone-flat shutter"><div class="screen"><img src="/assets/shots/reader-crt.webp" loading="lazy" width="660" height="1429" alt="The reader on the Amber CRT surface in JetBrains Mono."></div><figcaption>Amber CRT</figcaption></figure>
      <figure class="phone phone-flat shutter"><div class="screen"><img src="/assets/shots/reader-phosphor.webp" loading="lazy" width="660" height="1429" alt="The reader on the Phosphor surface in IBM Plex Mono."></div><figcaption>Phosphor</figcaption></figure>
      <figure class="phone phone-flat shutter"><div class="screen"><img src="/assets/shots/surfaces.webp" loading="lazy" width="660" height="1429" alt="The Light and surface settings: brightness, super dim, warmth and the day and night surfaces."></div><figcaption>Light and surface</figcaption></figure>
      <figure class="phone phone-flat shutter"><div class="screen"><img src="/assets/shots/type.webp" loading="lazy" width="660" height="1429" alt="The Type settings: typeface, leading, paragraph gap, tracking, weight and margins."></div><figcaption>Type</figcaption></figure>
    </div>
  </div>
</section>

<section id="companion" class="plate dark" aria-labelledby="ask-h">
  <div class="wrap split">
    <div>
      <div class="head head-stack">
        <h2 id="ask-h">Ask the book, in the margin</h2>
        <p>Connect your own key from Google or Vercel AI Gateway. The companion knows how far you have read, and keeps quiet about the rest.</p>
      </div>
      <h3 class="sub-h sub-h-tight">Select any passage</h3>
      <div class="selmenu" id="selmenu" role="group" aria-label="What the selection menu does"></div>
      <p class="selmenu-out" id="selmenu-out" aria-live="polite"></p>
      <ul class="plain">
        <li>Chat about the whole book, or just one passage.</li>
        <li>Recap what you have read so far, picking up after a long gap.</li>
        <li>Pitch answers simple, clear or expert, in the language you choose.</li>
        <li>See what each model and voice has cost you in the usage log.</li>
      </ul>
    </div>
    <div class="pair">
      <figure class="phone shutter"><div class="screen"><img src="/assets/shots/chat.webp" loading="lazy" width="660" height="1429" alt="A chat with the AI companion about Moby-Dick, answering without spoilers."></div></figure>
      <figure class="phone shutter pair-low"><div class="screen"><img src="/assets/shots/detail.webp" loading="lazy" width="660" height="1429" alt="The book detail screen with rating, format, reading speed and time left."></div></figure>
    </div>
  </div>
</section>

<section id="listen" class="plate dark" aria-labelledby="listen-h">
  <div class="wrap">
    <div class="head">
      <h2 id="listen-h">Tune to anything spoken</h2>
      <p>Four bands on one dial. They all share the same player, keep going in the background, and stay on your lock screen.</p>
    </div>
    <div class="tuner" id="tuner" role="slider" tabindex="0" aria-label="Choose a listening band" aria-valuemin="1" aria-valuemax="4" aria-valuenow="1" aria-valuetext="Audiobooks">
      <div class="tuner-scale" aria-hidden="true"></div>
      <div class="tuner-stops"></div>
      <i class="needle" aria-hidden="true"></i>
    </div>
    <div class="band">
      <div class="band-copy">
        <div class="eq" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i><i></i><i></i></div>
        <h3 id="band-title">Audiobooks</h3>
        <ul class="plain" id="band-list"></ul>
      </div>
      <figure class="phone"><div class="screen"><img id="band-a" loading="lazy" width="660" height="1429" alt=""></div></figure>
      <figure class="phone band-second"><div class="screen"><img id="band-b" loading="lazy" width="660" height="1429" alt=""></div></figure>
    </div>
  </div>
</section>

<section id="track" class="plate" aria-labelledby="track-h">
  <div class="wrap">
    <div class="head">
      <h2 id="track-h">Keep track of all of it</h2>
      <p>Finding, filing and counting, across everything on your shelf.</p>
    </div>
    <div class="track">
      <div class="track-gauge">
        <div class="gauge" id="gauge" style="--v:1"><div class="gauge-in"><b id="gauge-n">56</b><span id="gauge-of">of 30 min</span></div></div>
        <label class="fader fader-wide"><span>Daily goal</span><input id="gauge-goal" type="range" min="10" max="120" step="5" value="30"><output>30 min</output></label>
        <p>Set goals for minutes a day, books and audiobooks a year, and episodes a week. Time is counted per kind, along with your streak.</p>
      </div>
      <figure class="phone shutter t-stats"><div class="screen"><img src="/assets/shots/stats.webp" loading="lazy" width="660" height="1429" alt="The stats screen: today's goal ring, a 23-day streak, totals by kind and two weeks of bars."></div><figcaption>Stats</figcaption></figure>
      <figure class="phone shutter t-widgets"><div class="screen"><img src="/assets/shots/widgets.webp" loading="lazy" width="660" height="1429" alt="The home-screen widget customiser with font and colour options."></div><figcaption>Home-screen widgets</figcaption></figure>
      <figure class="phone shutter t-folders"><div class="screen"><img src="/assets/shots/folders.webp" loading="lazy" width="660" height="1429" alt="Book folders, with smart rows for favourites and unfiled books above your own folders."></div><figcaption>Folders</figcaption></figure>
      <figure class="phone shutter t-find"><div class="screen"><img src="/assets/shots/books.webp" loading="lazy" width="660" height="1429" alt="The Books screen listing free EPUBs from Project Gutenberg, each with a Get EPUB button."></div><figcaption>Free books</figcaption></figure>
      <div class="track-notes">
        <p><b>Find.</b> Free EPUBs from Project Gutenberg in one tap, or the whole Open Library catalogue for your want-to-read list.</p>
        <p><b>File.</b> One folder can hold books, audiobooks and shows together. Favourites and unfiled items sort themselves.</p>
        <p><b>Search.</b> Every search bar keeps its own recent searches, and you can clear them one at a time.</p>
      </div>
    </div>
  </div>
</section>

<section id="share" class="plate dark" aria-labelledby="share-h">
  <div class="wrap split split-card">
    <div>
      <div class="head head-stack">
        <h2 id="share-h">Send a passage out</h2>
        <p>Turn a highlight into a card worth posting. Eight styles and three sizes, ready for the feed or a story.</p>
      </div>
      <fieldset class="dark-set">
        <legend>Style</legend>
        <div class="chips" id="card-styles"></div>
      </fieldset>
      <fieldset class="dark-set">
        <legend>Size</legend>
        <div class="chips" id="card-sizes"></div>
      </fieldset>
      <button type="button" class="btn btn-ghost" id="card-next">Another passage</button>
      <div class="studio">
        <figure class="phone shutter"><div class="screen"><img src="/assets/shots/quote.webp" loading="lazy" width="660" height="1429" alt="The card studio in the app: a preview above style, background colour, format and typeface controls."></div></figure>
        <p>The real studio in the app also lets you pick any background colour and typeface.</p>
      </div>
    </div>
    <div class="card-stage">
      <div class="quote" id="quote">
        <div class="quote-top"><i class="ring-mark" aria-hidden="true"></i><span>Alexandria / excerpt</span></div>
        <blockquote id="quote-text"></blockquote>
        <div class="quote-foot"><b id="quote-book"></b><span id="quote-author"></span></div>
      </div>
    </div>
  </div>
</section>

<section id="looks" class="plate" aria-labelledby="looks-h">
  <div class="wrap split split-looks">
    <div>
      <div class="head head-stack">
        <h2 id="looks-h">Two machines in one</h2>
        <p>Industrial is hairlines, monospace and hard corners. Zen drops all of that for something soft and quiet. Every screen follows, and so does this site's accent below.</p>
      </div>
      <fieldset>
        <legend>Accent</legend>
        <div class="accents" id="accents"></div>
        <p class="note" id="accent-name" aria-live="polite">Signal orange</p>
      </fieldset>
      <div class="row-switches">
        <label class="switch"><input id="s-mono" type="checkbox"><i></i><span>Monochrome</span></label>
        <label class="switch"><input id="s-dark" type="checkbox"><i></i><span>Dark</span></label>
      </div>
      <p class="note">Also yours to change: corner radius, five interface fonts, the dot grid, haptics, and any custom colour from a full picker.</p>
    </div>
    <div class="compare" id="compare" role="slider" tabindex="0" aria-label="Compare the Industrial and Zen looks" aria-valuemin="0" aria-valuemax="100" aria-valuenow="50">
      <figure class="phone phone-flat"><div class="screen">
        <img id="cmp-a" src="/assets/shots/library-light.webp" loading="lazy" width="660" height="1429" alt="The Library in the Industrial look.">
        <div class="cmp-top"><img src="/assets/shots/zen.webp" loading="lazy" width="660" height="1429" alt="The Library in the Zen look."></div>
        <i class="cmp-handle" aria-hidden="true"><b></b></i>
      </div></figure>
      <div class="cmp-labels" aria-hidden="true"><span>Zen</span><span>Industrial</span></div>
    </div>
  </div>
</section>

<section id="sheet" class="plate" aria-labelledby="sheet-h">
  <div class="wrap">
    <div class="head">
      <h2 id="sheet-h">Data sheet</h2>
      <p>Everything the app does, in one table.</p>
    </div>
    <label class="filter">
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M10 3a7 7 0 1 0 4.2 12.6l5.1 5.1 1.4-1.4-5.1-5.1A7 7 0 0 0 10 3zm0 2a5 5 0 1 1 0 10 5 5 0 0 1 0-10z"/></svg>
      <span class="sr">Filter the data sheet</span>
      <input id="sheet-q" type="search" placeholder="Filter: try voice, pdf or widget" autocomplete="off">
      <output id="sheet-n"></output>
    </label>
    <div class="sheet" id="sheet-body"></div>
  </div>
</section>

<section id="download" class="plate dark end" aria-labelledby="end-h">
  <div class="wrap end-grid">
    <a class="big-ring" data-download href="https://github.com/dagmawibabi/Alexandria/releases" aria-label="Download Alexandria from the GitHub releases page">
      <span class="big-ring-in"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M11 3h2v10.2l3.6-3.6L18 11l-6 6-6-6 1.4-1.4 3.6 3.6zM4 19h16v2H4z"/></svg></span>
    </a>
    <div>
      <h2 id="end-h">Put it on your phone</h2>
      <p>Alexandria is an Android app. Get the latest APK from the GitHub releases page and open it on your phone. Android may ask you to allow installs from your browser the first time.</p>
      <div class="cta">
        <a class="btn btn-signal" data-download href="https://github.com/dagmawibabi/Alexandria/releases">Go to the releases page</a>
        <a class="btn btn-ghost" href="https://github.com/dagmawibabi/Alexandria">Read the source</a>
      </div>
    </div>
  </div>
  <footer class="foot wrap">
    <p>No account and no sign-in. Your library lives on your phone, and a full backup is one JSON file.</p>
    <p>The screenshots are real app screens with demo data. Moby-Dick and the other books shown are in the public domain.</p>
  </footer>
</section>

</main>

<div class="hud" id="hud" aria-hidden="true">
  <span class="hud-pct" id="hud-pct">0.0%</span>
  <span class="hud-sec" id="hud-sec">Alexandria</span>
  <div class="hud-track" id="hud-track"><i id="hud-fill"></i><b id="hud-thumb"></b></div>
  <span class="hud-left" id="hud-left"></span>
</div>
