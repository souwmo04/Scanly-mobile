import React from 'react';
import {Composition, registerRoot} from 'remotion';
import {Promo, totalFrames} from './Promo';
import {FPS, H, W} from './theme';

const Root: React.FC = () => (
  <Composition id="ScanlyPromo" component={Promo} durationInFrames={totalFrames} fps={FPS} width={W} height={H} />
);

registerRoot(Root);
