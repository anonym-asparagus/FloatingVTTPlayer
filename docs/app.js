(() => {
  const translations = {
    en: {
      title: "Floating VTT Player — Download for Windows and macOS",
      description: "Download Floating VTT Player for Windows or macOS. Play MP3 and WAV audio with floating WebVTT subtitles.",
      navHow: "How it works", kicker: "A little window for the words",
      heroTitle: "Let the words<br>float.",
      heroDescription: "Play your audio with subtitles that stay in view.",
      downloadWindows: "Download for Windows", downloadMac: "Download for macOS",
      releaseDetail: "Windows x64 .exe · macOS 14+ universal .zip",
      macNote: "The macOS build is not notarized yet. If macOS blocks it, follow ",
      macHelp: "Apple's opening instructions.",
      previewTrack: "Now playing", previewSubtitle: "Music makes a brighter day.",
      heroTail: "A small player for the moments that matter.",
      howTitle: "Your audio, your subtitles.",
      howIntro: "Everything begins with one folder on your computer.",
      stepOneTitle: "Download and open",
      stepOneBody: "Choose the Windows or macOS download. No build tools needed.",
      stepTwoTitle: "Choose a folder",
      stepTwoBody: "Keep MP3 or WAV files beside their matching .vtt subtitle files.",
      stepThreeTitle: "Listen your way",
      stepThreeBody: "Move, resize, and style the floating subtitles while the audio plays.",
      footerText: "Made for listening with words in view.",
      releaseNotes: "Release notes", readme: "Read the guide",
      downloadAria: "Download Floating VTT Player for Windows x64",
      macAria: "Download Floating VTT Player for macOS 14 or later",
      previewAria: "Illustration of the audio player and floating subtitle window",
      navAria: "Main navigation", langAria: "Website language"
    },
    zh: {
      title: "Floating VTT Player — 下载 Windows 和 macOS 版",
      description: "下载 Floating VTT Player Windows 或 macOS 版。播放 MP3、WAV 音频，并显示悬浮 WebVTT 字幕。",
      navHow: "使用方法", kicker: "让文字陪着声音",
      heroTitle: "让字幕<br>轻轻浮现。",
      heroDescription: "播放喜爱的音频，让字幕始终陪在屏幕上。",
      downloadWindows: "下载 Windows 版", downloadMac: "下载 macOS 版",
      releaseDetail: "Windows x64 .exe · macOS 14+ 通用 .zip",
      macNote: "macOS 版本尚未经过 Apple 公证。如被系统拦截，请参阅",
      macHelp: "Apple 的打开说明。",
      previewTrack: "正在播放", previewSubtitle: "让音乐与文字一起流动。",
      heroTail: "一方小小播放器，陪你沉浸聆听。",
      howTitle: "你的音频，你的字幕。",
      howIntro: "把文件放在同一个文件夹，就可以开始。",
      stepOneTitle: "下载并打开",
      stepOneBody: "选择 Windows 或 macOS 版本下载，无需自行编译。",
      stepTwoTitle: "选择文件夹",
      stepTwoBody: "将 MP3 或 WAV 音频与对应的 .vtt 字幕放在一起。",
      stepThreeTitle: "自在聆听",
      stepThreeBody: "边播放边移动、缩放字幕窗，还能调整字体和颜色。",
      footerText: "让声音与文字，一起陪伴你的聆听。",
      releaseNotes: "版本说明", readme: "阅读使用指南",
      downloadAria: "下载 Floating VTT Player Windows x64 版",
      macAria: "下载适用于 macOS 14 或更新版本的 Floating VTT Player",
      previewAria: "音频播放器与悬浮字幕窗口示意图",
      navAria: "主导航", langAria: "网站语言"
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
      const key = element.dataset.i18n;
      if (key === "heroTitle") element.innerHTML = copy[key];
      else element.textContent = copy[key];
    });
    document.querySelector(".download-button").setAttribute("aria-label", copy.downloadAria);
    document.querySelector(".mac-option").setAttribute("aria-label", copy.macAria);
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

  const canvas = document.querySelector("#particle-canvas");
  const context = canvas.getContext("2d", { alpha: true });
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const coarsePointer = matchMedia("(pointer: coarse)");
  const pointer = { x: -1000, y: -1000, lastMove: -Infinity };
  const colors = ["66,115,244", "43,192,238", "120,106,238"];
  let width = 0, height = 0, dpr = 1, frame = 0, particles = [], sparks = [], ripples = [], running = false;

  function resizeCanvas() {
    width = window.innerWidth;
    height = window.innerHeight;
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    context.setTransform(dpr, 0, 0, dpr, 0, 0);
    const count = Math.min(95, Math.max(38, Math.round(width * height / 16500)));
    particles = Array.from({ length: count }, (_, index) => ({
      x: Math.random() * width, y: Math.random() * height,
      phase: Math.random() * Math.PI * 2,
      speed: .25 + Math.random() * .55,
      size: index % 7 === 0 ? 1.9 : .8 + Math.random() * .7,
      color: colors[index % colors.length]
    }));
    if (!running) render(performance.now(), true);
  }
  function dot(x, y, radius, color, opacity) {
    context.beginPath();
    context.arc(x, y, radius, 0, Math.PI * 2);
    context.fillStyle = "rgba(" + color + "," + opacity + ")";
    context.fill();
  }
  function render(now, staticOnly = false) {
    context.clearRect(0, 0, width, height);
    const motionAllowed = !reducedMotion.matches && !coarsePointer.matches;
    const active = motionAllowed && now - pointer.lastMove < 1650;
    const intensity = active ? Math.max(0, 1 - Math.max(0, now - pointer.lastMove - 240) / 1500) : 0;
    if (!staticOnly) frame++;
    for (const particle of particles) {
      let x = particle.x + (motionAllowed ? Math.sin(frame * .007 * particle.speed + particle.phase) * 9 : 0);
      let y = particle.y + (motionAllowed ? Math.cos(frame * .006 * particle.speed + particle.phase) * 7 : 0);
      const dx = x - pointer.x, dy = y - pointer.y, distance = Math.hypot(dx, dy);
      if (active && distance < 245 && distance > 1) {
        const influence = (1 - distance / 245) * intensity;
        x += dx / distance * influence * 18;
        y += dy / distance * influence * 18;
        if (distance > 54 && distance < 218 && particle.size > 1) {
          context.beginPath();
          context.moveTo(x, y);
          context.quadraticCurveTo((x + pointer.x) / 2, (y + pointer.y) / 2 - 13, pointer.x, pointer.y);
          context.strokeStyle = "rgba(" + particle.color + "," + Math.min(.2, influence * .34) + ")";
          context.lineWidth = .75;
          context.stroke();
        }
      }
      dot(x, y, particle.size + (active && distance < 245 ? 1.35 * intensity : 0), particle.color, active && distance < 245 ? .46 + .44 * intensity : .35);
    }
    if (active) {
      const pulse = (Math.sin(now * .008) + 1) / 2;
      for (let index = 0; index < 2; index++) {
        context.beginPath();
        context.arc(pointer.x, pointer.y, 45 + index * 43 + pulse * 12, 0, Math.PI * 2);
        context.strokeStyle = "rgba(" + (index ? colors[2] : colors[1]) + "," + (.1 - index * .03) * intensity + ")";
        context.lineWidth = .9;
        context.stroke();
      }
      dot(pointer.x, pointer.y, 3, colors[1], .6 * intensity);
    }
    sparks = sparks.filter((spark) => spark.life > 0);
    for (const spark of sparks) {
      spark.x += spark.vx; spark.y += spark.vy;
      spark.vx *= .98; spark.vy *= .98; spark.life -= .02;
      dot(spark.x, spark.y, spark.radius * Math.max(.4, spark.life), spark.color, spark.life * .75);
    }
    ripples = ripples.filter((ripple) => ripple.life > 0);
    for (const ripple of ripples) {
      ripple.radius += 2.2; ripple.life -= .023;
      context.beginPath();
      context.arc(ripple.x, ripple.y, ripple.radius, 0, Math.PI * 2);
      context.strokeStyle = "rgba(64,142,241," + ripple.life * .32 + ")";
      context.lineWidth = 1.2;
      context.stroke();
    }
    if (running) requestAnimationFrame(render);
  }
  function startOrStop() {
    const shouldRun = !document.hidden && !reducedMotion.matches && !coarsePointer.matches;
    if (shouldRun && !running) {
      running = true;
      requestAnimationFrame(render);
    } else if (!shouldRun) {
      running = false;
      render(performance.now(), true);
    }
  }
  window.addEventListener("pointermove", (event) => {
    if (reducedMotion.matches || coarsePointer.matches || event.pointerType === "touch") return;
    const distance = Math.hypot(event.clientX - pointer.x, event.clientY - pointer.y);
    pointer.x = event.clientX; pointer.y = event.clientY; pointer.lastMove = performance.now();
    if (distance > 2) {
      const count = Math.min(4, Math.ceil(distance / 20));
      for (let index = 0; index < count; index++) {
        const angle = Math.random() * Math.PI * 2, speed = .4 + Math.random() * 1.9;
        sparks.push({
          x: pointer.x + (Math.random() - .5) * 14, y: pointer.y + (Math.random() - .5) * 14,
          vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed,
          radius: 1 + Math.random() * 1.8, life: .7 + Math.random() * .3,
          color: colors[Math.floor(Math.random() * colors.length)]
        });
      }
      if (sparks.length > 120) sparks.splice(0, sparks.length - 120);
    }
  }, { passive: true });
  window.addEventListener("pointerdown", (event) => {
    if (!reducedMotion.matches && !coarsePointer.matches && event.pointerType !== "touch") {
      ripples.push({ x: event.clientX, y: event.clientY, radius: 10, life: 1 });
    }
  }, { passive: true });
  window.addEventListener("resize", resizeCanvas, { passive: true });
  document.addEventListener("visibilitychange", startOrStop);
  reducedMotion.addEventListener("change", startOrStop);
  coarsePointer.addEventListener("change", startOrStop);
  resizeCanvas();
  startOrStop();
})();
