import type { Idioma } from './config.js';
import { textos } from './i18n.js';
import { AUTOR, GITHUB, GITHUB_TXT, INSTAGRAM, INSTAGRAM_TXT, MARCA_NOMBRE, logoPara } from './marca.js';

function escapar(s: string): string {
  return s.replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!
  ));
}

interface DatosError {
  codigo: number;
  titulo: string;
  texto: string;
  idioma: Idioma;
}

export function paginaError(e: DatosError): string {
  const t = textos(e.idioma);
  return `<!doctype html>
<html lang="${e.idioma}" class="h-full">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="dark">
<meta name="robots" content="noindex, nofollow">
<title>${escapar(String(e.codigo))} · ${escapar(MARCA_NOMBRE)}</title>
<link rel="stylesheet" href="/app.css">
<script src="/app.js" defer></script>
<link rel="icon" type="image/png" sizes="32x32" href="/img/hfc-logo-32.png">
</head>
<body class="min-h-full flex flex-col">
  <canvas class="constelacion" data-constelacion aria-hidden="true"></canvas>
  <main class="relative z-10 flex-1 flex items-center justify-center px-4 sm:px-6 py-16">
    <div class="w-full max-w-xl text-center">
      <div class="flex justify-center mb-8"><img class="logo-club" src="${logoPara(132)}" width="132" height="132" alt="${escapar(MARCA_NOMBRE)}"></div>
      <p class="ceja mb-4">${escapar(MARCA_NOMBRE)} · ${escapar(String(e.codigo))}</p>
      <div class="font-serif font-light text-tinta leading-none mb-6 tracking-amplio" style="font-size:clamp(4rem,16vw,7.5rem)">${escapar(String(e.codigo))}</div>
      <h1 class="font-serif text-2xl sm:text-3xl text-tinta mb-4">${escapar(e.titulo)}</h1>
      <p class="text-tenue text-dato leading-relaxed mb-10">${escapar(e.texto)}</p>
      <a href="/" class="boton">${escapar(t.error.volver)}</a>
    </div>
  </main>
  <footer class="pie relative z-10">
    <span>${escapar(t.marca.pie)}</span>
    <a href="${INSTAGRAM}" rel="noopener noreferrer" target="_blank">Instagram ${INSTAGRAM_TXT}</a>
    <a href="${GITHUB}" rel="noopener noreferrer" target="_blank">${GITHUB_TXT}</a>
    <span class="sr-only">${escapar(AUTOR)}</span>
  </footer>
</body>
</html>`;
}

export const ERR_500 = (i: Idioma): string => paginaError({ codigo: 500, titulo: textos(i).error.e500t, texto: textos(i).error.e500x, idioma: i });
export const ERR_403 = (i: Idioma): string => paginaError({ codigo: 403, titulo: textos(i).error.e403t, texto: textos(i).error.e403x, idioma: i });
export const ERR_404 = (i: Idioma): string => paginaError({ codigo: 404, titulo: textos(i).error.e404t, texto: textos(i).error.e404x, idioma: i });
