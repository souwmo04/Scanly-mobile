import React from 'react';
import {AbsoluteFill, Easing, interpolate, random, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {Background, clamp, Kinetic, ScanlyIcon, Shine} from '../components';
import {C, fonts} from '../theme';

/** 4. Logo reveal: brackets fly in, page pops, scan line sweeps, shockwave. */
export const Reveal: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();
  const flash = interpolate(frame, [0, 14], [1, 0], clamp);
  const bracket = spring({frame: frame - 2, fps, config: {damping: 12, stiffness: 110}});
  const page = spring({frame: frame - 10, fps, config: {damping: 9, stiffness: 160}});
  const line = interpolate(frame, [16, 30], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  const lineY = interpolate(frame, [30, 52, 74], [0, -170, 0], {...clamp, easing: Easing.inOut(Easing.sin)});
  const bg = spring({frame, fps, config: {damping: 15, stiffness: 90}});
  const iconUp = spring({frame: frame - 48, fps, config: {damping: 16, stiffness: 90}});
  const iconY = interpolate(iconUp, [0, 1], [0, -260]);
  const iconScale = interpolate(iconUp, [0, 1], [1, 0.72]);
  const wave = interpolate(frame, [10, 50], [0, 1], {...clamp, easing: Easing.out(Easing.quad)});
  const letters = 'Scanly'.split('');
  const shine = interpolate(frame, [80, 115], [0, 1], clamp);
  const exit = interpolate(frame, [durationInFrames - 8, durationInFrames], [1, 0], clamp);
  return (
    <AbsoluteFill style={{opacity: exit}}>
      <Background glow={C.amber} />
      {/* Rotating rays */}
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', opacity: 0.35}}>
        {new Array(12).fill(0).map((_, i) => (
          <div
            key={i}
            style={{
              position: 'absolute',
              width: 180,
              height: 2600,
              background: `linear-gradient(to bottom, transparent, ${C.navy300}33, transparent)`,
              transform: `translateY(${iconY}px) rotate(${i * 30 + frame * 0.4}deg)`,
              clipPath: 'polygon(45% 0, 55% 0, 100% 50%, 55% 100%, 45% 100%, 0 50%)',
            }}
          />
        ))}
      </AbsoluteFill>
      {/* Shockwave rings */}
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
        {[0, 8].map((d) => {
          const w = interpolate(frame, [10 + d, 50 + d], [0, 1], {...clamp, easing: Easing.out(Easing.quad)});
          return (
            <div
              key={d}
              style={{
                position: 'absolute',
                width: 300 + w * 1700,
                height: 300 + w * 1700,
                borderRadius: '50%',
                border: `${10 * (1 - w)}px solid ${C.amber}`,
                opacity: 1 - w,
                transform: `translateY(${iconY}px)`,
              }}
            />
          );
        })}
      </AbsoluteFill>
      {/* Burst particles */}
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
        {new Array(60).fill(0).map((_, i) => {
          const a = random(`ba${i}`) * Math.PI * 2;
          const dist = (300 + random(`bd${i}`) * 700) * wave;
          const size = 6 + random(`bs${i}`) * 12;
          return (
            <div
              key={i}
              style={{
                position: 'absolute',
                width: size,
                height: size,
                borderRadius: '50%',
                background: i % 3 === 0 ? C.amber : C.navy100,
                boxShadow: `0 0 20px ${i % 3 === 0 ? C.amber : C.navy200}`,
                transform: `translate(${Math.cos(a) * dist}px, ${Math.sin(a) * dist + iconY}px)`,
                opacity: 1 - wave * 0.9,
              }}
            />
          );
        })}
      </AbsoluteFill>
      {/* Icon */}
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
        <div style={{transform: `translateY(${iconY}px) scale(${iconScale})`, filter: `drop-shadow(0 0 ${60 + Math.sin(frame / 8) * 20}px ${C.amber}88)`}}>
          <div style={{transform: `scale(${0.6 + bg * 0.4}) rotate(${(1 - bg) * -20}deg)`}}>
            <ScanlyIcon size={520} bracket={bracket} page={page} line={line} lineY={lineY} />
          </div>
        </div>
      </AbsoluteFill>
      {/* Wordmark */}
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
        <div style={{position: 'relative', transform: 'translateY(170px)', display: 'flex', overflow: 'hidden', padding: '0 20px'}}>
          {letters.map((l, i) => {
            const s = spring({frame: frame - 54 - i * 3, fps, config: {damping: 12, stiffness: 150}});
            return (
              <span
                key={i}
                style={{
                  display: 'inline-block',
                  fontFamily: fonts.latin,
                  fontWeight: 800,
                  fontSize: 230,
                  letterSpacing: -4,
                  color: 'white',
                  transform: `translateY(${(1 - s) * 260}px) rotate(${(1 - s) * 18}deg)`,
                  opacity: s,
                  textShadow: '0 20px 60px rgba(0,0,0,0.5)',
                }}
              >
                {l}
              </span>
            );
          })}
          <Shine progress={shine} width={26} opacity={0.9} />
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
        <div style={{transform: 'translateY(380px)', display: 'flex', gap: 24}}>
          {['একদম ফ্রি', 'স্মার্ট স্ক্যানার'].map((chip, i) => {
            const s = spring({frame: frame - 78 - i * 8, fps, config: {damping: 13}});
            return (
              <div
                key={chip}
                style={{
                  fontFamily: fonts.bangla,
                  fontWeight: 700,
                  fontSize: 56,
                  color: i === 0 ? C.navy950 : 'white',
                  background: i === 0 ? C.amber : 'rgba(255,255,255,0.08)',
                  border: i === 0 ? 'none' : `3px solid ${C.navy300}66`,
                  padding: '16px 46px',
                  borderRadius: 100,
                  transform: `scale(${s}) translateY(${(1 - s) * 60}px)`,
                  opacity: s,
                  boxShadow: i === 0 ? `0 0 60px ${C.amber}66` : undefined,
                }}
              >
                {chip}
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{background: 'white', opacity: flash}} />
    </AbsoluteFill>
  );
};

/** 9. No logo, no ads, no subscription; offline and private. */
export const PromiseScene: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();
  const items = ['লোগো', 'বিজ্ঞাপন', 'সাবস্ক্রিপশন'];
  const collapseAt = 128;
  const collapse = spring({frame: frame - collapseAt, fps, config: {damping: 16}});
  const exit = interpolate(frame, [durationInFrames - 8, durationInFrames], [1, 0], clamp);
  const free = spring({frame: frame - collapseAt - 4, fps, config: {damping: 9, stiffness: 160}});
  return (
    <AbsoluteFill style={{opacity: exit}}>
      <Background glow={C.green} />
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', flexDirection: 'column', gap: 50}}>
        {items.map((item, i) => {
          const at = 6 + i * 26;
          const s = spring({frame: frame - at, fps, config: {damping: 13, stiffness: 130}});
          const strike = interpolate(frame, [at + 10, at + 20], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
          const stamp = spring({frame: frame - at - 16, fps, config: {damping: 8, stiffness: 220}});
          return (
            <div
              key={item}
              style={{
                position: 'relative',
                width: 900,
                height: 190,
                borderRadius: 40,
                background: 'rgba(255,255,255,0.06)',
                border: '2px solid rgba(255,255,255,0.12)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                padding: '0 60px',
                transform: `translateX(${(1 - s) * (i % 2 ? 1200 : -1200)}px) translateY(${collapse * -(i - 1) * 240 - collapse * 300}px) scale(${1 - collapse * 0.6})`,
                opacity: 1 - collapse,
              }}
            >
              <div style={{position: 'relative', fontFamily: fonts.bangla, fontWeight: 700, fontSize: 96, color: 'white'}}>
                {item}
                <div style={{position: 'absolute', left: -10, top: '52%', height: 12, width: `${strike * 105}%`, background: C.red, borderRadius: 10, boxShadow: `0 0 30px ${C.red}`}} />
              </div>
              <div
                style={{
                  fontFamily: fonts.bangla,
                  fontWeight: 700,
                  fontSize: 70,
                  color: C.green,
                  border: `6px solid ${C.green}`,
                  borderRadius: 24,
                  padding: '0 28px',
                  transform: `rotate(-8deg) scale(${interpolate(stamp, [0, 1], [2.5, 1])})`,
                  opacity: Math.min(1, stamp * 2),
                }}
              >
                নেই
              </div>
            </div>
          );
        })}
      </AbsoluteFill>
      {/* 100% free */}
      <AbsoluteFill style={{alignItems: 'center', paddingTop: 300}}>
        <div
          style={{
            fontFamily: fonts.bangla,
            fontWeight: 700,
            fontSize: 210,
            color: C.amber,
            transform: `scale(${interpolate(free, [0, 1], [0.2, 1])})`,
            opacity: Math.min(1, free * 1.5),
            textShadow: `0 0 90px ${C.amber}99`,
          }}
        >
          ১০০% ফ্রি
        </div>
        <Confetti start={collapseAt + 4} />
      </AbsoluteFill>
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', flexDirection: 'column', gap: 44, paddingTop: 260}}>
        <Badge at={collapseAt + 20} icon={<WifiOff />} text="ইন্টারনেট ছাড়াই চলে" />
        <Badge at={collapseAt + 62} icon={<Shield />} text="ডকুমেন্ট থাকে শুধু আপনার ফোনে" />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

const Badge: React.FC<{at: number; icon: React.ReactNode; text: string}> = ({at, icon, text}) => {
  const frame = useCurrentFrame();
  const s = spring({frame: frame - at, fps: 30, config: {damping: 13, stiffness: 120}});
  const shine = interpolate(frame, [at + 10, at + 40], [0, 1], clamp);
  return (
    <div
      style={{
        position: 'relative',
        overflow: 'hidden',
        width: 920,
        display: 'flex',
        alignItems: 'center',
        gap: 36,
        padding: '40px 50px',
        borderRadius: 44,
        background: `linear-gradient(135deg, ${C.navy700}, ${C.navy800})`,
        border: `2px solid ${C.navy500}`,
        boxShadow: '0 30px 80px rgba(0,0,0,0.45)',
        transform: `translateY(${(1 - s) * 300}px) scale(${0.8 + s * 0.2})`,
        opacity: s,
      }}
    >
      <div style={{width: 110, height: 110, borderRadius: 30, background: `${C.green}22`, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>{icon}</div>
      <div style={{fontFamily: fonts.bangla, fontWeight: 700, fontSize: 58, color: 'white', flex: 1}}>{text}</div>
      <Shine progress={shine} />
    </div>
  );
};

const WifiOff = () => (
  <svg width={70} height={70} viewBox="0 0 24 24" fill="none" stroke={C.green} strokeWidth={2.2} strokeLinecap="round">
    <path d="M2 8.8a15 15 0 0 1 4.2-2.6M9.4 5.2A15 15 0 0 1 22 8.8M5 12.6a10 10 0 0 1 5.2-2.6M16.3 11a10 10 0 0 1 2.7 1.6M8.5 16.1a5 5 0 0 1 7 0" />
    <circle cx={12} cy={19.5} r={1} fill={C.green} />
    <path d="M3 3l18 18" />
  </svg>
);

const Shield = () => (
  <svg width={70} height={70} viewBox="0 0 24 24" fill="none" stroke={C.green} strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round">
    <path d="M12 2.5l8 3v6c0 5-3.4 8.7-8 10-4.6-1.3-8-5-8-10v-6z" />
    <path d="M8.5 12l2.5 2.5 4.5-5" />
  </svg>
);

export const Confetti: React.FC<{start: number; count?: number}> = ({start, count = 70}) => {
  const frame = useCurrentFrame();
  const t = Math.max(0, frame - start) / 30;
  if (frame < start) return null;
  const colors = [C.amber, C.green, C.navy200, '#ff7eb6', '#7cc4ff'];
  return (
    <AbsoluteFill style={{pointerEvents: 'none'}}>
      {new Array(count).fill(0).map((_, i) => {
        const a = -Math.PI / 2 + (random(`ca${i}`) - 0.5) * 2.6;
        const v = 900 + random(`cv${i}`) * 1100;
        const x = 540 + Math.cos(a) * v * t;
        const y = 420 + Math.sin(a) * v * t + 1400 * t * t;
        const rot = random(`cr${i}`) * 720 * t;
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: x,
              top: y,
              width: 18,
              height: 30,
              background: colors[i % colors.length],
              borderRadius: 4,
              transform: `rotate(${rot}deg) rotateX(${rot * 2}deg)`,
              opacity: interpolate(t, [0, 1.6, 2.2], [1, 1, 0], clamp),
            }}
          />
        );
      })}
    </AbsoluteFill>
  );
};

/** 10. Call to action. */
export const Cta: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const icon = spring({frame, fps, config: {damping: 11, stiffness: 120}});
  const btn = spring({frame: frame - 14, fps, config: {damping: 12}});
  const link = spring({frame: frame - 26, fps, config: {damping: 14}});
  const shine = (frame % 60) / 60;
  const float = Math.sin(frame / 15) * 12;
  const flash = interpolate(frame, [0, 12], [0.8, 0], clamp);
  return (
    <AbsoluteFill>
      <Background glow={C.amber} />
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', opacity: 0.4}}>
        {new Array(18).fill(0).map((_, i) => (
          <div
            key={i}
            style={{
              position: 'absolute',
              width: 120,
              height: 2600,
              background: `linear-gradient(to bottom, transparent, ${C.amber}22, transparent)`,
              transform: `translateY(-330px) rotate(${i * 20 - frame * 0.5}deg)`,
              clipPath: 'polygon(45% 0, 55% 0, 100% 50%, 55% 100%, 45% 100%, 0 50%)',
            }}
          />
        ))}
      </AbsoluteFill>
      <AbsoluteFill style={{alignItems: 'center', paddingTop: 300}}>
        <div style={{transform: `translateY(${float}px) scale(${icon}) rotate(${(1 - icon) * 30}deg)`, filter: `drop-shadow(0 0 70px ${C.amber}77)`}}>
          <ScanlyIcon size={380} />
        </div>
        <div style={{fontFamily: fonts.latin, fontWeight: 800, fontSize: 190, color: 'white', marginTop: 30, letterSpacing: -3, opacity: icon, transform: `translateY(${(1 - icon) * 80}px)`}}>
          Scanly
        </div>
        <Kinetic text="ডকুমেন্ট স্ক্যানার — চিরকাল ফ্রি" delay={8} size={56} weight={600} color={C.navy200} stagger={3} />
        <div
          style={{
            position: 'relative',
            overflow: 'hidden',
            marginTop: 80,
            display: 'flex',
            alignItems: 'center',
            gap: 30,
            padding: '38px 80px',
            borderRadius: 100,
            background: `linear-gradient(135deg, ${C.amber}, #ffcf6b)`,
            boxShadow: `0 30px 90px ${C.amber}66`,
            transform: `scale(${btn * (1 + Math.sin(frame / 6) * 0.02)})`,
          }}
        >
          <DownloadIcon />
          <div style={{fontFamily: fonts.bangla, fontWeight: 700, fontSize: 64, color: C.navy950}}>ফ্রি ডাউনলোড করুন</div>
          <Shine progress={shine} width={20} opacity={1} />
        </div>
        <div style={{marginTop: 40, fontFamily: fonts.bangla, fontWeight: 600, fontSize: 46, color: 'white', opacity: link}}>অ্যান্ড্রয়েডের জন্য</div>
        <div
          style={{
            marginTop: 26,
            fontFamily: fonts.latin,
            fontWeight: 700,
            fontSize: 44,
            color: C.navy100,
            padding: '22px 44px',
            borderRadius: 30,
            background: 'rgba(255,255,255,0.07)',
            border: `2px solid ${C.navy500}`,
            opacity: link,
            transform: `translateY(${(1 - link) * 60}px)`,
          }}
        >
          github.com/souwmo04/Scanly-mobile
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{background: 'white', opacity: flash}} />
    </AbsoluteFill>
  );
};

const DownloadIcon = () => (
  <svg width={64} height={64} viewBox="0 0 24 24" fill="none" stroke={C.navy950} strokeWidth={2.6} strokeLinecap="round" strokeLinejoin="round">
    <path d="M12 3v12M7 10l5 5 5-5M4 20h16" />
  </svg>
);
