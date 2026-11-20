import React from 'react';
import {AbsoluteFill, Audio, Sequence, staticFile} from 'remotion';
import timeline from '../public/vo/timeline.json';
import {Cta, PromiseScene, Reveal} from './scenes/Reveal';
import {EditFeature, OcrFeature, PdfFeature, ScanFeature} from './scenes/Features';
import {Hook, Problem, Turn} from './scenes/Intro';

const scenes: Record<string, React.FC> = {
  hook: Hook,
  problem: Problem,
  turn: Turn,
  reveal: Reveal,
  scan: ScanFeature,
  edit: EditFeature,
  ocr: OcrFeature,
  pdf: PdfFeature,
  promise: PromiseScene,
  cta: Cta,
};

export const totalFrames = timeline.reduce((n, s) => Math.max(n, s.startFrame + s.durationFrames), 0);

export const Promo: React.FC = () => (
  <AbsoluteFill style={{background: '#0A1428'}}>
    {timeline.map((s) => {
      const Scene = scenes[s.id];
      return (
        <Sequence key={s.id} from={s.startFrame} durationInFrames={s.durationFrames} name={s.id}>
          <Scene />
          <Sequence from={s.voiceDelayFrames} layout="none">
            <Audio src={staticFile(s.file)} volume={2} />
          </Sequence>
        </Sequence>
      );
    })}
    <Audio src={staticFile('music.wav')} volume={1} />
  </AbsoluteFill>
);
