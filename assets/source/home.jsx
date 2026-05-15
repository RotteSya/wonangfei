// home.jsx — Home is a single hero screen.
function HomeScreen({
  cfg, nowMin, privacy, onPrivacy,
  statusTime,
  onNavigate,
}) {
  const d = computeDay(cfg, nowMin);
  const pose = poseFromStatus(d.status, d.progressPct);

  const totalCents = Math.max(0, Math.floor(d.earnedToday * 100));
  const yuan = Math.floor(totalCents / 100).toLocaleString('en-US');
  const cents = String(totalCents % 100).padStart(2, '0');

  return (
    <div
      style={{
        background: T.bg, height: '100%',
        fontFamily: FONT_BODY, color: T.ink,
        position: 'relative', overflow: 'hidden',
        touchAction: 'manipulation',
      }}>

      <HeroPage
        d={d} cfg={cfg} pose={pose}
        yuan={yuan} cents={cents}
        privacy={privacy} onPrivacy={onPrivacy} />

      {/* fixed tab bar */}
      <div data-no-pager-drag style={{ position: 'absolute', left: 0, right: 0, bottom: 0, zIndex: 80 }}>
        <TabBar active="home" onNavigate={onNavigate} />
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// HOME HERO
// ─────────────────────────────────────────────────────────────
function HeroPage({ d, cfg, pose, yuan, cents, privacy, onPrivacy }) {
  return (
    <div style={{ height: '100%', position: 'relative' }}>
      {/* status spacer */}
      <div style={{ height: 54 }} />

      <TopBar right={
        <span data-no-pager-drag>
          <PrivacyToggle on={privacy} onClick={onPrivacy} />
        </span>
      } />

      <div style={{ padding: '6px 22px 0', position: 'relative' }}>
        {/* status chip */}
        <div style={{
          display: 'inline-flex', alignItems: 'center', gap: 6,
          background: T.cardSoft, color: T.ink,
          padding: '6px 12px', borderRadius: 999,
          fontFamily: FONT_BODY, fontSize: 12, fontWeight: 800,
        }}>
          <span style={{
            width: 6, height: 6, borderRadius: 3, background: T.coral,
            boxShadow: `0 0 0 3px ${T.coralSoft}`,
          }} />
          {statusCopy(d.status)}
        </div>

        <div style={{
          marginTop: 18, fontSize: 13, fontWeight: 800,
          color: T.inkSoft, letterSpacing: 2,
        }}>今 日 窝 囊 费</div>

        <div style={{
          marginTop: 4, fontFamily: FONT_DISPLAY,
          fontSize: 86, lineHeight: 0.92,
          color: T.ink, letterSpacing: 0,
          display: 'flex', alignItems: 'baseline',
          fontVariantNumeric: 'tabular-nums',
          transition: 'filter 0.16s ease',
        }}>
          {privacy ? (
            <>
              <span style={{ color: T.yellow }}>¥</span>
              <span style={{ letterSpacing: 4 }}>•••</span>
              <span style={{ fontSize: 44, color: T.muted, marginLeft: 4 }}>.••</span>
            </>
          ) : (
            <>
              <span style={{ color: T.yellow, marginRight: 4 }}>¥</span>
              <span>{yuan}</span>
              <span style={{ fontSize: 44, color: T.muted, marginLeft: 4 }}>.{cents}</span>
            </>
          )}
        </div>

        <div style={{
          marginTop: 14, display: 'flex', gap: 22, alignItems: 'center',
          fontFamily: FONT_BODY, fontSize: 13.5, fontWeight: 700,
          color: T.inkSoft,
        }}>
          <span>已忍 <span style={{
            fontFamily: FONT_MONO, color: T.ink, fontWeight: 800,
          }}>{fmtHMcn(d.elapsedPaid)}</span></span>
          <span style={{ width: 4, height: 4, borderRadius: 2, background: T.muted }} />
          <span>离下班 <span style={{
            fontFamily: FONT_MONO, color: T.ink, fontWeight: 800,
          }}>{fmtHMcn(d.wallToEnd)}</span></span>
        </div>

        {/* progress bar */}
        <div style={{ marginTop: 22, position: 'relative' }}>
          <div style={{
            height: 12, borderRadius: 999,
            background: '#F2E6BE', position: 'relative', overflow: 'hidden',
          }}>
            <div style={{
              position: 'absolute', left: 0, top: 0, bottom: 0,
              width: `${d.progressPct * 100}%`,
              background: `linear-gradient(90deg, ${T.gold} 0%, ${T.yellow} 100%)`,
              borderRadius: 999,
              transition: 'width 0.6s ease',
            }} />
            {d.progressPct > 0 && d.progressPct < 1 && (
              <div style={{
                position: 'absolute', top: -4, bottom: -4,
                left: `calc(${d.progressPct * 100}% - 6px)`,
                width: 12, borderRadius: 6,
                background: '#fff', border: `3px solid ${T.ink}`,
                boxShadow: '0 2px 4px rgba(0,0,0,0.15)',
              }} />
            )}
          </div>
          <div style={{
            display: 'flex', justifyContent: 'space-between', marginTop: 8,
            fontSize: 11, fontWeight: 700, color: T.muted,
            fontFamily: FONT_MONO, letterSpacing: 0.4,
          }}>
            <span>{cfg.workStart}</span>
            <span>{(d.progressPct * 100).toFixed(0)}%</span>
            <span>{cfg.workEnd}</span>
          </div>
        </div>
      </div>

      {/* cow */}
      <div style={{
        position: 'absolute',
        bottom: 150,
        right: 0, left: 0,
        display: 'flex', justifyContent: 'center',
        pointerEvents: 'none',
      }}>
        <div style={{ position: 'relative' }}>
          <Cow pose={pose} size={260} />
          <div style={{ position: 'absolute', top: 10, left: -30 }}>
            <SpeechBubble bg="#fff">{quote(d.status)}</SpeechBubble>
          </div>
          <div style={{ position: 'absolute', top: 60, right: -10 }}>
            <YenCoin size={26} />
          </div>
          <div style={{ position: 'absolute', bottom: 50, left: -20 }}>
            <YenCoin size={20} />
          </div>
        </div>
      </div>

    </div>
  );
}

// ─────────── small pieces ───────────

function YenCoin({ size = 24 }) {
  return (
    <div style={{
      width: size, height: size, borderRadius: '50%',
      background: `radial-gradient(circle at 30% 30%, #FFEAA0 0%, ${T.gold} 60%, #D89A1A 100%)`,
      color: '#fff', fontFamily: FONT_DISPLAY, fontWeight: 400,
      fontSize: size * 0.6, lineHeight: 1,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      boxShadow: '0 4px 10px rgba(218,154,26,0.35), inset 0 -2px 0 rgba(170,110,20,0.4)',
    }}>¥</div>
  );
}

Object.assign(window, { HomeScreen });
