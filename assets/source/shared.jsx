// shared.jsx — brand-aligned theme + helpers
// Palette pulled directly from page 03 of the brand book.
const T = {
  // body / surfaces
  bg:        '#FFF6E5',  // 奶油白
  bgWarm:    '#FCEAB7',  // soft yellow tint for hero accents
  card:      '#FFFFFF',
  cardSoft:  '#FFF1D2',  // pale yellow card
  // brand
  yellow:    '#FFC83D',  // 窝囊黄
  gold:      '#FFD24D',  // 金币金
  ink:       '#0D0D0D',  // 墨黑
  inkSoft:   '#3A3530',
  muted:     '#9A938A',
  hair:      'rgba(13,13,13,0.08)',
  cyan:      '#00E5FF',  // 电光青
  cyanSoft:  '#B6F5FB',
  coral:     '#FF5C57',  // 热辣珊瑚
  coralSoft: '#FFD7D2',
  cowGray:   '#3A3530',  // cow patches
  pink:      '#FFB1A6',  // 粉鼻子
  pinkSoft:  '#FFE3DD',
};

const FONT_DISPLAY = '"ZCOOL QingKe HuangYou", "Nunito", "PingFang SC", -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif';
const FONT_BODY = '"Nunito", "PingFang SC", -apple-system, BlinkMacSystemFont, system-ui, sans-serif';
const FONT_MONO = '"JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace';

// ───────── math ─────────
function parseHM(s) {
  const [h, m] = s.split(':').map(Number);
  return h * 60 + m;
}
function parseHMSeconds(s) {
  return parseHM(s) * 60;
}
function secondsInDay(date) {
  return date.getHours() * 3600 + date.getMinutes() * 60 + date.getSeconds();
}
function formatClock(date) {
  return `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
}
function normalizeNowSeconds(nowValue) {
  return nowValue > 24 * 60 ? nowValue : nowValue * 60;
}
function fmtHMcn(mins) {
  const h = Math.floor(mins / 60);
  const m = Math.round(mins % 60);
  if (h <= 0) return `${m}min`;
  if (m === 0) return `${h}h`;
  return `${h}h${m}min`;
}

function computeDay(cfg, nowMin) {
  const startMin = parseHM(cfg.workStart);
  const endMin = parseHM(cfg.workEnd);
  const lunchStart = cfg.noLunch ? endMin : parseHM(cfg.lunchStart);
  const lunchEnd   = cfg.noLunch ? endMin : parseHM(cfg.lunchEnd);
  const lunchLen = Math.max(0, lunchEnd - lunchStart);
  const workdayLen = Math.max(0, endMin - startMin - lunchLen);
  const hourlyRate = cfg.monthlySalary / (cfg.workdaysPerMonth * (workdayLen / 60));
  const startSecond = startMin * 60;
  const endSecond = endMin * 60;
  const lunchStartSecond = lunchStart * 60;
  const lunchEndSecond = lunchEnd * 60;
  const nowSecond = normalizeNowSeconds(nowMin);

  let elapsedPaidSeconds = 0;
  if (nowSecond > startSecond) {
    elapsedPaidSeconds = Math.min(nowSecond, endSecond) - startSecond;
    const lunchOver = Math.max(0, Math.min(nowSecond, lunchEndSecond) - lunchStartSecond);
    elapsedPaidSeconds -= Math.max(0, lunchOver);
    elapsedPaidSeconds = Math.max(0, elapsedPaidSeconds);
  }
  const elapsedPaid = Math.floor(elapsedPaidSeconds / 60);
  const earnedToday = (hourlyRate / 3600) * elapsedPaidSeconds;
  const targetToday = (hourlyRate / 60) * workdayLen;
  const nowMinute = nowSecond / 60;

  let status = 'before';
  if (nowMinute < startMin) status = 'before';
  else if (nowMinute >= startMin && nowMinute < lunchStart) status = 'morning';
  else if (nowMinute >= lunchStart && nowMinute < lunchEnd) status = 'lunch';
  else if (nowMinute >= lunchEnd && nowMinute < endMin) status = 'afternoon';
  else status = 'done';

  const wallToEnd = Math.max(0, Math.ceil((endSecond - nowSecond) / 60));
  return {
    startMin, endMin, lunchStart, lunchEnd, workdayLen,
    hourlyRate, elapsedPaid, elapsedPaidSeconds, earnedToday, targetToday,
    status, wallToEnd, nowMin: nowMinute,
    progressPct: workdayLen ? elapsedPaidSeconds / (workdayLen * 60) : 0,
  };
}

function poseFromStatus(s, p) {
  if (s === 'before') return 'front-sad';
  if (s === 'morning') return 'three-q';
  if (s === 'lunch') return 'front-sad-2';
  if (s === 'afternoon') return p > 0.85 ? 'three-q-2' : 'front-sad';
  return 'three-q-2';
}

function statusCopy(s) {
  return ({
    before:    '尚未开工 · 再睡会儿',
    morning:   '上午搬砖中',
    lunch:     '午休回血',
    afternoon: '下午挺挺',
    done:      '今日通关 · 收工',
  })[s] || '';
}

function quote(s) {
  return ({
    before:    '别急，钱还没开始挣。',
    morning:   '早上的两小时最值钱。',
    lunch:     '吃饭的时候不发工资。',
    afternoon: '再忍忍，钱在涨。',
    done:      '今天又把房租挣回来了。',
  })[s] || '算了算了。';
}

function fmtMoneyInt(n, privacy) {
  if (privacy) return '¥••••';
  return '¥' + Math.round(n).toLocaleString('en-US');
}

// ───────── primitives ─────────

// Brand wordmark — used in screen headers
function Wordmark({ size = 18, color }) {
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 6,
      fontFamily: FONT_DISPLAY,
      fontWeight: 400,            // ZCOOL QingKe HuangYou ships at 400 only
      fontSize: size, lineHeight: 1,
      color: color || T.ink, letterSpacing: 0.5,
    }}>
      <Cow pose="three-q" size={size * 1.4} style={{ marginTop: -2 }} />
      <span>窝囊费</span>
      <YenBadge size={size * 0.7} />
    </div>
  );
}

// Gold ¥ tag — the cow's pendant
function YenBadge({ size = 14 }) {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      width: size, height: size, borderRadius: size * 0.22,
      background: `linear-gradient(135deg, #FFE680 0%, ${T.gold} 100%)`,
      color: '#fff', fontFamily: FONT_DISPLAY, fontSize: size * 0.78,
      fontWeight: 400, lineHeight: 1, letterSpacing: 0,
      boxShadow: '0 1px 1.5px rgba(170,110,20,0.3)',
    }}>¥</span>
  );
}

// Speech bubble — comes from the brand "今天又..." sticker style
function SpeechBubble({ children, tail = 'bl', bg = '#fff', color = T.ink, style = {} }) {
  return (
    <div style={{
      position: 'relative', display: 'inline-block',
      background: bg, color,
      fontFamily: FONT_DISPLAY, fontSize: 14,
      lineHeight: 1.35, letterSpacing: 0.3,
      padding: '10px 14px', borderRadius: 16,
      boxShadow: '0 4px 14px rgba(20,20,20,0.08), 0 0 0 0.5px rgba(0,0,0,0.04)',
      ...style,
    }}>
      {children}
      <span style={{
        position: 'absolute',
        ...(tail === 'bl' ? { left: 16, bottom: -6 } : { right: 16, bottom: -6 }),
        width: 14, height: 14, background: bg, borderRadius: 3,
        transform: 'rotate(45deg)', zIndex: -1,
        boxShadow: '0 4px 8px rgba(20,20,20,0.06)',
      }} />
    </div>
  );
}

// Black pill button (1° CTA)
function PillButton({ children, secondary, full, style = {}, ...rest }) {
  return (
    <button {...rest} style={{
      appearance: 'none', border: 'none', cursor: 'pointer',
      background: secondary ? '#fff' : T.ink,
      color: secondary ? T.ink : '#fff',
      fontFamily: FONT_BODY,
      fontWeight: 800, fontSize: 14,
      padding: '13px 22px', borderRadius: 999,
      width: full ? '100%' : undefined,
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
      boxShadow: secondary
        ? '0 0 0 0.5px rgba(0,0,0,0.12), 0 4px 10px rgba(0,0,0,0.04)'
        : '0 6px 18px rgba(13,13,13,0.22)',
      ...style,
    }}>{children}</button>
  );
}

// Yellow pill button (2° CTA, also brand)
function YellowPill({ children, style = {}, ...rest }) {
  return (
    <button {...rest} style={{
      appearance: 'none', border: 'none', cursor: 'pointer',
      background: T.yellow,
      color: T.ink,
      fontFamily: FONT_BODY, fontWeight: 800, fontSize: 14,
      padding: '12px 18px', borderRadius: 999,
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6,
      boxShadow: '0 6px 14px rgba(255,200,61,0.4)',
      ...style,
    }}>{children}</button>
  );
}

// Liquid-Glass tab bar (iOS 26 style) — floating translucent pill.
// Sits above content, never opaque, with a thick blur + faint inner highlight.
function TabBar({ active, variant = 'light', onNavigate }) {
  const items = [
    { key: 'home',     label: '首页', icon: 'home' },
    { key: 'stats',    label: '记录', icon: 'stats' },
    { key: 'settings', label: '我的', icon: 'me' },
  ];
  // On warm cream the glass leans white; on yellow surfaces it leans cream.
  const isDark = variant === 'dark';
  const surface = isDark
    ? 'rgba(13,13,13,0.55)'      // dark glass over images
    : 'rgba(255,255,255,0.55)';   // light glass over cream
  const stroke = isDark
    ? 'rgba(255,255,255,0.18)'
    : 'rgba(255,255,255,0.85)';
  const innerHi = isDark
    ? 'inset 0 1px 0 rgba(255,255,255,0.10)'
    : 'inset 0 1px 0 rgba(255,255,255,0.9), inset 0 -1px 0 rgba(0,0,0,0.04)';
  const textOff = isDark ? 'rgba(255,255,255,0.7)' : T.inkSoft;
  return (
    <div style={{
      position: 'absolute', left: 0, right: 0, bottom: 18,
      display: 'flex', justifyContent: 'center',
      zIndex: 80, pointerEvents: 'none',
    }}>
      <div style={{
        pointerEvents: 'auto',
        display: 'flex', alignItems: 'center', gap: 4,
        padding: 6,
        borderRadius: 999,
        background: surface,
        backdropFilter: 'blur(28px) saturate(180%)',
        WebkitBackdropFilter: 'blur(28px) saturate(180%)',
        border: `0.5px solid ${stroke}`,
        boxShadow: `0 12px 32px rgba(13,13,13,0.18), 0 2px 6px rgba(13,13,13,0.06), ${innerHi}`,
      }}>
        {items.map(it => {
          const on = active === it.key;
          return (
            <button key={it.key} type="button" onClick={() => onNavigate?.(it.key)} style={{
              appearance: 'none', border: 'none', cursor: 'pointer',
              display: 'flex', alignItems: 'center', gap: 6,
              padding: on ? '10px 16px' : '10px 12px',
              borderRadius: 999,
              background: on ? T.ink : 'transparent',
              color: on ? T.yellow : textOff,
              fontFamily: FONT_BODY, fontWeight: 800, fontSize: 13,
              transition: 'all .25s cubic-bezier(.32,.72,0,1)',
              boxShadow: on ? '0 6px 14px rgba(13,13,13,0.22)' : 'none',
            }}>
              <TabIcon name={it.icon} active={on} />
              {on && <span style={{ color: '#fff', letterSpacing: 0.3 }}>{it.label}</span>}
            </button>
          );
        })}
      </div>
    </div>
  );
}

// Simple stroked glyph set — matches the rounded brand book icon style.
function TabIcon({ name, active }) {
  const stroke = active ? '#FFC83D' : 'currentColor';
  const fill = 'none';
  const sw = 1.9;
  const c = { fill, stroke, strokeWidth: sw, strokeLinecap: 'round', strokeLinejoin: 'round' };
  if (name === 'home') {
    return (
      <svg width="20" height="20" viewBox="0 0 24 24">
        <path d="M3.5 11.2 12 4l8.5 7.2" {...c} />
        <path d="M5.5 10v9h13v-9" {...c} />
        <path d="M10 19v-4.2a2 2 0 0 1 4 0V19" {...c} />
      </svg>
    );
  }
  if (name === 'stats') {
    return (
      <svg width="20" height="20" viewBox="0 0 24 24">
        <path d="M4 19h16" {...c} />
        <rect x="6" y="11" width="3.2" height="8" rx="1.2" {...c} />
        <rect x="10.4" y="7" width="3.2" height="12" rx="1.2" {...c} />
        <rect x="14.8" y="13" width="3.2" height="6" rx="1.2" {...c} />
      </svg>
    );
  }
  // me
  return (
    <svg width="20" height="20" viewBox="0 0 24 24">
      <circle cx="12" cy="9" r="3.6" {...c} />
      <path d="M5 19.5c.7-3.4 3.6-5.4 7-5.4s6.3 2 7 5.4" {...c} />
    </svg>
  );
}

// Top bar — wordmark + 1 right-side action
function TopBar({ right }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '14px 20px 8px',
    }}>
      <Wordmark size={20} />
      {right}
    </div>
  );
}

// Eye icon for privacy toggle in top bar
function PrivacyToggle({ on, onClick }) {
  return (
    <div onClick={onClick} style={{
      width: 38, height: 38, borderRadius: 12,
      background: on ? T.ink : '#fff',
      color: on ? T.yellow : T.ink,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      boxShadow: '0 0 0 0.5px rgba(0,0,0,0.06), 0 2px 6px rgba(0,0,0,0.04)',
      cursor: 'pointer',
    }}>
      {on ? (
        <svg width="18" height="18" viewBox="0 0 24 24"><path d="M3 3l18 18M10.6 6.1A10 10 0 0112 6c5 0 9 6 9 6a17 17 0 01-2.3 3M6.3 6.3A17 17 0 003 12s4 6 9 6a9 9 0 003.7-.8M9.9 9.9a3 3 0 004.2 4.2" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"/></svg>
      ) : (
        <svg width="18" height="18" viewBox="0 0 24 24"><path d="M3 12s4-6 9-6 9 6 9 6-4 6-9 6-9-6-9-6z" fill="none" stroke="currentColor" strokeWidth="1.8"/><circle cx="12" cy="12" r="3" fill="none" stroke="currentColor" strokeWidth="1.8"/></svg>
      )}
    </div>
  );
}

Object.assign(window, {
  T, FONT_DISPLAY, FONT_BODY, FONT_MONO,
  parseHM, fmtHMcn, fmtMoneyInt,
  computeDay, poseFromStatus, statusCopy, quote,
  Wordmark, YenBadge, SpeechBubble, PillButton, YellowPill,
  TabBar, TopBar, PrivacyToggle,
});
