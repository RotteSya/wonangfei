// stats.jsx — 记录页 · 可操作版
// Brand-aligned, fully interactive: 周/月/年 segmented control swaps the
// dataset, individual bars are tappable and surface a floating callout.
function StatsScreen({ cfg, privacy, onPrivacy, onNavigate }) {
  const [tab, setTab] = React.useState('month'); // 'week' | 'month' | 'year'
  const [pickedIdx, setPickedIdx] = React.useState(null);

  // base unit — daily target (一日窝囊费)
  const day = computeDay(cfg, parseHM(cfg.workEnd));
  const dailyAvg = day.targetToday;
  const hourly = day.hourlyRate;

  // ── datasets per tab ────────────────────────────────────────────
  // Numbers are deterministic shapes scaled off the live daily target,
  // so changing salary / workdays in 我的 reshapes the chart honestly.
  const datasets = React.useMemo(() => ({
    week: {
      heroLabel: '本 周 窝 囊 费',
      compareLabel: '比上周',
      delta: '+4.1%',
      bars: [
        { key: '一', long: '周一', mult: 1.00, state: 'past' },
        { key: '二', long: '周二', mult: 1.08, state: 'past' },
        { key: '三', long: '周三', mult: 0.93, state: 'past' },
        { key: '四', long: '今日',  mult: 0.62, state: 'today' },
        { key: '五', long: '周五', mult: 0,    state: 'future' },
        { key: '六', long: '周六', mult: 0,    state: 'future' },
        { key: '日', long: '周日', mult: 0,    state: 'future' },
      ],
      subtitle: '周一 – 周日',
      tile1: ['本周日均', dailyAvg, '每天的窝囊费'],
      tile2: ['加班挣到', dailyAvg * 0.32, '占本周 6.1%'],
      tile3: ['周时薪',    hourly, '基于税后月薪'],
      tile4: ['情绪温度', 0,          '丧但还顶得住'],
      caption: (b) => `${b.long} · ${fmtMoneyInt(b.mult * dailyAvg, privacy)}`,
    },
    month: {
      heroLabel: '本 月 窝 囊 费',
      compareLabel: '比上月',
      delta: '+9.2%',
      bars: [
        { key: 'W1', long: '第 1 周', mult: 4.8, state: 'past' },
        { key: 'W2', long: '第 2 周', mult: 5.0, state: 'past' },
        { key: 'W3', long: '第 3 周', mult: 4.2, state: 'past' },
        { key: 'W4', long: '本周',     mult: 3.4, state: 'today' },
        { key: 'W5', long: '第 5 周', mult: 0,   state: 'future' },
      ],
      subtitle: '第 1 – 第 5 周',
      tile1: ['月日均', dailyAvg, '每日的窝囊费'],
      tile2: ['加班挣到', dailyAvg * 0.18 * 9.4, '占本月 6.4%'],
      tile3: ['月时薪',  hourly, '基于税后月薪'],
      tile4: ['已窝囊', Math.round(day.workdayLen / 60 * 9.4), '小时 · 9.4 个工作日'],
      caption: (b) => `${b.long} · ${fmtMoneyInt(b.mult * dailyAvg, privacy)}`,
    },
    year: {
      heroLabel: '本 年 窝 囊 费',
      compareLabel: '比去年',
      delta: '+14%',
      bars: [
        { key: '1', long: '1 月', mult: 22, state: 'past' },
        { key: '2', long: '2 月', mult: 18, state: 'past' },
        { key: '3', long: '3 月', mult: 23, state: 'past' },
        { key: '4', long: '4 月', mult: 22, state: 'past' },
        { key: '5', long: '本月',  mult: 21, state: 'today' },
        { key: '6', long: '6 月', mult: 0,  state: 'future' },
        { key: '7', long: '7 月', mult: 0,  state: 'future' },
        { key: '8', long: '8 月', mult: 0,  state: 'future' },
        { key: '9', long: '9 月', mult: 0,  state: 'future' },
        { key: '10', long: '10 月', mult: 0, state: 'future' },
        { key: '11', long: '11 月', mult: 0, state: 'future' },
        { key: '12', long: '12 月', mult: 0, state: 'future' },
      ],
      subtitle: '1 月 – 12 月',
      tile1: ['年日均', dailyAvg, '每日的窝囊费'],
      tile2: ['加班挣到', dailyAvg * 0.18 * 21 * 4, '占本年 5.8%'],
      tile3: ['年时薪',  hourly, '基于税后月薪'],
      tile4: ['已窝囊', Math.round(day.workdayLen / 60 * 21 * 4.4), '小时 · 96 个工作日'],
      caption: (b) => `${b.long} · ${fmtMoneyInt(b.mult * dailyAvg, privacy)}`,
    },
  }), [dailyAvg, hourly, day.workdayLen, privacy]);

  const cur = datasets[tab];
  const totalShown = cur.bars.reduce((a, b) => a + b.mult * dailyAvg, 0);

  // tap a bar → highlight; tap again → unselect
  const onPickBar = (idx) => setPickedIdx(p => (p === idx ? null : idx));

  // Reset picked bar when tab swaps to keep the callout sane
  React.useEffect(() => { setPickedIdx(null); }, [tab]);

  return (
    <div style={{
      background: T.bg, height: '100%',
      fontFamily: FONT_BODY, color: T.ink,
      overflowY: 'auto', position: 'relative',
    }}>
      <div style={{ height: 54 }} />
      <TopBar right={<PrivacyToggle on={privacy} onClick={onPrivacy} />} />

      {/* HERO — yellow card */}
      <div style={{
        margin: '6px 18px 0',
        background: T.yellow,
        borderRadius: 28,
        padding: '20px 22px 22px',
        position: 'relative', overflow: 'hidden',
        boxShadow: '0 12px 28px rgba(255,200,61,0.30)',
      }}>
        {/* huge ¥ watermark */}
        <div style={{
          position: 'absolute', right: -16, top: -28,
          fontFamily: FONT_DISPLAY, fontSize: 240, color: 'rgba(13,13,13,0.06)',
          lineHeight: 1, pointerEvents: 'none',
        }}>¥</div>

        {/* Period tabs — working segmented control */}
        <SegTabs value={tab} onChange={setTab} options={[
          { v: 'week', label: '周' },
          { v: 'month', label: '月' },
          { v: 'year', label: '年' },
        ]}/>

        <div style={{
          display: 'flex', justifyContent: 'space-between',
          alignItems: 'flex-start', marginTop: 12, position: 'relative',
        }}>
          <div style={{ minWidth: 0 }}>
            <div style={{
              fontSize: 11, fontWeight: 800, color: 'rgba(13,13,13,0.65)',
              letterSpacing: 2,
            }}>{cur.heroLabel}</div>
            <BigYen amount={totalShown} privacy={privacy} />
            <div style={{
              marginTop: 10, display: 'flex', gap: 8, alignItems: 'center',
              fontSize: 12, fontWeight: 700, color: T.ink,
            }}>
              <span style={{
                background: T.ink, color: T.yellow,
                padding: '3px 9px', borderRadius: 999, fontSize: 11,
                display: 'inline-flex', alignItems: 'center', gap: 4,
              }}>
                <svg width="9" height="9" viewBox="0 0 10 10"><path d="M1 7 L5 2 L9 7" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/></svg>
                {cur.delta}
              </span>
              <span style={{ color: 'rgba(13,13,13,0.6)' }}>{cur.compareLabel}</span>
            </div>
          </div>

        </div>

        {/* hero mini line — changes shape per tab */}
        <HeroLine tab={tab} />
      </div>

      {/* Sub-stats — varies per tab */}
      <div style={{ display: 'flex', gap: 10, padding: '14px 18px 0' }}>
        <Tile label={cur.tile1[0]} big
          value={fmtMoneyInt(cur.tile1[1], privacy)}
          sub={cur.tile1[2]} />
        <Tile label={cur.tile2[0]} big tone="coral"
          value={fmtMoneyInt(cur.tile2[1], privacy)}
          sub={cur.tile2[2]} />
      </div>
      <div style={{ display: 'flex', gap: 10, padding: '10px 18px 0' }}>
        <Tile label={cur.tile3[0]} tone="cyan"
          value={privacy ? '¥••/h' : `¥${cur.tile3[1].toFixed(0)}/h`}
          sub={cur.tile3[2]} />
        <Tile label={cur.tile4[0]}
          value={typeof cur.tile4[1] === 'number' && cur.tile4[1] > 0
            ? `${cur.tile4[1]}h`
            : '半丧'}
          sub={cur.tile4[2]} />
      </div>

      {/* Achievement card — month-scoped (always) */}
      <div style={{
        margin: '14px 18px 0', borderRadius: 22, padding: '16px 18px',
        background: T.ink, color: '#fff',
        display: 'flex', alignItems: 'center', gap: 16,
        position: 'relative', overflow: 'hidden',
      }}>
        <div style={{ position: 'absolute', top: 12, right: 90, color: T.yellow, fontSize: 14 }}>✦</div>
        <div style={{ position: 'absolute', bottom: 18, right: 60, color: T.yellow, opacity: 0.5, fontSize: 10 }}>✦</div>

        <img
          src={WNF_MASCOT_ROOT + 'hero-mascot.png'}
          alt="窝囊牛"
          style={{
            width: 56, height: 56, borderRadius: 18,
            objectFit: 'cover', objectPosition: 'center 42%',
            flexShrink: 0,
            border: `1px solid rgba(255,255,255,0.16)`,
            display: 'block',
          }}
        />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{
            fontSize: 10.5, color: T.yellow, fontWeight: 800,
            letterSpacing: 1.5, marginBottom: 3,
          }}>★ 本 月 成 就</div>
          <div style={{
            fontFamily: FONT_DISPLAY, fontSize: 22, letterSpacing: -0.5,
            color: '#fff', lineHeight: 1.15,
          }}>
            本月已窝囊 <span style={{ color: T.yellow }}>{Math.round(day.workdayLen / 60 * 9.4)}</span> 小时
          </div>
          <div style={{ fontSize: 11.5, color: 'rgba(255,255,255,0.55)', marginTop: 4, fontWeight: 600 }}>
            相当于看完 {Math.round(day.workdayLen / 60 * 9.4 / 2)} 集《甄嬛传》
          </div>
        </div>
      </div>

      {/* Bar chart — tappable */}
      <div style={{
        margin: '14px 18px 0', borderRadius: 22, padding: '16px 18px 14px',
        background: '#fff', border: `0.5px solid ${T.hair}`,
      }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
          <span style={{ fontFamily: FONT_DISPLAY, fontSize: 18, color: T.ink, letterSpacing: -0.2 }}>
            {tab === 'week' ? '本周每日' : tab === 'month' ? '本月每周' : '本年每月'}窝囊费
          </span>
          <span style={{ fontSize: 11, color: T.muted, fontWeight: 700 }}>{cur.subtitle}</span>
        </div>
        <BarChart
          bars={cur.bars}
          dailyAvg={dailyAvg}
          pickedIdx={pickedIdx}
          onPick={onPickBar}
          caption={cur.caption}
          tab={tab}
        />
        <div style={{
          marginTop: 8, fontSize: 11, color: T.muted, fontWeight: 700,
          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
        }}>
          <span>点击柱子查看明细</span>
          {pickedIdx != null && (
            <button onClick={() => setPickedIdx(null)} style={{
              appearance: 'none', border: 'none', cursor: 'pointer',
              background: 'transparent', color: T.ink,
              fontFamily: FONT_BODY, fontWeight: 800, fontSize: 11,
              textDecoration: 'underline', padding: 0,
            }}>取消选中</button>
          )}
        </div>
      </div>

      {/* Badges */}
      <div style={{
        margin: '14px 18px 22px', borderRadius: 22, padding: '14px 18px',
        background: '#fff', border: `0.5px solid ${T.hair}`,
      }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12 }}>
          <span style={{ fontFamily: FONT_DISPLAY, fontSize: 18, color: T.ink, letterSpacing: -0.2 }}>窝囊徽章</span>
          <span style={{ fontSize: 11, color: T.muted, fontWeight: 700 }}>3 / 8 解锁</span>
        </div>
        <div style={{ display: 'flex', gap: 10, justifyContent: 'space-between' }}>
          <BadgeIcon kind="sleep"   label="早八勇士" unlocked />
          <BadgeIcon kind="lunch"   label="午休大师" unlocked />
          <BadgeIcon kind="clock"   label="加班 +1" unlocked />
          <BadgeIcon kind="cow"     label="忍 100h" />
        </div>
      </div>

      <div style={{ height: 90 }} />
      <TabBar active="stats" onNavigate={onNavigate} />
    </div>
  );
}

// ───────── primitives ─────────────────────────────────────────────

// Yellow-hero big yen number
function BigYen({ amount, privacy }) {
  if (privacy) {
    return (
      <div style={{
        marginTop: 6, fontFamily: FONT_DISPLAY,
        fontSize: 56, lineHeight: 0.95,
        letterSpacing: -1.5, color: T.ink,
        display: 'flex', alignItems: 'baseline',
      }}>
        <span>¥</span><span style={{ letterSpacing: 4 }}>••,•••</span>
      </div>
    );
  }
  const intPart = Math.floor(amount).toLocaleString('en-US');
  const decPart = (amount % 1).toFixed(2).slice(2);
  return (
    <div style={{
      marginTop: 6, fontFamily: FONT_DISPLAY,
      fontSize: 56, lineHeight: 0.95,
      letterSpacing: -1.5, color: T.ink,
      fontVariantNumeric: 'tabular-nums',
      display: 'flex', alignItems: 'baseline',
    }}>
      <span>¥</span><span>{intPart}</span>
      <span style={{ fontSize: 28, marginLeft: 3, color: 'rgba(13,13,13,0.55)' }}>.{decPart}</span>
    </div>
  );
}

// 周 / 月 / 年 segmented control — ink pill with a sliding yellow chip
function SegTabs({ value, onChange, options }) {
  return (
    <div style={{
      display: 'inline-flex',
      background: 'rgba(13,13,13,0.85)', padding: 3, borderRadius: 999,
      position: 'relative',
    }}>
      {options.map((o) => {
        const on = o.v === value;
        return (
          <button key={o.v} onClick={() => onChange(o.v)} style={{
            appearance: 'none', border: 'none', cursor: 'pointer',
            padding: '6px 16px', borderRadius: 999,
            fontFamily: FONT_BODY, fontSize: 12, fontWeight: 800, letterSpacing: 1,
            background: on ? T.yellow : 'transparent',
            color: on ? T.ink : 'rgba(255,255,255,0.65)',
            transition: 'all .25s cubic-bezier(.32,.72,0,1)',
          }}>{o.label}</button>
        );
      })}
    </div>
  );
}

// hero mini line — changes shape per tab
function HeroLine({ tab }) {
  const paths = {
    week:  'M0 56 L40 50 L80 52 L120 38 L160 30 L200 24 L240 18 L280 14 L320 8',
    month: 'M0 60 L40 56 L80 44 L120 48 L160 32 L200 28 L240 22 L280 16 L320 10',
    year:  'M0 62 L40 58 L80 46 L120 36 L160 42 L200 30 L240 24 L280 22 L320 12',
  };
  const fillPath = paths[tab] + ' L320 70 L0 70 Z';
  const lastY = Number(paths[tab].split(' ').slice(-1)[0]);
  return (
    <div style={{ marginTop: 14, height: 60, position: 'relative' }}>
      <svg width="100%" height="60" viewBox="0 0 320 70" preserveAspectRatio="none" style={{ display: 'block' }}>
        <defs>
          <linearGradient id="hero-line-g" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={T.ink} stopOpacity="0.18"/>
            <stop offset="100%" stopColor={T.ink} stopOpacity="0"/>
          </linearGradient>
        </defs>
        <path d={fillPath} fill="url(#hero-line-g)"/>
        <path d={paths[tab]} fill="none" stroke={T.ink} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/>
        <circle cx="320" cy={lastY} r="5" fill={T.ink}/>
        <circle cx="320" cy={lastY} r="2.5" fill={T.yellow}/>
      </svg>
    </div>
  );
}

// stat tile
function Tile({ label, value, sub, tone = 'default', big }) {
  const accent = tone === 'cyan' ? T.cyan : tone === 'coral' ? T.coral : T.yellow;
  return (
    <div style={{
      flex: 1, background: '#fff', borderRadius: 20,
      padding: '14px 14px',
      border: `0.5px solid ${T.hair}`,
    }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span style={{ fontSize: 11.5, color: T.muted, fontWeight: 800, letterSpacing: 0.3 }}>{label}</span>
        <span style={{ width: 6, height: 6, borderRadius: 3, background: accent }} />
      </div>
      <div style={{
        marginTop: 5, fontFamily: FONT_MONO, fontWeight: 800,
        fontSize: big ? 22 : 18, color: T.ink, letterSpacing: -0.4,
        fontVariantNumeric: 'tabular-nums',
      }}>{value}</div>
      <div style={{ fontSize: 11, color: T.muted, marginTop: 1, fontWeight: 600 }}>{sub}</div>
    </div>
  );
}

// tappable bar chart with floating callout
function BarChart({ bars, dailyAvg, pickedIdx, onPick, caption, tab }) {
  const maxMult = Math.max(...bars.map(b => b.mult), 1);
  const isCompact = tab === 'year';   // 12 bars need to be slim
  const trackH = 100;
  return (
    <div style={{ position: 'relative', marginTop: 24 }}>
      <div style={{
        display: 'flex', alignItems: 'flex-end',
        gap: isCompact ? 4 : 10, height: trackH + 28,
      }}>
        {bars.map((b, i) => {
          const isFuture = b.state === 'future';
          const isToday  = b.state === 'today';
          const isPicked = i === pickedIdx;
          const h = isFuture ? 5 : Math.max(8, (b.mult / maxMult) * trackH);

          let barBg;
          if (isPicked) barBg = T.ink;
          else if (isFuture) barBg = '#F2EAD2';
          else if (isToday) barBg = T.ink;
          else barBg = T.yellow;

          return (
            <button key={b.key + i}
              onClick={() => !isFuture && onPick(i)}
              style={{
                flex: 1, height: trackH + 28,
                appearance: 'none', border: 'none', background: 'transparent',
                padding: 0,
                cursor: isFuture ? 'default' : 'pointer',
                display: 'flex', flexDirection: 'column', alignItems: 'center',
                justifyContent: 'flex-end',
                position: 'relative',
              }}>
              {/* picked floating callout above this bar */}
              {isPicked && (
                <div style={{
                  position: 'absolute', top: -8, left: '50%',
                  transform: 'translateX(-50%)',
                  background: T.ink, color: '#fff',
                  fontFamily: FONT_BODY, fontWeight: 800, fontSize: 10.5,
                  padding: '5px 10px', borderRadius: 999, whiteSpace: 'nowrap',
                  boxShadow: '0 8px 16px rgba(13,13,13,0.25)',
                  pointerEvents: 'none',
                }}>
                  <span style={{ color: T.yellow }}>●</span> {caption(b)}
                </div>
              )}
              {/* today pill (only when not picked) */}
              {isToday && !isPicked && (
                <div style={{
                  position: 'absolute', top: 0, left: '50%',
                  transform: 'translateX(-50%)',
                  fontSize: 9.5, color: T.ink, fontWeight: 800,
                  background: T.yellow, padding: '2px 7px', borderRadius: 999,
                  whiteSpace: 'nowrap', pointerEvents: 'none',
                }}>{tab === 'week' ? '今日' : tab === 'month' ? '本周' : '本月'}</div>
              )}
              <div style={{
                width: isCompact ? '80%' : '60%',
                height: h, borderRadius: isCompact ? 4 : 8,
                background: barBg,
                marginBottom: 22,
                transition: 'background .2s, transform .2s',
                transform: isPicked ? 'translateY(-2px)' : 'translateY(0)',
                boxShadow: isPicked ? '0 8px 16px rgba(13,13,13,0.25)' : 'none',
              }} />
              <span style={{
                position: 'absolute', bottom: 0, left: 0, right: 0,
                fontSize: isCompact ? 9 : 11,
                color: isToday || isPicked ? T.ink : T.muted,
                fontWeight: isToday || isPicked ? 800 : 700,
                textAlign: 'center', pointerEvents: 'none',
              }}>{b.key}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

// Brand-style badge — small cow / coin glyphs
function BadgeIcon({ kind, label, unlocked }) {
  return (
    <div style={{
      flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 5,
      opacity: unlocked ? 1 : 0.42,
    }}>
      <div style={{
        width: 48, height: 48, borderRadius: 16,
        background: unlocked ? T.yellow : '#F2EAD2',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        boxShadow: unlocked ? '0 4px 10px rgba(255,200,61,0.3)' : 'none',
        filter: unlocked ? 'none' : 'grayscale(1)',
        color: T.ink,
      }}>
        <BadgeGlyph kind={kind} />
      </div>
      <span style={{ fontSize: 10.5, color: T.muted, fontWeight: 800 }}>{label}</span>
    </div>
  );
}

function BadgeGlyph({ kind }) {
  const s = { fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round' };
  if (kind === 'sleep') {
    return (
      <svg width="24" height="24" viewBox="0 0 24 24">
        <path d="M15.5 4a8 8 0 1 0 4.5 12.5A6.5 6.5 0 0 1 15.5 4Z" {...s} fill="currentColor"/>
        <path d="M5 6h3l-3 4h3" {...s}/>
      </svg>
    );
  }
  if (kind === 'lunch') {
    return (
      <svg width="24" height="24" viewBox="0 0 24 24">
        <path d="M4 12h16a8 8 0 0 1-16 0Z" {...s} fill="currentColor"/>
        <path d="M3 19h18" {...s}/>
        <path d="M10 8c0-1.5 4-1.5 4 0M8 6c0-1.5 8-1.5 8 0" {...s}/>
      </svg>
    );
  }
  if (kind === 'clock') {
    return (
      <svg width="24" height="24" viewBox="0 0 24 24">
        <circle cx="12" cy="12" r="9" {...s}/>
        <path d="M12 7v5l3 2" {...s}/>
      </svg>
    );
  }
  // cow — tiny coin with ¥
  return (
    <svg width="24" height="24" viewBox="0 0 24 24">
      <circle cx="12" cy="12" r="9" {...s} fill="currentColor"/>
      <text x="12" y="16" textAnchor="middle" fontFamily={FONT_DISPLAY} fontSize="13" fill="#FFC83D">¥</text>
    </svg>
  );
}

Object.assign(window, { StatsScreen });
