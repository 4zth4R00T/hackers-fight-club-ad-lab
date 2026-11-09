import express, { type Request, type Response, type NextFunction } from 'express';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import cookieParser from 'cookie-parser';
import { readFileSync, appendFileSync, existsSync, mkdirSync } from 'node:fs';
import { appendFile } from 'node:fs/promises';
import { join } from 'node:path';
import { createServer as crearHttps } from 'node:https';
import { createServer as crearHttp } from 'node:http';

import { config, esIdioma, type Idioma } from './config.js';
import { autenticar } from './directorio.js';
import {
  entregarBandera, reiniciarRegistros, FORMATO_BANDERA,
  leerPadron, guardarAsistencia, MARCAS, type Marca,
  guardarComentario, guardarPregunta,
} from './datos.js';
import { csrfValido, testigoCsrf } from './jwt.js';
import { abrirSesion, cerrarSesion, comoUsuario, leer, secreto } from './sesion.js';
import { ERR_403, ERR_404, ERR_500 } from './error-html.js';
import { comprimir } from './comprimir.js';
import { compilarRedes, dentroDe, esLocal } from './red.js';
import { textos } from './i18n.js';

const entradaAstro = new URL('../dist-astro/server/entry.mjs', import.meta.url).href;
const moduloAstro = await import(entradaAstro);
const astro = moduloAstro.handler as (req: Request, res: Response, next: NextFunction, locals: Record<string, unknown>) => void;

const app = express();
app.set('trust proxy', false);
app.disable('x-powered-by');

const rutaCrt = join(config.rutaCerts, 'web.crt');
const rutaKey = join(config.rutaCerts, 'web.key');
const rutaPfx = join(config.rutaCerts, 'web.pfx');
const rutaClavePfx = join(config.rutaCerts, 'web.pass');
const hayPem = existsSync(rutaCrt) && existsSync(rutaKey);
const hayPfx = existsSync(rutaPfx) && existsSync(rutaClavePfx);
const hayTls = hayPem || hayPfx;
let origenCert = 'none';
try { origenCert = readFileSync(join(config.rutaCerts, 'origin.txt'), 'utf8').trim() || 'none'; } catch { }

try { mkdirSync(config.rutaLogs, { recursive: true }); } catch { }

const COOKIE_IDIOMA = 'lab.lang';
const redes = compilarRedes(config.redesPermitidas);

app.use(helmet({
  contentSecurityPolicy: {
    useDefaults: false,
    directives: {
      defaultSrc: ["'none'"],
      scriptSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      imgSrc: ["'self'", 'data:'],
      fontSrc: ["'self'"],
      formAction: ["'self'"],
      frameAncestors: ["'none'"],
      baseUri: ["'none'"],
      connectSrc: ["'self'"],
      objectSrc: ["'none'"],
    },
  },
  hsts: origenCert === 'tailscale' ? { maxAge: 15552000, includeSubDomains: false } : false,
  crossOriginOpenerPolicy: { policy: 'same-origin' },
  referrerPolicy: { policy: 'no-referrer' },
}));

app.use(express.urlencoded({ extended: false, limit: '32kb' }));
app.use(cookieParser());
app.use(comprimir);

declare global {
  namespace Express {
    interface Request {
      jti?: string;
      identidad?: ReturnType<typeof comoUsuario> | null;
      idioma?: Idioma;
    }
  }
}

app.use((req: Request, _res: Response, next: NextFunction) => {
  const c = (req.cookies as Record<string, unknown> | undefined)?.[COOKIE_IDIOMA];
  req.idioma = esIdioma(c) ? c : config.idioma;
  next();
});

app.use((req: Request, res: Response, next: NextFunction) => {
  const ip = req.socket.remoteAddress ?? '';
  if (esLocal(ip) || dentroDe(ip, redes)) return next();
  res.status(403).type('text/plain').send(textos(req.idioma ?? config.idioma).error.fuera);
});

const RE_AUTOMATA = /bot|crawler|spider|curl|wget|python|httpx|aiohttp|Go-http-client|headless|node-fetch|axios|java|libwww|okhttp|PowerShell|WinHttp/i;
const RE_RECURSO = /\.(?:css|js|map|svg|png|jpe?g|gif|webp|ico|woff2?|ttf|txt)$/i;

app.use((req: Request, _res: Response, next: NextFunction) => {
  if (RE_RECURSO.test(req.path)) return next();
  if (req.path === '/comentarios' && req.method === 'POST') return next();
  const ua = req.get('user-agent') ?? '(no User-Agent)';
  const auto = RE_AUTOMATA.test(ua) ? '  [AUTOMATED]' : '';
  const linea = `${new Date().toISOString()}  ${(req.socket.remoteAddress ?? '').padEnd(18)} `
    + `${req.method.padEnd(4)} ${req.path.padEnd(24)} UA=${ua}${auto}\n`;
  appendFile(join(config.rutaLogs, 'web-access.log'), linea, 'utf8').catch(() => undefined);
  next();
});

app.use(express.static(config.rutaPublic, { maxAge: '1h', index: false, dotfiles: 'deny', redirect: false }));

app.use((req: Request, _res: Response, next: NextFunction) => {
  const d = leer(req);
  req.identidad = d ? comoUsuario(d) : null;
  req.jti = d?.jti;
  next();
});

function idiomaDe(req: Request): Idioma {
  return req.idioma ?? config.idioma;
}

function comprobarTestigo(req: Request, res: Response, next: NextFunction): void {
  const enviado = String((req.body as Record<string, unknown>)?.['_csrf'] ?? '');
  if (!csrfValido(enviado, req.jti ?? '', secreto)) {
    res.redirect('/entrar?e=sesion');
    return;
  }
  next();
}

function exigeSesion(req: Request, res: Response, next: NextFunction): void {
  if (req.identidad) return next();
  res.redirect('/entrar');
}

function exigeInstructor(req: Request, res: Response, next: NextFunction): void {
  if (req.identidad?.esInstructor) return next();
  if (!req.identidad) { res.redirect('/entrar?e=solo-profes'); return; }
  res.status(403).type('html').send(ERR_403(idiomaDe(req)));
}

const limiteEntrar = rateLimit({
  windowMs: 10 * 60_000, limit: 12, standardHeaders: 'draft-7', legacyHeaders: false,
  handler: (_req, res) => res.redirect('/entrar?e=limite'),
});

const limiteEntregar = rateLimit({
  windowMs: 60_000, limit: 20, standardHeaders: 'draft-7', legacyHeaders: false,
  handler: (_req, res) => res.redirect('/entregar?r=limite'),
});

const limiteBuzon = rateLimit({
  windowMs: 10 * 60_000, limit: 10, standardHeaders: 'draft-7', legacyHeaders: false,
  handler: (req, res) => res.redirect(`${req.path}?r=limite`),
});

app.get('/idioma', (req, res) => {
  const l = String(req.query['l'] ?? '');
  const destino = String(req.query['r'] ?? '/');
  const seguro = /^\/(?!\/)[A-Za-z0-9/_?=&.-]*$/.test(destino) ? destino : '/';
  if (esIdioma(l)) {
    res.cookie(COOKIE_IDIOMA, l, { httpOnly: true, sameSite: 'lax', secure: hayTls, maxAge: 365 * 86400_000, path: '/' });
  }
  res.redirect(seguro);
});

app.post('/entrar', limiteEntrar, async (req, res) => {
  const b = req.body as Record<string, unknown>;
  const id = await autenticar(String(b['usuario'] ?? '').trim(), String(b['clave'] ?? ''));
  if (!id) return res.redirect('/entrar?e=malas');
  abrirSesion(res, id, hayTls);
  res.redirect(id.esAlumno ? '/entregar' : '/');
});

app.post('/salir', (req, res) => {
  cerrarSesion(req, res);
  res.redirect('/');
});

app.post('/entregar', exigeSesion, limiteEntregar, comprobarTestigo, async (req, res) => {
  const u = req.identidad!;
  const b = req.body as Record<string, unknown>;
  const bandera = String(b['bandera'] ?? '').trim();
  if (!u.esAlumno) return res.redirect('/entregar?r=noalumno');
  if (!FORMATO_BANDERA.test(bandera)) return res.redirect('/entregar?r=formato');
  try {
    await entregarBandera(u, bandera, String(b['comentario'] ?? '').trim(), req.socket.remoteAddress ?? '?');
    res.redirect('/entregar?r=ok');
  } catch {
    res.redirect('/entregar?r=error');
  }
});

app.post('/comentarios', exigeSesion, limiteBuzon, comprobarTestigo, async (req, res) => {
  const b = req.body as Record<string, unknown>;
  const texto = String(b['texto'] ?? '').trim();
  if (texto.length < 4) return res.redirect('/comentarios?r=corto');
  try {
    await guardarComentario(texto, String(b['animo'] ?? '').trim(), String(b['tema'] ?? '').trim());
    res.redirect('/comentarios?r=ok');
  } catch {
    res.redirect('/comentarios?r=error');
  }
});

app.post('/preguntas', exigeSesion, limiteBuzon, comprobarTestigo, async (req, res) => {
  const b = req.body as Record<string, unknown>;
  const texto = String(b['texto'] ?? '').trim();
  if (texto.length < 4) return res.redirect('/preguntas?r=corto');
  const anonima = String(b['anonima'] ?? '') === 'si';
  const u = req.identidad!;
  try {
    await guardarPregunta(anonima ? null : { sam: u.sam, nombre: u.nombre }, String(b['reto'] ?? '').trim(), texto);
    res.redirect(`/preguntas?r=${anonima ? 'okanon' : 'ok'}`);
  } catch {
    res.redirect('/preguntas?r=error');
  }
});

app.post('/monitor/reiniciar', exigeInstructor, comprobarTestigo, async (_req, res) => {
  await reiniciarRegistros();
  res.redirect('/monitor?r=reiniciado');
});

app.get('/salud', (_req, res) => res.json({ ok: true, tls: hayTls, cert: origenCert, t: new Date().toISOString() }));

app.get(['/monitor', '/alertas', '/asistencia'], exigeInstructor, (_req, _res, next) => next());

app.get('/monitor.json', exigeInstructor, (req, res) => {
  const ruta = join(config.rutaScore, 'monitor.json');
  if (!existsSync(ruta)) { res.json({}); return; }
  res.sendFile(ruta, (err) => { if (err && !res.headersSent) res.status(404).type('html').send(ERR_404(idiomaDe(req))); });
});

app.post('/asistencia', exigeInstructor, comprobarTestigo, async (req, res) => {
  const b = req.body as Record<string, unknown>;
  const clase = String(b['clase'] ?? '').trim();
  if (!/^clase[1-9][0-9]?$/.test(clase)) return res.redirect('/asistencia?r=clase');
  const padron = await leerPadron();
  const marcas: Record<string, Marca> = {};
  for (const p of padron) {
    const v = String(b[`m_${p.Slot}`] ?? '').trim();
    if (MARCAS.some((m) => m.id === v)) marcas[p.Slot] = v as Marca;
  }
  try {
    await guardarAsistencia(clase, marcas);
    res.redirect(`/asistencia?clase=${clase}&r=ok`);
  } catch {
    res.redirect(`/asistencia?clase=${clase}&r=error`);
  }
});

app.use((req: Request, res: Response, next: NextFunction) => {
  astro(req, res, next, {
    usuario: req.identidad ?? null,
    csrf: req.jti ? testigoCsrf(req.jti, secreto) : '',
    idioma: idiomaDe(req),
  });
});

app.use((req: Request, res: Response) => {
  res.status(404).type('html').send(ERR_404(idiomaDe(req)));
});

function anotarFallo(tipo: string, e: unknown): void {
  const detalle = e instanceof Error ? `${e.name}: ${e.message}\n${e.stack ?? ''}` : String(e);
  const linea = `${new Date().toISOString()}  [${tipo}] ${detalle}\n`;
  try { appendFileSync(join(config.rutaLogs, 'web.log'), linea, 'utf8'); } catch { }
  console.error(linea);
}

app.use((err: unknown, req: Request, res: Response, _next: NextFunction) => {
  anotarFallo('ERROR', err);
  if (res.headersSent) return;
  res.status(500).type('html').send(ERR_500(idiomaDe(req)));
});

function opcionesTls(): { cert?: Buffer; key?: Buffer; pfx?: Buffer; passphrase?: string; minVersion: 'TLSv1.2' } {
  if (hayPem) return { cert: readFileSync(rutaCrt), key: readFileSync(rutaKey), minVersion: 'TLSv1.2' };
  return { pfx: readFileSync(rutaPfx), passphrase: readFileSync(rutaClavePfx, 'utf8').trim(), minVersion: 'TLSv1.2' };
}

const servidor = hayTls ? crearHttps(opcionesTls(), app) : crearHttp(app);

servidor.listen(config.port, config.bindHost, () => {
  const esquema = hayTls ? 'https' : 'http';
  const msg = `${new Date().toISOString()}  [OK] Lab web listening on ${esquema}://${config.bindHost}:${config.port} `
    + `(certificate: ${origenCert}, allowed: ${config.redesPermitidas.join(', ') || 'loopback only'})\n`;
  try { appendFileSync(join(config.rutaLogs, 'web.log'), msg, 'utf8'); } catch { }
  console.log(msg.trim());
});

servidor.on('error', (e) => {
  anotarFallo('LISTEN FAILED', e);
  process.exit(1);
});

for (const s of ['SIGTERM', 'SIGINT'] as const) {
  process.on(s, () => servidor.close(() => process.exit(0)));
}

process.on('uncaughtException', (e) => anotarFallo('UNCAUGHT EXCEPTION', e));
process.on('unhandledRejection', (e) => anotarFallo('UNHANDLED REJECTION', e));
