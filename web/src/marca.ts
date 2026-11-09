export const MARCA_NOMBRE = 'Hackers Fight Club';
export const AUTOR = 'Aztharot';
export const INSTAGRAM = 'https://instagram.com/its_aztharot.exe';
export const INSTAGRAM_TXT = '@its_aztharot.exe';
export const GITHUB = 'https://github.com/4zth4R00T';
export const GITHUB_TXT = 'github.com/4zth4R00T';
export const LOGO_TAMANOS = [32, 64, 192, 256, 512] as const;

export function logoPara(px: number): string {
  const necesario = px * 2;
  for (const t of LOGO_TAMANOS) if (t >= necesario) return `/img/hfc-logo-${t}.png`;
  return '/img/hfc-logo.png';
}
