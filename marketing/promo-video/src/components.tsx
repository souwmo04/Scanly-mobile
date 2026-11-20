import React from 'react';
import {AbsoluteFill, interpolate, random, spring, useCurrentFrame, useVideoConfig, Easing} from 'remotion';
import {C, fonts, H, W} from './theme';

export const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

export const useSpring = (delay = 0, config: {damping?: number; stiffness?: number; mass?: number} = {}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return spring({frame: frame - delay, fps, config: {damping: 14, stiffness: 120, mass: 0.8, ...config}});
};

/** Moving navy gradient, perspective grid floor and drifting particles. */
export const Background: React.FC<{tint?: number; glow?: string}> = ({tint = 0, glow = C.navy500}) => {
  const frame = useCurrentFrame();
  const a = frame / 90;
  const x1 = 30 + Math.sin(a) * 20;
  const y1 = 25 + Math.cos(a * 0.7) * 12;
  const x2 = 70 + Math.cos(a * 0.8) * 20;
  const y2 = 75 + Math.sin(a * 0.6) * 12;
  const red = `rgba(229,72,77,${0.45 * tint})`;
  return (
    <AbsoluteFill style={{background: C.navy950, overflow: 'hidden'}}>
      <AbsoluteFill
        style={{
          background: `radial-gradient(circle at ${x1}% ${y1}%, ${glow}66 0%, transparent 45%),
            radial-gradient(circle at ${x2}% ${y2}%, ${C.navy600}88 0%, transparent 50%),
            radial-gradient(circle at 50% 50%, ${red} 0%, transparent 70%)`,
        }}
      />
      {/* Perspective grid floor */}
      <div
        style={{
          position: 'absolute',
          left: -W,
          width: W * 3,
          top: H * 0.62,
          height: H,
          transform: 'perspective(700px) rotateX(72deg)',
          transformOrigin: '50% 0%',
          backgroundImage: `linear-gradient(${C.navy300}22 2px, transparent 2px), linear-gradient(90deg, ${C.navy300}22 2px, transparent 2px)`,
          backgroundSize: '120px 120px',
          backgroundPosition: `0px ${(frame * 4) % 120}px`,
          maskImage: 'linear-gradient(to bottom, black 0%, transparent 70%)',
          WebkitMaskImage: 'linear-gradient(to bottom, black 0%, transparent 70%)',
        }}
      />
      <Particles count={46} />
      <AbsoluteFill style={{background: 'radial-gradient(circle at 50% 50%, transparent 55%, rgba(0,0,0,0.55) 100%)'}} />
    </AbsoluteFill>
  );
};

export const Particles: React.FC<{count: number; color?: string}> = ({count, color = C.navy200}) => {
  const frame = useCurrentFrame();
  return (
    <>
      {new Array(count).fill(0).map((_, i) => {
        const speed = 0.4 + random(`s${i}`) * 1.2;
        const x = random(`x${i}`) * W + Math.sin(frame / 40 + i) * 18;
        const y = (random(`y${i}`) * H - frame * speed + H * 4) % H;
        const size = 2 + random(`r${i}`) * 5;
        const op = 0.15 + random(`o${i}`) * 0.5;
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: x,
              top: y,
              width: size,
              height: size,
              borderRadius: '50%',
              background: color,
              opacity: op,
              boxShadow: `0 0 ${size * 3}px ${color}`,
            }}
          />
        );
      })}
    </>
  );
};

/** Words rise in one by one with blur and spring. */
export const Kinetic: React.FC<{
  text: string;
  delay?: number;
  size?: number;
  color?: string;
  weight?: number;
  stagger?: number;
  font?: string;
  highlight?: string[];
  highlightColor?: string;
  style?: React.CSSProperties;
}> = ({text, delay = 0, size = 96, color = C.white, weight = 700, stagger = 4, font = fonts.bangla, highlight = [], highlightColor = C.amber, style}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const words = text.split(' ');
  return (
    <div
      style={{
        display: 'flex',
        flexWrap: 'wrap',
        justifyContent: 'center',
        gap: `0 ${size * 0.28}px`,
        fontFamily: font,
        fontSize: size,
        fontWeight: weight,
        lineHeight: 1.25,
        color,
        textAlign: 'center',
        ...style,
      }}
    >
      {words.map((w, i) => {
        const s = spring({frame: frame - delay - i * stagger, fps, config: {damping: 13, stiffness: 140, mass: 0.7}});
        const hl = highlight.some((h) => w.includes(h));
        return (
          <span
            key={i}
            style={{
              display: 'inline-block',
              transform: `translateY(${(1 - s) * size * 0.8}px) scale(${0.7 + 0.3 * s})`,
              opacity: Math.min(1, s * 1.4),
              filter: `blur(${(1 - Math.min(1, s)) * 12}px)`,
              color: hl ? highlightColor : undefined,
              textShadow: hl ? `0 0 40px ${highlightColor}88` : '0 8px 30px rgba(0,0,0,0.45)',
            }}
          >
            {w}
          </span>
        );
      })}
    </div>
  );
};

/** Scanly app icon drawn as SVG so its parts can animate. */
export const ScanlyIcon: React.FC<{
  size: number;
  bracket?: number; // 0..1 brackets fly in
  page?: number; // 0..1 page scales in
  line?: number; // 0..1 scan line grows
  lineY?: number; // scan line vertical offset in icon units
  bg?: boolean;
}> = ({size, bracket = 1, page = 1, line = 1, lineY = 0, bg = true}) => {
  const off = (1 - bracket) * 500;
  const corner = (dx: number, dy: number, d: string) => (
    <path
      d={d}
      transform={`translate(${dx * off} ${dy * off})`}
      fill="none"
      stroke={C.navy200}
      strokeWidth={56}
      strokeLinecap="round"
      strokeLinejoin="miter"
      opacity={Math.min(1, bracket * 1.5)}
    />
  );
  return (
    <svg width={size} height={size} viewBox="0 0 1024 1024" style={{overflow: 'visible'}}>
      {bg && <rect width={1024} height={1024} rx={230} fill={C.navy800} />}
      {corner(-1, -1, 'M348 205 H205 V348')}
      {corner(1, -1, 'M676 205 H819 V348')}
      {corner(-1, 1, 'M348 819 H205 V676')}
      {corner(1, 1, 'M676 819 H819 V676')}
      <g transform={`translate(512 512) scale(${page}) translate(-512 -512)`}>
        <rect x={348} y={307} width={328} height={410} rx={44} fill={C.white} />
      </g>
      <line
        x1={512 - 261 * line}
        x2={512 + 261 * line}
        y1={512 + lineY}
        y2={512 + lineY}
        stroke={C.amber}
        strokeWidth={52}
        strokeLinecap="round"
        opacity={line > 0.01 ? 1 : 0}
      />
    </svg>
  );
};

/** A phone with rounded bezel; children render as the screen. */
export const Phone: React.FC<{
  width?: number;
  rotateY?: number;
  rotateX?: number;
  scale?: number;
  y?: number;
  children: React.ReactNode;
  glow?: string;
}> = ({width = 600, rotateY = 0, rotateX = 0, scale = 1, y = 0, children, glow = C.navy500}) => {
  const height = width * 2.08;
  return (
    <div style={{perspective: 2200, position: 'absolute', left: 0, right: 0, top: 0, bottom: 0, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>
      <div
        style={{
          width,
          height,
          transform: `translateY(${y}px) rotateY(${rotateY}deg) rotateX(${rotateX}deg) scale(${scale})`,
          transformStyle: 'preserve-3d',
          borderRadius: width * 0.13,
          background: 'linear-gradient(145deg, #2a3550, #0b1222 60%, #1d2740)',
          padding: width * 0.03,
          boxShadow: `0 60px 120px rgba(0,0,0,0.6), 0 0 160px ${glow}55, inset 0 0 0 3px #3b4a6e`,
        }}
      >
        <div style={{position: 'relative', width: '100%', height: '100%', borderRadius: width * 0.105, overflow: 'hidden', background: '#F7F8FB'}}>
          {children}
          {/* Glass reflection */}
          <div
            style={{
              position: 'absolute',
              inset: 0,
              background: `linear-gradient(${115 + rotateY}deg, rgba(255,255,255,0.18) 0%, transparent 30%, transparent 70%, rgba(255,255,255,0.06) 100%)`,
              pointerEvents: 'none',
            }}
          />
          {/* Camera punch hole */}
          <div style={{position: 'absolute', top: width * 0.03, left: '50%', width: width * 0.04, height: width * 0.04, marginLeft: -width * 0.02, borderRadius: '50%', background: '#05080f'}} />
        </div>
      </div>
    </div>
  );
};

/** Lines that look like printed text on a page. */
export const TextLines: React.FC<{rows: number; color?: string; width?: number; gap?: number; seed?: string; thickness?: number}> = ({
  rows,
  color = '#C9CFDA',
  width = 100,
  gap = 26,
  seed = 'p',
  thickness = 10,
}) => (
  <div style={{display: 'flex', flexDirection: 'column', gap: gap - thickness}}>
    {new Array(rows).fill(0).map((_, i) => (
      <div key={i} style={{height: thickness, borderRadius: thickness, background: color, width: `${(i % 5 === 4 ? 45 : 70 + random(`${seed}${i}`) * 30) * (width / 100)}%`}} />
    ))}
  </div>
);

/** A brief white flash + zoom used on scene entry. */
export const EntryFlash: React.FC<{duration?: number; color?: string}> = ({duration = 10, color = '#ffffff'}) => {
  const frame = useCurrentFrame();
  const o = interpolate(frame, [0, duration], [0.55, 0], {...clamp, easing: Easing.out(Easing.quad)});
  return <AbsoluteFill style={{background: color, opacity: o, pointerEvents: 'none'}} />;
};

/** Light streak that sweeps across its parent. */
export const Shine: React.FC<{progress: number; width?: number; opacity?: number}> = ({progress, width = 30, opacity = 0.7}) => (
  <div
    style={{
      position: 'absolute',
      inset: 0,
      background: `linear-gradient(110deg, transparent ${progress * 140 - 40}%, rgba(255,255,255,${opacity}) ${progress * 140 - 40 + width / 2}%, transparent ${progress * 140 - 40 + width}%)`,
      mixBlendMode: 'overlay',
      pointerEvents: 'none',
    }}
  />
);

/** Section heading used by the feature scenes. */
export const FeatureTitle: React.FC<{index: string; title: string; subtitle: string}> = ({index, title, subtitle}) => {
  const frame = useCurrentFrame();
  const s = useSpring(0);
  const bar = interpolate(frame, [4, 22], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  return (
    <div style={{position: 'absolute', top: 150, left: 0, right: 0, display: 'flex', flexDirection: 'column', alignItems: 'center'}}>
      <div
        style={{
          fontFamily: fonts.latin,
          fontWeight: 800,
          fontSize: 34,
          letterSpacing: 10,
          color: C.amber,
          opacity: s,
          transform: `translateY(${(1 - s) * -30}px)`,
          display: 'flex',
          alignItems: 'center',
          gap: 18,
        }}
      >
        <div style={{width: 70 * bar, height: 4, background: C.amber, borderRadius: 4}} />
        {index}
        <div style={{width: 70 * bar, height: 4, background: C.amber, borderRadius: 4}} />
      </div>
      <Kinetic text={title} delay={3} size={92} style={{marginTop: 18, maxWidth: 960}} />
      <Kinetic text={subtitle} delay={10} size={44} weight={500} color={C.navy200} stagger={2} style={{marginTop: 10, maxWidth: 900}} />
    </div>
  );
};
