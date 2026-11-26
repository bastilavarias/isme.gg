(() => {
  'use strict';

  const video = document.getElementById('hero-video');
  const toggle = document.getElementById('hero-motion');
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  let loaded = false;

  function syncToggle() {
    toggle.textContent = video.paused ? 'Play demo' : 'Pause demo';
  }

  async function play() {
    if (!loaded) {
      for (const source of video.querySelectorAll('source[data-src]')) {
        source.src = source.dataset.src;
      }
      video.load();
      loaded = true;
    }
    try {
      await video.play();
    } catch {
      syncToggle();
    }
  }

  function applyMotionPreference() {
    video.autoplay = !motion.matches;
    if (motion.matches) {
      video.pause();
    } else {
      void play();
    }
  }

  video.addEventListener('play', syncToggle);
  video.addEventListener('pause', syncToggle);
  toggle.addEventListener('click', () => {
    if (video.paused) void play();
    else video.pause();
  });
  motion.addEventListener('change', applyMotionPreference);
  toggle.hidden = false;
  applyMotionPreference();
})();
