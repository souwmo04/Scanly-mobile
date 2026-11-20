import React from 'react';
import {AbsoluteFill, Easing, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {Background, clamp, EntryFlash, FeatureTitle, Phone, TextLines} from '../components';
import {C, fonts} from '../theme';

const SW = 564; // phone screen width (Phone width 600 minus bezel)
const SH = 1212;

/** Phone that swings in and keeps a gentle 3D float. */
const FeaturePhone: React.FC<{children: React.ReactNode; from?: number}> = ({children, from = 1}) => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();
  const s = spring({frame, fps, config: {damping: 16, stiffness: 150}});
  const exit = interpolate(frame, [durationInFrames - 8, durationInFrames], [0, 1], clamp);
  return (
    <Phone
      width={600}
      y={230 + (1 - s) * 900 + exit * -60}
      rotateY={from * (1 - s) * 50 + Math.sin(frame / 25) * 7}
      rotateX={8 + Math.cos(frame / 30) * 3}
      scale={1 - exit * 0.08}
    >
      {children}
    </Phone>
  );
};

const SceneShell: React.FC<{index: string; title: string; subtitle: string; glow?: string; from?: number; children: React.ReactNode}> = ({
  index,
  title,
  subtitle,
  glow,
  from,
  children,
}) => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const exit = interpolate(frame, [durationInFrames - 8, durationInFrames], [1, 0], clamp);
  return (
    <AbsoluteFill style={{opacity: exit}}>
      <Background glow={glow} />
      <FeatureTitle index={index} title={title} subtitle={subtitle} />
      <FeaturePhone from={from}>{children}</FeaturePhone>
      <EntryFlash duration={8} />
    </AbsoluteFill>
  );
};

const AppBar: React.FC<{title: string; dark?: boolean}> = ({title, dark}) => (
  <div style={{position: 'absolute', top: 0, left: 0, right: 0, height: 150, paddingTop: 70, paddingLeft: 36, display: 'flex', alignItems: 'center', gap: 26, fontFamily: fonts.latin, fontWeight: 700, fontSize: 34, color: dark ? 'white' : C.navy900, zIndex: 5}}>
    <svg width={36} height={36} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.6} strokeLinecap="round">
      <path d="M19 12H5M11 6l-6 6 6 6" />
    </svg>
    {title}
  </div>
);

/** 5. Auto edge detection: outline hunts, locks, shutter fires. */
export const ScanFeature: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const lockAt = 44;
  const shotAt = 74;
  const lock = interpolate(frame, [20, lockAt], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  const wob = (i: number) => (1 - lock) * Math.sin(frame / 3 + i * 1.7) * 40;
  // Document corners in the camera view (perspective quad).
  const doc = [
    [110, 330],
    [470, 300],
    [500, 860],
    [70, 880],
  ];
  const quad = doc.map(([x, y], i) => [x + wob(i) + (1 - lock) * (i % 3 === 0 ? -60 : 60), y + wob(i + 2) + (1 - lock) * (i < 2 ? -50 : 50)]);
  const locked = frame >= lockAt;
  const ring = interpolate(frame, [lockAt, shotAt], [0, 1], clamp);
  const flash = interpolate(frame, [shotAt, shotAt + 3, shotAt + 12], [0, 1, 0], clamp);
  const review = spring({frame: frame - shotAt - 4, fps, config: {damping: 14}});
  const color = locked ? C.green : C.amber;
  const pts = quad.map((p) => p.join(',')).join(' ');
  return (
    <SceneShell index="০১" title="অটো এজ ডিটেকশন" subtitle="বর্ডার খুঁজে নেয় নিজে থেকেই" glow={C.green}>
      {/* Camera feed */}
      <AbsoluteFill style={{background: 'linear-gradient(160deg, #6b4a32, #3b2718 70%, #2a1b10)'}}>
        <svg width={SW} height={SH} style={{position: 'absolute', inset: 0}}>
          <defs>
            <linearGradient id="paper" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stopColor="#fdfcf7" />
              <stop offset="1" stopColor="#d9d6cc" />
            </linearGradient>
          </defs>
          <polygon points={doc.map((p) => p.join(',')).join(' ')} fill="url(#paper)" />
          {new Array(12).fill(0).map((_, i) => {
            const t = 0.12 + i * 0.065;
            const lx = 110 + (70 - 110) * t + 40;
            const rx = 470 + (500 - 470) * t - 40 - (i % 4 === 3 ? 140 : 0);
            const y1 = 330 + (880 - 330) * t;
            const y2 = 300 + (860 - 300) * t;
            return <line key={i} x1={lx} y1={y1} x2={rx} y2={y2} stroke="#9aa0ab" strokeWidth={9} strokeLinecap="round" />;
          })}
          <polygon points={pts} fill={`${color}33`} stroke={color} strokeWidth={7} strokeLinejoin="round" />
          {quad.map(([x, y], i) => (
            <circle key={i} cx={x} cy={y} r={locked ? 16 + Math.sin(frame / 3) * 3 : 14} fill="white" stroke={color} strokeWidth={6} />
          ))}
        </svg>
        <div style={{position: 'absolute', top: 120, left: 0, right: 0, display: 'flex', justifyContent: 'center'}}>
          <div style={{fontFamily: fonts.bangla, fontWeight: 600, fontSize: 30, color: 'white', background: 'rgba(0,0,0,0.55)', padding: '12px 30px', borderRadius: 40}}>
            {locked ? 'স্থির রাখুন… ছবি তোলা হচ্ছে' : 'ডকুমেন্ট খোঁজা হচ্ছে…'}
          </div>
        </div>
        {/* Shutter with auto ring */}
        <div style={{position: 'absolute', bottom: 70, left: 0, right: 0, display: 'flex', justifyContent: 'center'}}>
          <svg width={150} height={150} viewBox="0 0 150 150">
            <circle cx={75} cy={75} r={66} fill="none" stroke="rgba(255,255,255,0.4)" strokeWidth={8} />
            <circle cx={75} cy={75} r={66} fill="none" stroke={C.green} strokeWidth={8} strokeDasharray={`${ring * 415} 415`} transform="rotate(-90 75 75)" strokeLinecap="round" />
            <circle cx={75} cy={75} r={52} fill="white" />
          </svg>
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{background: 'white', opacity: flash}} />
      {/* Review: flattened page */}
      <AbsoluteFill style={{background: '#EEF1F6', opacity: review, transform: `scale(${1.1 - review * 0.1})`}}>
        <AppBar title="Scan 1" />
        <div style={{position: 'absolute', top: 190, left: 50, right: 50, height: 680, background: 'white', borderRadius: 14, boxShadow: '0 20px 50px rgba(20,30,60,0.2)', padding: 40}}>
          <div style={{width: '50%', height: 18, background: '#2d3446', borderRadius: 6, marginBottom: 30}} />
          <TextLines rows={15} gap={34} thickness={11} seed="rv" color="#AEB5C2" />
        </div>
        <div style={{position: 'absolute', bottom: 120, left: 0, right: 0, display: 'flex', justifyContent: 'center'}}>
          <div style={{display: 'flex', alignItems: 'center', gap: 16, fontFamily: fonts.bangla, fontWeight: 700, fontSize: 36, color: 'white', background: C.navy800, padding: '20px 40px', borderRadius: 40, transform: `scale(${review})`}}>
            <svg width={36} height={36} viewBox="0 0 24 24" fill="none" stroke={C.green} strokeWidth={3} strokeLinecap="round">
              <path d="M5 12.5l4.5 4.5L19 7.5" />
            </svg>
            স্ক্যান সেভ হয়েছে
          </div>
        </div>
      </AbsoluteFill>
    </SceneShell>
  );
};

/** 6. Crop, rotate and filters with a before/after wipe. */
export const EditFeature: React.FC = () => {
  const frame = useCurrentFrame();
  const crop = interpolate(frame, [8, 34], [0, 1], {...clamp, easing: Easing.inOut(Easing.cubic)});
  const rot = interpolate(frame, [38, 56], [-90, 0], {...clamp, easing: Easing.out(Easing.back(1.6))});
  const wipe = interpolate(frame, [62, 100], [0, 1], {...clamp, easing: Easing.inOut(Easing.cubic)});
  const chips = ['Color', 'Gray', 'B&W', 'Enhanced'];
  const active = Math.min(3, Math.floor(interpolate(frame, [60, 104], [0, 3.99], clamp)));
  const inset = 30 + crop * 30;
  const pageStyle = (filter: string): React.CSSProperties => ({
    position: 'absolute',
    inset: 0,
    padding: 44,
    background: '#fff',
    filter,
  });
  const content = (
    <>
      <div style={{width: '55%', height: 20, background: '#222a3a', borderRadius: 6, marginBottom: 30}} />
      <TextLines rows={14} gap={36} thickness={12} seed="ed" color="#4a5263" />
    </>
  );
  return (
    <SceneShell index="০২" title="ক্রপ • রোটেট • ফিল্টার" subtitle="প্রতিটা পাতা হবে পরিষ্কার" glow={C.amber} from={-1}>
      <AbsoluteFill style={{background: '#10172a'}}>
        <AppBar title="Edit page" dark />
        <div style={{position: 'absolute', top: 180, left: 40, right: 40, height: 760, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>
          <div style={{position: 'relative', width: 440, height: 640, transform: `rotate(${rot}deg)`, borderRadius: 8, overflow: 'hidden', boxShadow: '0 20px 60px rgba(0,0,0,0.5)'}}>
            {/* Before: dull, yellow, low contrast photo */}
            <div style={pageStyle('sepia(0.55) contrast(0.6) brightness(0.82) blur(0.6px)')}>{content}</div>
            {/* After: crisp */}
            <div style={{...pageStyle('contrast(1.25) brightness(1.05)'), clipPath: `inset(0 ${100 - wipe * 100}% 0 0)`}}>{content}</div>
            {wipe > 0 && wipe < 1 && <div style={{position: 'absolute', top: 0, bottom: 0, left: `${wipe * 100}%`, width: 6, marginLeft: -3, background: C.amber, boxShadow: `0 0 30px ${C.amber}`}} />}
          </div>
          {/* Crop frame */}
          <div style={{position: 'absolute', inset: `${inset}px ${inset + 10}px`, border: '3px solid white', opacity: interpolate(frame, [4, 10, 40, 50], [0, 1, 1, 0], clamp)}}>
            {[
              [0, 0],
              [1, 0],
              [0, 1],
              [1, 1],
            ].map(([x, y], i) => (
              <div key={i} style={{position: 'absolute', left: x ? undefined : -8, right: x ? -8 : undefined, top: y ? undefined : -8, bottom: y ? -8 : undefined, width: 50, height: 50, borderLeft: x ? undefined : '10px solid white', borderRight: x ? '10px solid white' : undefined, borderTop: y ? undefined : '10px solid white', borderBottom: y ? '10px solid white' : undefined}} />
            ))}
          </div>
        </div>
        {/* Tool row */}
        <div style={{position: 'absolute', bottom: 70, left: 0, right: 0, display: 'flex', justifyContent: 'center', gap: 14}}>
          {chips.map((c, i) => (
            <div
              key={c}
              style={{
                fontFamily: fonts.latin,
                fontWeight: 700,
                fontSize: 26,
                padding: '16px 22px',
                borderRadius: 30,
                color: i === active && frame > 60 ? C.navy950 : 'white',
                background: i === active && frame > 60 ? C.amber : 'rgba(255,255,255,0.1)',
                transform: `scale(${i === active && frame > 60 ? 1.08 : 1})`,
              }}
            >
              {c}
            </div>
          ))}
        </div>
      </AbsoluteFill>
    </SceneShell>
  );
};

const ocrLines = ['চালান নম্বর ৪৮২১', 'Invoice total 1,250.00 BDT', 'তারিখ: ২০ নভেম্বর ২০২৬', 'Thank you for your order', 'মোট টাকা পরিশোধিত'];

/** 7. OCR: beam reads the page, boxes light up, text types into a sheet. */
export const OcrFeature: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const beam = interpolate(frame, [8, 50], [0, 1], {...clamp, easing: Easing.inOut(Easing.sin)});
  const sheet = spring({frame: frame - 54, fps, config: {damping: 15}});
  const fullText = ocrLines.join('\n');
  const typed = Math.floor(interpolate(frame, [58, 90], [0, fullText.length], clamp));
  const toast = spring({frame: frame - 94, fps, config: {damping: 12}});
  const pageTop = 180;
  return (
    <SceneShell index="০৩" title="বাংলা + English লেখা চেনে" subtitle="কপি করুন এক ট্যাপে" glow={C.navy300}>
      <AbsoluteFill style={{background: '#EEF1F6'}}>
        <AppBar title="Page 1" />
        <div style={{position: 'absolute', top: pageTop, left: 40, right: 40, height: 720, background: 'white', borderRadius: 14, boxShadow: '0 20px 50px rgba(20,30,60,0.18)', padding: '50px 40px', display: 'flex', flexDirection: 'column', gap: 46}}>
          {ocrLines.map((l, i) => {
            const lineY = (i + 0.5) / ocrLines.length;
            const hit = beam > lineY * 0.9;
            return (
              <div key={i} style={{position: 'relative', alignSelf: 'flex-start'}}>
                <div style={{fontFamily: fonts.bangla, fontWeight: i === 0 ? 700 : 500, fontSize: i === 0 ? 40 : 34, color: '#262d3d'}}>{l}</div>
                <div
                  style={{
                    position: 'absolute',
                    inset: '-8px -14px',
                    border: `4px solid ${C.amber}`,
                    borderRadius: 10,
                    background: `${C.amber}22`,
                    opacity: hit ? 1 : 0,
                    transform: `scale(${hit ? 1 : 1.2})`,
                  }}
                />
              </div>
            );
          })}
          {/* Beam */}
          <div style={{position: 'absolute', left: 0, right: 0, top: `${beam * 100}%`, height: 8, background: C.amber, boxShadow: `0 0 40px 10px ${C.amber}88`, opacity: beam > 0 && beam < 1 ? 1 : 0}} />
        </div>
        {/* Result sheet */}
        <div style={{position: 'absolute', left: 0, right: 0, bottom: 0, height: 560, background: C.navy900, borderRadius: '44px 44px 0 0', padding: '30px 44px', transform: `translateY(${(1 - sheet) * 600}px)`, boxShadow: '0 -20px 60px rgba(0,0,0,0.35)'}}>
          <div style={{width: 80, height: 8, borderRadius: 8, background: '#3a4766', margin: '0 auto 26px'}} />
          <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 20}}>
            <div style={{fontFamily: fonts.bangla, fontWeight: 600, fontSize: 28, color: C.navy300}}>Recognized as বাংলা + English</div>
            <svg width={44} height={44} viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth={2.2}>
              <rect x={8} y={8} width={12} height={13} rx={2} />
              <path d="M16 8V5a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h2" />
            </svg>
          </div>
          <div style={{fontFamily: fonts.bangla, fontWeight: 500, fontSize: 34, lineHeight: 1.55, color: 'white', whiteSpace: 'pre-wrap'}}>
            {fullText.slice(0, typed)}
            <span style={{opacity: frame % 16 < 8 ? 1 : 0, color: C.amber}}>▍</span>
          </div>
        </div>
        <div style={{position: 'absolute', top: 560, left: 0, right: 0, display: 'flex', justifyContent: 'center'}}>
          <div style={{display: 'flex', alignItems: 'center', gap: 14, fontFamily: fonts.bangla, fontWeight: 700, fontSize: 34, color: 'white', background: C.green, padding: '18px 36px', borderRadius: 40, transform: `translateY(${(1 - toast) * -200}px)`, opacity: toast, boxShadow: `0 20px 50px ${C.green}66`}}>
            ✓ কপি হয়েছে
          </div>
        </div>
      </AbsoluteFill>
    </SceneShell>
  );
};

/** 8. Searchable PDF: pages stack into a PDF, search highlights, share/print. */
export const PdfFeature: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const stack = spring({frame: frame - 4, fps, config: {damping: 14, stiffness: 90}});
  const merge = spring({frame: frame - 36, fps, config: {damping: 13}});
  const query = 'invoice';
  const typed = Math.floor(interpolate(frame, [62, 86], [0, query.length], clamp));
  const found = frame > 90;
  const actions = ['শেয়ার', 'প্রিন্ট', 'সেভ'];
  return (
    <SceneShell index="০৪" title="সার্চেবল PDF" subtitle="শেয়ার বা প্রিন্ট করুন মুহূর্তেই" glow="#ff6b6b" from={-1}>
      <AbsoluteFill style={{background: '#EEF1F6'}}>
        <AppBar title="Invoice.pdf" />
        {/* Search bar */}
        <div style={{position: 'absolute', top: 160, left: 36, right: 36, height: 84, borderRadius: 42, background: 'white', boxShadow: '0 8px 24px rgba(20,30,60,0.1)', display: 'flex', alignItems: 'center', padding: '0 30px', gap: 18, opacity: merge}}>
          <svg width={36} height={36} viewBox="0 0 24 24" fill="none" stroke={C.navy600} strokeWidth={2.6} strokeLinecap="round">
            <circle cx={11} cy={11} r={7} />
            <path d="M20 20l-4-4" />
          </svg>
          <div style={{fontFamily: fonts.latin, fontWeight: 500, fontSize: 34, color: typed ? C.navy900 : '#9aa3b5'}}>
            {typed ? query.slice(0, typed) : 'Search text…'}
            {frame > 60 && frame < 92 && <span style={{color: C.amber}}>|</span>}
          </div>
        </div>
        {/* Pages */}
        <div style={{position: 'absolute', top: 290, left: 0, right: 0, height: 700, display: 'flex', justifyContent: 'center'}}>
          {[2, 1, 0].map((i) => {
            const spreadX = (i - 1) * 260 * (1 - merge);
            const spreadR = (i - 1) * 14 * (1 - merge);
            const stackOff = i * 18 * merge;
            return (
              <div
                key={i}
                style={{
                  position: 'absolute',
                  width: 400,
                  height: 560,
                  background: 'white',
                  borderRadius: 12,
                  padding: 36,
                  boxShadow: '0 20px 50px rgba(20,30,60,0.22)',
                  transform: `translate(${spreadX + stackOff}px, ${(1 - stack) * (900 + i * 200) + stackOff}px) rotate(${spreadR}deg) scale(${0.6 + 0.4 * stack})`,
                }}
              >
                <div style={{width: '50%', height: 16, background: '#2b3243', borderRadius: 6, marginBottom: 26}} />
                <TextLines rows={12} gap={32} thickness={10} seed={`pdf${i}`} />
                {i === 0 && (
                  <div style={{position: 'absolute', left: 36, top: 150, width: 170, height: 34, borderRadius: 6, background: `${C.amber}88`, opacity: found ? 1 : 0, boxShadow: found ? `0 0 30px ${C.amber}` : undefined}} />
                )}
                {i === 0 && (
                  <div
                    style={{
                      position: 'absolute',
                      right: -30,
                      top: -30,
                      fontFamily: fonts.latin,
                      fontWeight: 800,
                      fontSize: 40,
                      color: 'white',
                      background: '#E5484D',
                      padding: '12px 26px',
                      borderRadius: 18,
                      transform: `scale(${merge}) rotate(${(1 - merge) * 40}deg)`,
                      boxShadow: '0 10px 30px rgba(229,72,77,0.5)',
                    }}
                  >
                    PDF
                  </div>
                )}
              </div>
            );
          })}
        </div>
        {/* Actions */}
        <div style={{position: 'absolute', bottom: 80, left: 0, right: 0, display: 'flex', justifyContent: 'center', gap: 22}}>
          {actions.map((a, i) => {
            const s = spring({frame: frame - 100 - i * 6, fps, config: {damping: 10, stiffness: 160}});
            return (
              <div key={a} style={{fontFamily: fonts.bangla, fontWeight: 700, fontSize: 34, color: 'white', background: i === 0 ? C.navy700 : C.navy800, padding: '22px 36px', borderRadius: 30, transform: `scale(${s})`, opacity: s}}>
                {a}
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
    </SceneShell>
  );
};
