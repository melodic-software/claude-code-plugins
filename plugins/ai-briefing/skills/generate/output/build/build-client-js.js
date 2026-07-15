// Client-side JS for single-file HTML deck (keyboard nav, scroll-spy, print mode).

export function buildClientJs(groups) {
  return `
(() => {
  const sections = [...document.querySelectorAll('main#deck > section.section')];
  if (sections.length === 0) return;

  // News-parent membership map — sub-section ids whose parentSection was set to news
  const NEWS_SUB_IDS = new Set(${JSON.stringify(groups.filter((g) => g.slides[0]?.parentSection === "news").map((g) => g.key))});

  // All chips, primary + sub
  const chips = new Map(
    [...document.querySelectorAll('#topnav .chips a')].map((a) => [a.dataset.key || a.getAttribute('href').slice(1), a])
  );
  // Just the primary chips (used for keyboard sequential nav)
  const primaryChips = [...document.querySelectorAll('.chips-primary a')];
  let currentIdx = 0;

  function setActive(id) {
    // Direct match
    chips.forEach((a, key) => {
      if (key === id) a.setAttribute('aria-current', 'location');
      else a.removeAttribute('aria-current');
    });
    // Virtual "news" parent chip — active when current section is in news territory
    const newsChip = chips.get('news');
    if (newsChip && NEWS_SUB_IDS.has(id)) {
      newsChip.setAttribute('aria-current', 'location');
      document.body.classList.add('in-news');
    } else {
      document.body.classList.remove('in-news');
    }
    const targetIdx = sections.findIndex((s) => s.id === id);
    if (targetIdx >= 0) currentIdx = targetIdx;
    if (location.hash !== '#' + id) {
      try { history.replaceState(null, '', '#' + id); } catch {}
    }
  }

  // IntersectionObserver scroll-spy — pick the most-intersecting section per callback
  const observed = new Map();
  const obs = new IntersectionObserver((entries) => {
    entries.forEach((e) => observed.set(e.target.id, e));
    const visible = [...observed.values()]
      .filter((e) => e.isIntersecting)
      .sort((a, b) => b.intersectionRatio - a.intersectionRatio);
    if (visible.length > 0) setActive(visible[0].target.id);
  }, { rootMargin: '-30% 0px -55% 0px', threshold: [0, 0.25, 0.5, 0.75, 1] });
  sections.forEach((s) => obs.observe(s));

  // Keyboard nav — section step
  function go(delta) {
    const next = Math.max(0, Math.min(sections.length - 1, currentIdx + delta));
    if (next !== currentIdx) {
      sections[next].scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  }
  document.addEventListener('keydown', (e) => {
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    switch (e.key) {
      case 'ArrowRight':
      case 'PageDown':
      case ' ':
      case 'n':       e.preventDefault(); go(1); break;
      case 'ArrowLeft':
      case 'PageUp':
      case 'p':       e.preventDefault(); go(-1); break;
      case 'Home':    e.preventDefault(); sections[0].scrollIntoView({ behavior: 'smooth' }); break;
      case 'End':     e.preventDefault(); sections[sections.length - 1].scrollIntoView({ behavior: 'smooth' }); break;
      case 'Escape':  e.preventDefault(); sections[0].scrollIntoView({ behavior: 'smooth' }); break;
    }
  });

  // Chip click → smooth-scroll to section + manually scroll chip-strip horizontally.
  // The virtual "news" parent chip routes to the first news sub-section (open).
  // (DO NOT use a.scrollIntoView for the chip — it races the page-scroll and causes
  // the page to land on the wrong section. Manual scrollLeft on the strip avoids
  // the page-scroll side effect entirely.)
  chips.forEach((a, key) => {
    a.addEventListener('click', (e) => {
      e.preventDefault();
      // News parent chip has no DOM section — route to the first news sub-section
      const targetId = key === 'news'
        ? ([...NEWS_SUB_IDS][0] || 'open')
        : key;
      const target = document.getElementById(targetId);
      if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      const strip = a.closest('.chips');
      if (strip) {
        const left = a.offsetLeft - strip.clientWidth / 2 + a.clientWidth / 2;
        strip.scrollTo({ left: Math.max(0, left), behavior: 'smooth' });
      }
    });
  });

  // Hash deep-link on load (instant — no animation surprise)
  function jumpToHash(behavior) {
    const hashId = decodeURIComponent(location.hash.slice(1));
    if (hashId && document.getElementById(hashId)) {
      document.getElementById(hashId).scrollIntoView({ behavior: behavior || 'instant', block: 'start' });
    }
  }
  requestAnimationFrame(() => jumpToHash('instant'));
  // Hashchange (manual URL edit, deep-link from another tab) — smooth-scroll
  window.addEventListener('hashchange', () => jumpToHash('smooth'));

  // Scroll progress bar
  const progress = document.getElementById('progress');
  if (progress) {
    const update = () => {
      const max = document.documentElement.scrollHeight - window.innerHeight;
      const pct = max > 0 ? (window.scrollY / max) * 100 : 0;
      progress.style.width = pct + '%';
    };
    document.addEventListener('scroll', update, { passive: true });
    update();
  }

  // Print mode toggle (?print=1 query) — used by build-pdf.js
  if (new URLSearchParams(location.search).get('print') === '1') {
    document.body.classList.add('print-mode');
  }
  // Speaker notes toggle (?notes=1 query) — reveals .speaker-notes overlay
  if (new URLSearchParams(location.search).get('notes') === '1') {
    document.body.classList.add('show-speaker-notes');
  }
})();
`;
}
