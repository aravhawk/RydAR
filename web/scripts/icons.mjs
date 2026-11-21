// Renders the web app manifest's PNG icons from public/logo.svg, so they always match the logo.
import { Resvg } from '@resvg/resvg-js';

// [file under public/icons, pixel size, maskable]
export const ICONS = [
  ['icon-192.png', 192, false],
  ['icon-512.png', 512, false],
  ['icon-maskable-512.png', 512, true],
];

export function renderIcon(logoSVG, size, maskable) {
  // The logo is a rounded tile. A maskable icon is full bleed instead: the launcher draws the shape,
  // and the white dot and the bend sit well inside the safe zone.
  const svg = maskable ? logoSVG.replace('rx="14"', 'rx="0"') : logoSVG;
  if (maskable && svg === logoSVG) throw new Error('public/logo.svg no longer has the rounded tile the maskable icon is made from');
  return new Resvg(svg, { fitTo: { mode: 'width', value: size } }).render().asPng();
}
