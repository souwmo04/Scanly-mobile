import React from 'react';
import {AbsoluteFill, Easing, interpolate, random, useCurrentFrame, useVideoConfig, spring} from 'remotion';
import {Background, clamp, EntryFlash, Kinetic, TextLines, useSpring} from '../components';
import {C, fonts, H, W} from '../theme';

const tileColors = ['#E5484D', '#3E63DD', '#30A46C', '#F76B15', '#8E4EC6', '#12A594', '#D6409F', '#FFC53D', '#0090FF', '#E54666'];
const glyphs = ['PDF', 'SCAN', 'DOC', 'CAM', 'OCR', 'PRO'];

/** 1. "There is no shortage of scanner apps" – a storm of generic app tiles. */
export const Hook: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const tiles = 54;
  const camZ = interpolate(frame, [0, durationInFrames], [0, 900]);
  const exit = interpolate(frame, [durationInFrames - 10, durationInFrames], [1, 0], clamp);
  return (
    <AbsoluteFill>
      <Background />
      <AbsoluteFill style={{perspective: 1000, opacity: exit}}>
        <AbsoluteFill style={{transformStyle: 'preserve-3d', transform: `translateZ(${camZ}px) rotateZ(${frame * 0.08}deg)`}}>
          {new Array(tiles).fill(0).map((_, i) => {
            const angle = random(`a${i}`) * Math.PI * 2;
            const radius = 280 + random(`r${i}`) * 900;
            const z = -2600 + random(`z${i}`) * 2600;
            const delay = random(`d${i}`) * 25;
            const s = spring({frame: frame - delay, fps: 30, config: {damping: 18, stiffness: 60}});
            const size = 150 + random(`s${i}`) * 90;
            const color = tileColors[i % tileColors.length];
            const spin = (random(`sp${i}`) - 0.5) * 50 + frame * (random(`v${i}`) - 0.5) * 1.2;
            return (
              <div
                key={i}
                style={{
                  position: 'absolute',
                  left: W / 2 + Math.cos(angle) * radius - size / 2,
                  top: H / 2 + Math.sin(angle) * radius * 1.3 - size / 2,
                  width: size,
                  height: size,
                  borderRadius: size * 0.24,
                  background: `linear-gradient(145deg, ${color}, ${color}99)`,
                  transform: `translateZ(${z - (1 - s) * 2500}px) rotateY(${spin}deg) rotateX(${spin * 0.6}deg)`,
                  opacity: s,
                  boxShadow: `0 20px 50px rgba(0,0,0,0.5), inset 0 0 0 3px rgba(255,255,255,0.25)`,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontFamily: fonts.latin,
                  fontWeight: 800,
                  fontSize: size * 0.24,
                  color: 'white',
                  letterSpacing: 2,
                }}
              >
                {glyphs[i % glyphs.length]}
              </div>
            );
          })}
        </AbsoluteFill>
      </AbsoluteFill>
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', opacity: exit}}>
        <div style={{padding: '50px 60px', borderRadius: 50, background: 'rgba(10,20,40,0.55)', backdropFilter: 'blur(18px)', boxShadow: '0 30px 80px rgba(0,0,0,0.5)', maxWidth: 960}}>
          <Kinetic text="বাজারে স্ক্যানার অ্যাপের" delay={6} size={86} />
          <Kinetic text="কোনো অভাব নেই" delay={20} size={120} highlight={['অভাব']} />
        </div>
      </AbsoluteFill>
      <EntryFlash duration={14} color="#000" />
    </AbsoluteFill>
  );
};

/** A plain white page with grey text lines. */
const Page: React.FC<{width: number; children?: React.ReactNode; style?: React.CSSProperties}> = ({width, children, style}) => (
  <div
    style={{
      position: 'relative',
      width,
      height: width * 1.36,
      background: 'white',
      borderRadius: 18,
      padding: width * 0.09,
      boxShadow: '0 50px 120px rgba(0,0,0,0.55)',
      overflow: 'hidden',
      ...style,
    }}
  >
    <div style={{width: '55%', height: 22, background: '#3d4658', borderRadius: 8, marginBottom: 40}} />
    <TextLines rows={14} gap={38} thickness={14} seed="pg" />
    {children}
  </div>
);

/** 2. Every page gets their logo; removing it costs money. */
export const Problem: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();
  const stampAt = 62;
  const payAt = 112;
  const priceAt = 160;
  const enter = useSpring(0, {damping: 16});
  const stamp = spring({frame: frame - stampAt, fps, config: {damping: 9, stiffness: 180}});
  const shake = frame >= stampAt && frame < stampAt + 14 ? Math.sin(frame * 3.1) * (14 - (frame - stampAt)) * 2.2 : 0;
  const glitch = frame >= stampAt && frame < stampAt + 6;
  const tile = interpolate(frame, [stampAt + 8, stampAt + 30], [0, 1], clamp);
  const pay = spring({frame: frame - payAt, fps, config: {damping: 14, stiffness: 110}});
  const price = spring({frame: frame - priceAt, fps, config: {damping: 8, stiffness: 200}});
  const pulse = 1 + Math.sin(frame / 4) * 0.03 * (frame > priceAt ? 1 : 0);
  const tint = interpolate(frame, [stampAt, stampAt + 20], [0, 1], clamp);
  const exit = interpolate(frame, [durationInFrames - 8, durationInFrames], [1, 0], clamp);
  const pageY = interpolate(pay, [0, 1], [0, -170]);
  return (
    <AbsoluteFill style={{transform: `translate(${shake}px, ${shake * 0.6}px)`, opacity: exit}}>
      <Background tint={tint} glow={tint > 0.5 ? '#7a1f2b' : C.navy500} />
      <div style={{position: 'absolute', top: 140, left: 0, right: 0}}>
        <Kinetic text="প্রতিটা পাতায় তাদের লোগো" delay={8} size={84} highlight={['লোগো']} highlightColor={C.red} />
      </div>
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', perspective: 1800}}>
        <div
          style={{
            transform: `translateY(${120 + pageY + (1 - enter) * 600}px) rotateX(${12 - enter * 6}deg) rotateY(${-10 + Math.sin(frame / 30) * 6}deg) rotateZ(-3deg)`,
            filter: glitch ? 'drop-shadow(12px 0 0 rgba(255,0,60,0.8)) drop-shadow(-12px 0 0 rgba(0,200,255,0.8))' : undefined,
          }}
        >
          <Page width={660}>
            {/* Tiled small watermarks */}
            <div style={{position: 'absolute', inset: -200, display: 'flex', flexWrap: 'wrap', gap: 50, transform: 'rotate(-30deg)', opacity: tile * 0.25, alignContent: 'center'}}>
              {new Array(40).fill(0).map((_, i) => (
                <div key={i} style={{fontFamily: fonts.latin, fontWeight: 800, fontSize: 40, color: C.red, letterSpacing: 4}}>
                  SCANAPP ©
                </div>
              ))}
            </div>
            {/* Big stamp */}
            {frame >= stampAt && (
              <div
                style={{
                  position: 'absolute',
                  left: '50%',
                  top: '48%',
                  transform: `translate(-50%, -50%) rotate(-24deg) scale(${interpolate(stamp, [0, 1], [3.2, 1])})`,
                  opacity: Math.min(1, stamp * 2) * 0.85,
                  border: `12px solid ${C.red}`,
                  borderRadius: 30,
                  padding: '18px 44px',
                  fontFamily: fonts.latin,
                  fontWeight: 800,
                  fontSize: 120,
                  color: C.red,
                  letterSpacing: 8,
                  whiteSpace: 'nowrap',
                  background: 'rgba(255,255,255,0.6)',
                }}
              >
                LOGO
              </div>
            )}
          </Page>
        </div>
      </AbsoluteFill>
      {/* Paywall card */}
      <AbsoluteFill style={{justifyContent: 'flex-end', alignItems: 'center', paddingBottom: 150}}>
        <div
          style={{
            width: 900,
            borderRadius: 56,
            padding: '50px 56px',
            background: 'linear-gradient(160deg, #2a1220, #160a14)',
            border: `3px solid ${C.red}88`,
            boxShadow: `0 40px 120px rgba(0,0,0,0.7), 0 0 120px ${C.red}44`,
            transform: `translateY(${(1 - pay) * 900}px)`,
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            gap: 22,
          }}
        >
          <div style={{display: 'flex', alignItems: 'center', gap: 26}}>
            <LockIcon size={84} />
            <div style={{fontFamily: fonts.bangla, fontWeight: 700, fontSize: 64, color: 'white'}}>লোগো সরাতে চান?</div>
          </div>
          <div
            style={{
              fontFamily: fonts.bangla,
              fontWeight: 700,
              fontSize: 92,
              color: C.red,
              transform: `scale(${interpolate(price, [0, 1], [2.4, 1]) * pulse})`,
              opacity: Math.min(1, price * 2),
              textShadow: `0 0 50px ${C.red}aa`,
            }}
          >
            ৳৪৯৯ / মাস
          </div>
          <div
            style={{
              fontFamily: fonts.bangla,
              fontWeight: 700,
              fontSize: 46,
              color: 'white',
              background: C.red,
              padding: '20px 70px',
              borderRadius: 100,
              opacity: price,
              transform: `scale(${pulse})`,
            }}
          >
            সাবস্ক্রাইব করুন
          </div>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

const LockIcon: React.FC<{size: number}> = ({size}) => (
  <svg width={size} height={size} viewBox="0 0 24 24">
    <path d="M7 10V7a5 5 0 0 1 10 0v3" fill="none" stroke={C.red} strokeWidth={2.4} strokeLinecap="round" />
    <rect x={4} y={10} width={16} height={11} rx={3} fill={C.red} />
    <circle cx={12} cy={15.5} r={1.8} fill="#160a14" />
  </svg>
);

/** 3. "No more!" – the watermarked page shatters, light builds for the reveal. */
export const Turn: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();
  const no = spring({frame, fps, config: {damping: 7, stiffness: 220}});
  const breakAt = 22;
  const cols = 5;
  const rows = 7;
  const pw = 660;
  const ph = pw * 1.36;
  const t = Math.max(0, frame - breakAt);
  const orb = interpolate(frame, [40, durationInFrames], [0, 1], {...clamp, easing: Easing.in(Easing.cubic)});
  const flash = interpolate(frame, [durationInFrames - 8, durationInFrames], [0, 1], clamp);
  const noOut = interpolate(frame, [34, 46], [1, 0], clamp);
  return (
    <AbsoluteFill>
      <Background tint={interpolate(frame, [0, 40], [1, 0], clamp)} />
      {/* Shards of the old page */}
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', perspective: 1600}}>
        <div style={{position: 'relative', width: pw, height: ph, transform: 'translateY(120px) rotateZ(-3deg)'}}>
          {new Array(cols * rows).fill(0).map((_, i) => {
            const cx = i % cols;
            const cy = Math.floor(i / cols);
            const vx = (cx - cols / 2 + 0.5) * (8 + random(`vx${i}`) * 10);
            const vy = (cy - rows / 2 + 0.5) * (6 + random(`vy${i}`) * 8) - 6;
            const vz = 10 + random(`vz${i}`) * 40;
            const rot = (random(`rt${i}`) - 0.5) * 30;
            return (
              <div
                key={i}
                style={{
                  position: 'absolute',
                  left: (cx * pw) / cols,
                  top: (cy * ph) / rows,
                  width: pw / cols + 1,
                  height: ph / rows + 1,
                  background: (cx + cy) % 3 === 0 ? '#ffe9ea' : 'white',
                  boxShadow: t > 0 ? '0 0 0 1px rgba(0,0,0,0.15)' : undefined,
                  transform: `translate3d(${vx * t}px, ${vy * t + 0.6 * t * t}px, ${vz * t}px) rotateX(${rot * t}deg) rotateY(${rot * 0.7 * t}deg)`,
                  opacity: interpolate(t, [0, 30], [1, 0], clamp),
                }}
              >
                {cy === 3 && cx > 0 && cx < 4 && (
                  <div style={{position: 'absolute', inset: 0, background: `${C.red}55`}} />
                )}
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
      {/* Crack flash */}
      <AbsoluteFill style={{background: 'white', opacity: interpolate(frame, [breakAt, breakAt + 6], [0.7, 0], clamp)}} />
      {/* "আর না!" */}
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', opacity: noOut}}>
        <div
          style={{
            fontFamily: fonts.bangla,
            fontWeight: 700,
            fontSize: 260,
            color: 'white',
            transform: `scale(${interpolate(no, [0, 1], [3, 1])}) rotate(${(1 - no) * -8}deg)`,
            textShadow: `0 0 80px ${C.red}, 0 20px 60px rgba(0,0,0,0.6)`,
          }}
        >
          আর না!
        </div>
      </AbsoluteFill>
      {/* Building light */}
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
        <div
          style={{
            width: 200 + orb * 1600,
            height: 200 + orb * 1600,
            borderRadius: '50%',
            background: `radial-gradient(circle, rgba(255,255,255,${0.9 * orb}) 0%, ${C.amber}${Math.round(orb * 120).toString(16).padStart(2, '0')} 25%, transparent 65%)`,
          }}
        />
      </AbsoluteFill>
      {/* Light rays */}
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', opacity: orb * 0.8}}>
        {new Array(16).fill(0).map((_, i) => (
          <div
            key={i}
            style={{
              position: 'absolute',
              width: 14,
              height: 2400,
              background: `linear-gradient(to bottom, transparent, ${C.amber}aa, transparent)`,
              transform: `rotate(${i * 22.5 + frame * 1.5}deg)`,
            }}
          />
        ))}
      </AbsoluteFill>
      <AbsoluteFill style={{justifyContent: 'flex-end', alignItems: 'center', paddingBottom: 300}}>
        <Kinetic text="তাই নিয়ে এলাম…" delay={38} size={96} stagger={5} style={{maxWidth: 900}} />
      </AbsoluteFill>
      <AbsoluteFill style={{background: 'white', opacity: flash}} />
    </AbsoluteFill>
  );
};
