import {loadFont as loadBangla} from '@remotion/google-fonts/HindSiliguri';
import {loadFont as loadLatin} from '@remotion/google-fonts/Outfit';

const bangla = loadBangla('normal', {weights: ['500', '600', '700'], subsets: ['bengali', 'latin']});
const latin = loadLatin('normal', {weights: ['500', '700', '800'], subsets: ['latin']});

export const fonts = {
  bangla: `${bangla.fontFamily}, ${latin.fontFamily}, sans-serif`,
  latin: `${latin.fontFamily}, ${bangla.fontFamily}, sans-serif`,
};

// Scanly brand palette (lib/core/theme/app_colors.dart).
export const C = {
  navy950: '#0A1428',
  navy900: '#0E1A33',
  navy800: '#162544',
  navy700: '#1F3260',
  navy600: '#2B4580',
  navy500: '#3A5A9B',
  navy300: '#8EA5D6',
  navy200: '#B9C8E8',
  navy100: '#E3E9F5',
  amber: '#F2B53A',
  red: '#E5484D',
  green: '#30C285',
  white: '#FFFFFF',
};

export const W = 1080;
export const H = 1920;
export const FPS = 30;
