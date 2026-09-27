(() => {
  const translations = {
    en: {
      title: "Floating VTT Player — Listen with words in view",
      description: "Download Floating VTT Player for macOS or Windows. Play local audio with synced WebVTT subtitles in a floating window.",
      navHow: "How it works",
      heroLineOne: "Listen with",
      heroLineTwo: "words in view.",
      heroDescription: "Local audio. Synced subtitles. A little window that stays with you.",
      downloadMac: "Download for macOS",
      downloadWindows: "Download for Windows",
      releaseDetail: "macOS 14+ universal ZIP · Windows x64 EXE",
      macNote: "The macOS build is not notarized yet. If macOS blocks it, follow ",
      macHelp: "Apple's opening instructions.",
      previewLibrary: "Your Library",
      previewAllFiles: "All Files",
      previewRecent: "Recently Added",
      previewFavorites: "Favorite",
      previewPlaying: "Now playing",
      previewSubtitleLabel: "Subtitles (01.vtt)",
      previewSubtitle: "Music makes a brighter day.",
      howTitle: "A simple pair of files.",
      howIntro: "Keep an audio file and its WebVTT subtitles together with the same name.",
      syncTitle: "Audio and subtitles, together.",
      syncDescription: "Play locally. See the words in sync, in a floating window.",
      footerText: "Made for listening with words in view.",
      releaseNotes: "Release notes",
      readme: "Read the guide",
      macAria: "Download Floating VTT Player for macOS 14 or later",
      downloadAria: "Download Floating VTT Player for Windows x64",
      previewAria: "Illustration of the audio player and floating subtitle window",
      navAria: "Main navigation",
      langAria: "Website language"
    },
    zh: {
      title: "Floating VTT Player — 让声音与字幕同行",
      description: "下载 Floating VTT Player macOS 或 Windows 版。播放本地音频，并在悬浮窗中同步显示 WebVTT 字幕。",
      navHow: "使用方法",
      heroLineOne: "聆听声音，",
      heroLineTwo: "看见文字。",
      heroDescription: "本地音频，同步字幕。一方小窗，始终相伴。",
      downloadMac: "下载 macOS 版",
      downloadWindows: "下载 Windows 版",
      releaseDetail: "macOS 14+ 通用 ZIP · Windows x64 EXE",
      macNote: "macOS 版本尚未经过 Apple 公证。如被系统拦截，请参阅",
      macHelp: "Apple 的打开说明。",
      previewLibrary: "你的资料库",
      previewAllFiles: "所有文件",
      previewRecent: "最近添加",
      previewFavorites: "收藏",
      previewPlaying: "正在播放",
      previewSubtitleLabel: "字幕 (01.vtt)",
      previewSubtitle: "让音乐与文字一起流动。",
      howTitle: "一对同名文件，轻松开始。",
      howIntro: "将音频与对应的 WebVTT 字幕放在同一个文件夹，并保持文件名相同。",
      syncTitle: "声音与字幕，恰好同步。",
      syncDescription: "在本地播放音频，在悬浮窗中跟随字幕。",
      footerText: "让声音与文字，一起陪伴你的聆听。",
      releaseNotes: "版本说明",
      readme: "阅读使用指南",
      macAria: "下载适用于 macOS 14 或更新版本的 Floating VTT Player",
      downloadAria: "下载 Floating VTT Player Windows x64 版",
      previewAria: "音频播放器与悬浮字幕窗口示意图",
      navAria: "主导航",
      langAria: "网站语言"
    }
  };

  const languageButtons = [...document.querySelectorAll("[data-lang]")];
  function setLanguage(language) {
    const lang = translations[language] ? language : "en";
    const copy = translations[lang];
    document.documentElement.lang = lang === "zh" ? "zh-CN" : "en";
    document.title = copy.title;
    document.querySelector('meta[name="description"]').content = copy.description;
    document.querySelectorAll("[data-i18n]").forEach((element) => {
      element.textContent = copy[element.dataset.i18n];
    });
    document.querySelector(".mac-option").setAttribute("aria-label", copy.macAria);
    document.querySelector(".windows-option").setAttribute("aria-label", copy.downloadAria);
    document.querySelector(".product-preview").setAttribute("aria-label", copy.previewAria);
    document.querySelector(".site-nav").setAttribute("aria-label", copy.navAria);
    document.querySelector(".language-switch").setAttribute("aria-label", copy.langAria);
    document.querySelector("#readme-link").href = lang === "zh"
      ? "https://github.com/anonym-asparagus/FloatingVTTPlayer/blob/main/README.zh-CN.md"
      : "https://github.com/anonym-asparagus/FloatingVTTPlayer/blob/main/README.md";
    document.querySelector("#mac-help-link").href = lang === "zh"
      ? "https://support.apple.com/zh-cn/102445"
      : "https://support.apple.com/en-us/102445";
    languageButtons.forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.lang === lang)));
    try { localStorage.setItem("floating-vtt-site-lang", lang); } catch (_) { /* Storage may be unavailable. */ }
  }
  let savedLanguage = "en";
  try { savedLanguage = localStorage.getItem("floating-vtt-site-lang") || "en"; } catch (_) { /* Use English. */ }
  setLanguage(savedLanguage);
  languageButtons.forEach((button) => button.addEventListener("click", () => setLanguage(button.dataset.lang)));

  const waveform = document.querySelector("#wave-bars");
  for (let index = 0; index < 92; index++) {
    const bar = document.createElement("i");
    const wave = Math.abs(Math.sin(index * .31) * Math.cos(index * .087));
    const accent = index > 18 && index < 31 ? 1.35 : 1;
    bar.style.setProperty("--h", `${Math.round(5 + wave * 43 * accent)}px`);
    waveform.appendChild(bar);
  }

  const canvas = document.querySelector("#motion-canvas");
  const context = canvas.getContext("2d", { alpha: true });
  if (!context) return;
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const coarsePointer = matchMedia("(pointer: coarse)");
  const pointer = { x: -1000, y: -1000, drawnX: -1000, drawnY: -1000, lastMove: -Infinity, lastRipple: -Infinity };
  const ripples = [];
  let width = 0, height = 0, dpr = 1, frameId = 0;
  const motionAllowed = () => !reducedMotion.matches && !coarsePointer.matches && !document.hidden;

  function lineY(x, layer) {
    const top = Math.min(height * .17, 175);
    return top + layer * 19 + Math.sin(x / 178 + layer * .27) * 24 + Math.sin(x / 318 + .5) * 12;
  }
  function draw(now) {
    frameId = 0;
    context.clearRect(0, 0, width, height);
    const active = motionAllowed() && now - pointer.lastMove < 1250;
    const influence = active ? Math.max(0, 1 - (now - pointer.lastMove) / 1250) : 0;
    if (active) {
      pointer.drawnX += (pointer.x - pointer.drawnX) * .22;
      pointer.drawnY += (pointer.y - pointer.drawnY) * .22;
    }
    for (let layer = 0; layer < 5; layer++) {
      context.beginPath();
      for (let x = -20; x <= width + 20; x += 12) {
        let y = lineY(x, layer);
        if (active) {
          const distance = (x - pointer.drawnX) / 245;
          y += Math.exp(-distance * distance) * (pointer.drawnY - y) * .08 * influence;
        }
        if (x === -20) context.moveTo(x, y); else context.lineTo(x, y);
      }
      context.strokeStyle = `rgba(66, 110, 208, ${.075 + layer * .009})`;
      context.lineWidth = 1;
      context.stroke();
    }
    for (const x of [width * .31, width * .49, width * .7, width * .89]) {
      const y = lineY(x, 2);
      context.beginPath();
      context.arc(x, y, 2.1, 0, Math.PI * 2);
      context.fillStyle = "rgba(55, 105, 219, .42)";
      context.fill();
    }
    for (let index = ripples.length - 1; index >= 0; index--) {
      const ripple = ripples[index];
      const age = now - ripple.born;
      if (age > 1050 || !motionAllowed()) { ripples.splice(index, 1); continue; }
      const fade = 1 - age / 1050;
      for (let ring = 0; ring < 3; ring++) {
        const radius = 13 + age * .105 + ring * 28;
        context.beginPath();
        context.arc(ripple.x, ripple.y, radius, 0, Math.PI * 2);
        context.strokeStyle = `rgba(49, 92, 219, ${fade * (.18 - ring * .035)})`;
        context.lineWidth = 1;
        context.stroke();
      }
      context.beginPath();
      context.arc(ripple.x, ripple.y, 3 * fade, 0, Math.PI * 2);
      context.fillStyle = `rgba(49, 92, 219, ${fade * .45})`;
      context.fill();
    }
    if (active || ripples.length) frameId = requestAnimationFrame(draw);
  }
  function scheduleDraw() { if (!frameId) frameId = requestAnimationFrame(draw); }
  function resizeCanvas() {
    width = window.innerWidth;
    height = window.innerHeight;
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    context.setTransform(dpr, 0, 0, dpr, 0, 0);
    scheduleDraw();
  }
  window.addEventListener("pointermove", (event) => {
    if (!motionAllowed() || event.pointerType === "touch") return;
    const now = performance.now();
    pointer.x = event.clientX;
    pointer.y = event.clientY;
    if (pointer.drawnX < 0) { pointer.drawnX = pointer.x; pointer.drawnY = pointer.y; }
    pointer.lastMove = now;
    if (now - pointer.lastRipple > 190) {
      ripples.push({ x: pointer.x, y: pointer.y, born: now });
      if (ripples.length > 4) ripples.shift();
      pointer.lastRipple = now;
    }
    scheduleDraw();
  }, { passive: true });
  window.addEventListener("resize", resizeCanvas, { passive: true });
  document.addEventListener("visibilitychange", scheduleDraw);
  reducedMotion.addEventListener("change", scheduleDraw);
  coarsePointer.addEventListener("change", scheduleDraw);
  resizeCanvas();
})();
