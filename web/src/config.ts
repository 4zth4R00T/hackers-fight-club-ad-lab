import { readFileSync } from 'node:fs';
import { join } from 'node:path';

export type Idioma = 'es' | 'en' | 'ru';

export const IDIOMAS: readonly Idioma[] = ['es', 'en', 'ru'];

export function esIdioma(v: unknown): v is Idioma {
  return typeof v === 'string' && (IDIOMAS as readonly string[]).includes(v);
}

export interface Config {
  readonly bindHost: string;
  readonly port: number;
  readonly dominio: string;
  readonly dominioNetBIOS: string;
  readonly idioma: Idioma;
  readonly organizacion: string;
  readonly laboratorio: string;
  readonly prefijoBandera: string;
  readonly ldapUrl: string;
  readonly gruposInstructores: string[];
  readonly redesPermitidas: string[];
  readonly raiz: string;
  readonly rutaWeb: string;
  readonly rutaPublic: string;
  readonly rutaDb: string;
  readonly rutaDropWeb: string;
  readonly rutaHome: string;
  readonly rutaLogs: string;
  readonly rutaScore: string;
  readonly rutaContenido: string;
  readonly rutaDatosWeb: string;
  readonly rutaCerts: string;
  readonly rutaCatalogo: string;
  readonly huellaLdaps: string | null;
  readonly marcadores: Record<string, string>;
}

function argumento(nombre: string): string | undefined {
  const i = process.argv.indexOf(nombre);
  if (i >= 0 && i + 1 < process.argv.length) return process.argv[i + 1];
  return undefined;
}

function lista(v: string): string[] {
  return v.split(/[,;]/).map((x) => x.trim()).filter(Boolean);
}

function huella(ruta: string): string | null {
  try {
    const v = readFileSync(ruta, 'utf8').trim().toUpperCase().replace(/[^0-9A-F]/g, '');
    return v.length === 40 || v.length === 64 ? v : null;
  } catch {
    return null;
  }
}

interface Sitio {
  Settings: Record<string, string>;
  Placeholders: Record<string, string>;
}

function leerSitio(ruta: string): Sitio {
  const vacio: Sitio = { Settings: {}, Placeholders: {} };
  try {
    let txt = readFileSync(ruta, 'utf8');
    if (txt.charCodeAt(0) === 0xfeff) txt = txt.slice(1);
    const j = JSON.parse(txt) as { Settings?: Record<string, unknown>; Placeholders?: Record<string, unknown> };
    for (const [k, v] of Object.entries(j.Settings ?? {})) vacio.Settings[k] = String(v ?? '');
    for (const [k, v] of Object.entries(j.Placeholders ?? {})) vacio.Placeholders[k] = String(v ?? '');
    return vacio;
  } catch {
    return vacio;
  }
}

function raizInicial(): string {
  const a = argumento('--root');
  if (a && a.trim()) return a.trim();
  const e = process.env['LAB_ROOT'];
  if (e && e.trim()) return e.trim();
  return 'C:\\Lab';
}

const raiz = raizInicial();
const sitioActual = leerSitio(join(raiz, 'data', 'web', 'site.json'));

function env(nombre: string, defecto: string): string {
  const v = process.env[nombre];
  if (v !== undefined && v.trim() !== '') return v.trim();
  const s = sitioActual.Settings[nombre];
  if (s !== undefined && s.trim() !== '') return s.trim();
  return defecto;
}

const rutaDatosWeb = join(raiz, 'data', 'web');
const dominio = env('LAB_DOMAIN', 'lab.local').toLowerCase();
const netbios = env('LAB_NETBIOS', dominio.split('.')[0]!.toUpperCase());
const idiomaCrudo = env('LAB_LANG', 'es').toLowerCase();
const idioma: Idioma = idiomaCrudo.startsWith('en') ? 'en' : idiomaCrudo.startsWith('ru') ? 'ru' : 'es';
const organizacion = env('LAB_ORG', 'Lab Corp');
const laboratorio = env('LAB_NAME', 'Hackers Fight Club');
const prefijoBandera = env('LAB_FLAG', 'FLAG');
const rutaWeb = env('LAB_WEB', join(raiz, 'web'));

const marcadores: Record<string, string> = {
  '{ORG}': organizacion,
  '{LAB}': laboratorio,
  '{DOMAIN}': dominio,
  '{NETBIOS}': netbios,
  '{DC}': 'DC01',
  '{DCFQDN}': `dc01.${dominio}`,
  '{FLAG}': prefijoBandera,
  '{KIT_DIR}': 'Lab-Kit',
  '{CMD_CHALLENGES}': 'Get-Challenges',
  '{CMD_HINT}': 'Get-Hint',
  '{CMD_SUBMIT}': 'Submit-Flag',
  '{CMD_PROGRESS}': 'Get-Progress',
  '{CMD_MAIL}': 'Send-LabMail',
  '{OU_SANDBOX}': 'Sandbox',
  '{SHARE_PUBLIC}': 'Publico',
  '{HOME_DRIVE}': 'H:',
  ...sitioActual.Placeholders,
};

export const config: Config = {
  bindHost: env('LAB_BIND', '127.0.0.1'),
  port: Number(env('LAB_PORT', '8443')),
  dominio,
  dominioNetBIOS: netbios,
  idioma,
  organizacion,
  laboratorio,
  prefijoBandera,
  ldapUrl: env('LAB_LDAP', 'ldaps://127.0.0.1:636'),
  gruposInstructores: lista(env('LAB_INSTRUCTORS', 'Lab-Instructores')),
  redesPermitidas: lista(env('LAB_ALLOW', '')),
  raiz,
  rutaWeb,
  rutaPublic: join(rutaWeb, 'public'),
  rutaDb: join(raiz, 'score', 'db.json'),
  rutaDropWeb: join(raiz, 'score', 'drop-web'),
  rutaHome: join(raiz, 'shares', 'home'),
  rutaLogs: join(raiz, 'logs'),
  rutaScore: join(raiz, 'score'),
  rutaContenido: join(raiz, 'content'),
  rutaDatosWeb,
  rutaCerts: join(rutaDatosWeb, 'certs'),
  rutaCatalogo: env('LAB_CATALOG', join(raiz, 'engine', 'challenges.json')),
  huellaLdaps: huella(join(rutaDatosWeb, '.ldaps-thumbprint')),
  marcadores,
};

export function expandir(texto: string): string {
  let t = texto;
  for (const [k, v] of Object.entries(config.marcadores)) t = t.split(k).join(v);
  return t;
}
