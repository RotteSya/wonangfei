// settings.jsx — 我的页 · 可操作版
// Everything that looked like input now actually mutates state via `actions`.
// New: 没有午休 toggle hides the lunch rows when on.
function SettingsScreen({ cfg, privacy, onPrivacy, actions, onNavigate }) {
  const day = computeDay(cfg, parseHM(cfg.workEnd));
  const hourly = day.hourlyRate;

  // Inline-edit state for the salary value.
  const [editing, setEditing] = React.useState(false);
  const [draft, setDraft] = React.useState(String(cfg.monthlySalary));
  React.useEffect(() => {
    if (!editing) setDraft(String(cfg.monthlySalary));
  }, [cfg.monthlySalary, editing]);

  const commitSalary = () => {
    const n = Math.max(0, Math.round(Number(draft) || 0));
    actions.setSalary(n);
    setEditing(false);
  };

  return (
    <div style={{
      background: T.bg, height: '100%',
      fontFamily: FONT_BODY, color: T.ink,
      overflowY: 'auto', position: 'relative',
    }}>
      <div style={{ height: 54 }} />
      <TopBar right={<PrivacyToggle on={privacy} onClick={onPrivacy} />} />

      {/* Profile banner */}
      <div style={{
        margin: '6px 18px 0', padding: '20px 22px',
        background: T.ink, color: '#fff',
        borderRadius: 28, position: 'relative', overflow: 'hidden',
      }}>
        <div style={{
          position: 'absolute', right: -30, top: -50,
          fontFamily: FONT_DISPLAY, fontSize: 260,
          color: 'rgba(255,200,61,0.15)', lineHeight: 1, pointerEvents: 'none',
        }}>¥</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, position: 'relative' }}>
          <img
            src={WNF_MASCOT_ROOT + 'hero-mascot.png'}
            alt="窝囊牛"
            style={{
              width: 64, height: 64, borderRadius: 18,
              objectFit: 'cover', objectPosition: 'center 42%',
              flexShrink: 0,
              border: '1px solid rgba(255,255,255,0.16)',
              display: 'block',
            }}
          />
          <div style={{ minWidth: 0 }}>
            <div style={{
              fontFamily: FONT_DISPLAY, fontSize: 26, color: '#fff', letterSpacing: -0.2,
              lineHeight: 1.1,
            }}>窝囊费打工人</div>
            <div style={{
              marginTop: 4, fontSize: 12, color: 'rgba(255,255,255,0.55)', fontWeight: 700,
              display: 'flex', alignItems: 'center', gap: 6,
            }}>
              <YenBadge size={12} />
              <span>
                时薪 {privacy ? '¥••' : `¥${hourly.toFixed(0)}`}
                {cfg.noLunch
                  ? ' · 不午休'
                  : ` · 已忍 ${Math.round(day.workdayLen/60 * 9.4)} 小时`}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* 收入 */}
      <Section title="收入">
        <Row label="月薪 · 税后">
          <SalaryEditor
            value={cfg.monthlySalary}
            draft={draft} setDraft={setDraft}
            editing={editing} setEditing={setEditing}
            commit={commitSalary}
            privacy={privacy}
            onStep={(d) => actions.setSalary(cfg.monthlySalary + d)}
          />
        </Row>
        <Row label="每月工作日">
          <Stepper
            value={`${cfg.workdaysPerMonth} 天`}
            onMinus={() => actions.setWorkdays(cfg.workdaysPerMonth - 1)}
            onPlus={() => actions.setWorkdays(cfg.workdaysPerMonth + 1)}
          />
        </Row>
        <Row label="时薪 · 自动算" last>
          <YellowChip value={privacy ? '¥ ••.•/h' : `¥${hourly.toFixed(1)}/h`} />
        </Row>
      </Section>

      {/* 工作日 */}
      <Section title="工作日">
        <div style={{ padding: '12px 14px' }}>
          <div style={{ display: 'flex', gap: 6, justifyContent: 'space-between' }}>
            {['一','二','三','四','五','六','日'].map((d, i) => {
              const on = cfg.weekdays.includes(i);
              return (
                <button key={i}
                  onClick={() => actions.toggleWeekday(i)}
                  style={{
                    appearance: 'none', border: 'none', cursor: 'pointer',
                    flex: 1, height: 40, borderRadius: 12,
                    background: on ? T.ink : T.cardSoft,
                    color: on ? T.yellow : T.muted,
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    fontFamily: FONT_DISPLAY, fontSize: 16,
                    boxShadow: on ? '0 4px 10px rgba(13,13,13,0.18)' : 'none',
                    transition: 'all .2s',
                  }}>{d}</button>
              );
            })}
          </div>
          <div style={{
            marginTop: 8, fontSize: 10.5, color: T.muted, fontWeight: 700,
          }}>已选 {cfg.weekdays.length} 天 · 每周窝囊 {cfg.weekdays.length} 次</div>
        </div>
      </Section>

      {/* 时间 */}
      <Section title="时间">
        <TimeRow label="上班" icon="sunrise" value={cfg.workStart}
          onChange={(v) => actions.setTime('workStart', v)} />
        <TimeRow label="下班" icon="sunset" value={cfg.workEnd}
          onChange={(v) => actions.setTime('workEnd', v)} />

        {/* 午休 toggle */}
        <ToggleRow
          icon="lunch" iconBg={T.cardSoft}
          title="午休"
          sub={cfg.noLunch ? '中午也在搬砖 · 时薪已重新计算' : '默认有一小时午休'}
          on={!cfg.noLunch}
          onToggle={() => actions.setNoLunch(!cfg.noLunch)}
          last={cfg.noLunch}
        />

        {/* Lunch rows — fold away when noLunch is on */}
        <FoldAway open={!cfg.noLunch}>
          <TimeRow label="午休开始" icon="bowl" value={cfg.lunchStart}
            onChange={(v) => actions.setTime('lunchStart', v)} />
          <TimeRow label="午休结束" icon="coffee" value={cfg.lunchEnd}
            onChange={(v) => actions.setTime('lunchEnd', v)} last />
        </FoldAway>
      </Section>

      {/* 其它 */}
      <Section title="其它">
        <ToggleRow
          icon="clock" iconBg={T.coralSoft}
          title="计入加班"
          sub="超过下班时间也算工资"
          on={cfg.overtime}
          onToggle={() => actions.setOvertime(!cfg.overtime)}
        />
        <ToggleRow
          icon="eye" iconBg={T.cyanSoft}
          title="截图隐藏工资"
          sub="给同事看时打码 · 隐藏明细"
          on={privacy}
          onToggle={() => actions.setPrivacy(!privacy)}
          last
        />
      </Section>

      <div style={{
        textAlign: 'center', padding: '24px 32px 30px',
        fontFamily: FONT_BODY,
      }}>
        <div style={{
          fontFamily: FONT_DISPLAY, fontSize: 14, color: T.muted, marginBottom: 4,
          letterSpacing: 2,
        }}>算 了 算 了</div>
        <div style={{ fontSize: 11, color: T.muted, fontWeight: 600, lineHeight: 1.55 }}>
          数据仅本地存储 · 我们不知道你赚多少<br/>
          也别让老板知道你装了这个 app
        </div>
      </div>

      <div style={{ height: 80 }} />
      <TabBar active="settings" onNavigate={onNavigate} />
    </div>
  );
}

// ───────── primitives ─────────────────────────────────────────────

function Section({ title, children }) {
  return (
    <>
      <div style={{
        padding: '20px 28px 8px', fontFamily: FONT_BODY,
        fontSize: 11, color: T.muted, fontWeight: 800,
        letterSpacing: 1.5, textTransform: 'uppercase',
      }}>{title}</div>
      <div style={{
        margin: '0 18px', background: '#fff',
        borderRadius: 22, border: `0.5px solid ${T.hair}`,
        overflow: 'hidden',
      }}>{children}</div>
    </>
  );
}

function Row({ label, children, last }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '14px 16px', minHeight: 30,
      borderBottom: last ? 'none' : `0.5px solid ${T.hair}`,
    }}>
      <span style={{ fontSize: 14.5, fontWeight: 700, color: T.ink }}>{label}</span>
      {children}
    </div>
  );
}

// Salary — inline editable. Click number to type, blur/Enter to save.
// -¥500 / +¥500 step buttons flank it.
function SalaryEditor({ value, draft, setDraft, editing, setEditing, commit, privacy, onStep }) {
  const inputRef = React.useRef(null);
  React.useEffect(() => { if (editing && inputRef.current) inputRef.current.select(); }, [editing]);
  const stepBtn = {
    appearance: 'none', border: 'none', cursor: 'pointer',
    width: 24, height: 24, borderRadius: 8,
    background: '#fff', color: T.ink, fontWeight: 800, fontSize: 13,
    boxShadow: '0 0 0 0.5px rgba(0,0,0,0.06)',
  };
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 4,
      background: T.cardSoft, padding: 3, borderRadius: 12,
      border: `0.5px solid rgba(255,200,61,0.3)`,
    }}>
      <button style={stepBtn} onClick={() => onStep(-500)}>−</button>
      <div style={{
        display: 'inline-flex', alignItems: 'baseline', gap: 3, padding: '0 8px',
      }}>
        <span style={{ color: T.ink, fontSize: 12, fontWeight: 800 }}>¥</span>
        {editing ? (
          <input
            ref={inputRef}
            type="number"
            inputMode="numeric"
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onBlur={commit}
            onKeyDown={(e) => {
              if (e.key === 'Enter') { e.preventDefault(); e.currentTarget.blur(); }
              if (e.key === 'Escape') { setDraft(String(value)); setEditing(false); }
            }}
            style={{
              width: 72, appearance: 'textfield',
              border: 'none', outline: 'none', background: 'transparent',
              fontFamily: FONT_MONO, fontSize: 14, fontWeight: 800,
              color: T.ink, textAlign: 'right', padding: 0,
            }}
          />
        ) : (
          <span
            onClick={() => setEditing(true)}
            style={{
              fontFamily: FONT_MONO, fontSize: 14, fontWeight: 800,
              color: T.ink, fontVariantNumeric: 'tabular-nums',
              minWidth: 64, textAlign: 'right', cursor: 'text',
            }}
          >{privacy ? '••,•••' : value.toLocaleString()}</span>
        )}
        <span style={{ fontSize: 11, color: T.muted, fontWeight: 700 }}>/月</span>
      </div>
      <button style={stepBtn} onClick={() => onStep(500)}>+</button>
    </div>
  );
}

function YellowChip({ value }) {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center',
      background: T.yellow, color: T.ink,
      padding: '4px 10px', borderRadius: 999,
      fontFamily: FONT_MONO, fontSize: 13, fontWeight: 800,
      fontVariantNumeric: 'tabular-nums',
    }}>{value}</span>
  );
}

function Stepper({ value, onMinus, onPlus }) {
  const btn = {
    appearance: 'none', border: 'none', cursor: 'pointer',
    width: 26, height: 24, borderRadius: 7,
    background: '#fff', color: T.ink, fontWeight: 800, fontSize: 13,
    boxShadow: '0 0 0 0.5px rgba(0,0,0,0.05)',
  };
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 2,
      background: T.cardSoft, borderRadius: 10, padding: 2,
    }}>
      <button style={btn} onClick={onMinus}>−</button>
      <span style={{
        minWidth: 50, textAlign: 'center', fontFamily: FONT_MONO,
        fontSize: 13.5, fontWeight: 800, color: T.ink,
      }}>{value}</span>
      <button style={btn} onClick={onPlus}>+</button>
    </div>
  );
}

// Real <input type="time"> styled to match the existing pill.
function TimeRow({ label, value, icon, onChange, last }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '14px 16px', minHeight: 30,
      borderBottom: last ? 'none' : `0.5px solid ${T.hair}`,
    }}>
      <span style={{ fontSize: 14.5, fontWeight: 700, color: T.ink }}>{label}</span>
      <label style={{
        display: 'inline-flex', alignItems: 'center', gap: 6,
        background: T.cardSoft, padding: '6px 12px', borderRadius: 10,
        border: `0.5px solid rgba(255,200,61,0.25)`,
        cursor: 'pointer',
      }}>
        <RowIcon kind={icon} />
        <input
          type="time"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          style={{
            appearance: 'none', border: 'none', outline: 'none',
            background: 'transparent',
            fontFamily: FONT_MONO, fontSize: 14, fontWeight: 800,
            color: T.ink, fontVariantNumeric: 'tabular-nums',
            padding: 0, width: 64,
          }}
        />
      </label>
    </div>
  );
}

function ToggleRow({ icon, iconBg, title, sub, on, onToggle, last }) {
  return (
    <div onClick={onToggle} style={{
      display: 'flex', alignItems: 'center', padding: '13px 16px',
      borderBottom: last ? 'none' : `0.5px solid ${T.hair}`,
      cursor: onToggle ? 'pointer' : 'default',
    }}>
      <div style={{
        width: 34, height: 34, borderRadius: 11, background: iconBg || T.cardSoft,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        marginRight: 12, color: T.ink,
      }}>
        <RowIcon kind={icon} />
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14.5, fontWeight: 800, color: T.ink }}>{title}</div>
        {sub && <div style={{ fontSize: 11.5, color: T.muted, marginTop: 1, fontWeight: 600 }}>{sub}</div>}
      </div>
      <Switch on={on} />
    </div>
  );
}

function Switch({ on }) {
  return (
    <div style={{
      width: 50, height: 30, borderRadius: 999,
      background: on ? T.ink : '#D7D2C5',
      position: 'relative', transition: 'background .2s',
      flexShrink: 0,
    }}>
      <div style={{
        width: 26, height: 26, borderRadius: 999, background: on ? T.yellow : '#fff',
        position: 'absolute', top: 2, left: on ? 22 : 2,
        boxShadow: '0 1px 3px rgba(0,0,0,0.18)',
        transition: 'left .2s, background .2s',
      }} />
    </div>
  );
}

// Smooth height fold for the lunch rows
function FoldAway({ open, children }) {
  return (
    <div style={{
      display: 'grid',
      gridTemplateRows: open ? '1fr' : '0fr',
      transition: 'grid-template-rows .3s cubic-bezier(.32,.72,0,1)',
    }}>
      <div style={{ overflow: 'hidden' }}>{children}</div>
    </div>
  );
}

// Tiny stroked icon set — replaces emoji slop with on-brand glyphs.
function RowIcon({ kind }) {
  const s = { fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round' };
  switch (kind) {
    case 'sunrise':
      return (
        <svg width="16" height="16" viewBox="0 0 24 24">
          <path d="M3 18h18" {...s}/>
          <path d="M6 18a6 6 0 0 1 12 0" {...s}/>
          <path d="M12 4v3M5 8l2 2M19 8l-2 2" {...s}/>
        </svg>
      );
    case 'sunset':
      return (
        <svg width="16" height="16" viewBox="0 0 24 24">
          <path d="M3 18h18" {...s}/>
          <path d="M6 18a6 6 0 0 1 12 0" {...s}/>
          <path d="M12 9V6M5 12l2-2M19 12l-2-2" {...s}/>
        </svg>
      );
    case 'bowl':
      return (
        <svg width="16" height="16" viewBox="0 0 24 24">
          <path d="M4 12h16a8 8 0 0 1-16 0Z" {...s}/>
          <path d="M3 19h18" {...s}/>
          <path d="M10 7c0-1.5 4-1.5 4 0" {...s}/>
        </svg>
      );
    case 'coffee':
      return (
        <svg width="16" height="16" viewBox="0 0 24 24">
          <path d="M5 10h12v6a4 4 0 0 1-4 4H9a4 4 0 0 1-4-4z" {...s}/>
          <path d="M17 12h2a2 2 0 0 1 0 4h-2" {...s}/>
          <path d="M8 4c0 1.5 1 1.5 1 3M12 4c0 1.5 1 1.5 1 3" {...s}/>
        </svg>
      );
    case 'lunch':
      return (
        <svg width="16" height="16" viewBox="0 0 24 24">
          <rect x="3" y="6" width="18" height="14" rx="3" {...s}/>
          <path d="M7 6V4M17 6V4M3 11h18" {...s}/>
        </svg>
      );
    case 'clock':
      return (
        <svg width="16" height="16" viewBox="0 0 24 24">
          <circle cx="12" cy="12" r="9" {...s}/>
          <path d="M12 7v5l3 2" {...s}/>
        </svg>
      );
    case 'eye':
      return (
        <svg width="16" height="16" viewBox="0 0 24 24">
          <path d="M3 12s4-6 9-6 9 6 9 6-4 6-9 6-9-6-9-6Z" {...s}/>
          <circle cx="12" cy="12" r="2.6" {...s}/>
        </svg>
      );
    default:
      return null;
  }
}

Object.assign(window, { SettingsScreen });
