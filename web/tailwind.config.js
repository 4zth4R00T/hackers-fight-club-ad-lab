export default {
  content: ['./src/**/*.{ts,html}', './astro/**/*.{astro,ts,html}', './public/app.js'],
  theme: {
    extend: {
      colors: {
        noche: '#030504',
        lienzo: '#060505',
        panel: '#0b1712',
        hondo: '#040807',
        barra: '#050908',
        tinta: '#c9d6d2',
        tenue: '#7a9a90',
        mudo: '#466a5f',
        borde: '#295e49',
        realce: '#12291f',
        jade: {
          DEFAULT: '#47836b',
          hondo: '#295e49',
          claro: '#6fb597',
        },
        neon: '#00ffa3',
        cian: '#00e5ff',
        rosa: '#ff2e63',
        ambar: '#d9c27a',
        violeta: '#9d8cff',
      },
      fontFamily: {
        mono: ['"IBM Plex Mono"', 'Consolas', '"DejaVu Sans Mono"', 'monospace'],
        serif: ['"Cormorant Garamond"', 'Georgia', '"Times New Roman"', 'serif'],
      },
      fontSize: {
        dato: ['0.9375rem', { lineHeight: '1.55rem' }],
        cifra: ['1.75rem', { lineHeight: '2rem', fontWeight: '500' }],
      },
      letterSpacing: {
        amplio: '0.32em',
        marca: '0.5em',
      },
      maxWidth: {
        panel: '1680px',
        ancho: '2200px',
      },
    },
  },
  plugins: [],
};
