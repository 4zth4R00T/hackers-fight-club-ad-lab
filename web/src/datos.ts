import { readFile, writeFile, mkdir, readdir, rename, stat, appendFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { join } from 'node:path';
import { config, expandir, type Idioma } from './config.js';

export interface RetoResuelto {
  Momento: string;
  Puntos: number;
  Primero: boolean;
  Via: string;
  Dia?: number;
}

export interface FichaAlumno {
  Slot: string;
  Sam: string;
  Nombre: string;
  Correo: string;
  Puntos: number;
  Bonos: number;
  Penas: number;
  Fallos: number;
  Resueltas: number;
  DiasCompletos: number[];
  Resueltos: Record<string, RetoResuelto>;
  Copias: unknown[];
  Alertas?: unknown[];
}

export interface Evento {
  Momento: string;
  Tipo: string;
  Alumno: string;
  Texto: string;
}

export interface BaseDatos {
  Actualizado: string | null;
  Alumnos: Record<string, FichaAlumno>;
  PrimerasSangres: Record<string, string>;
  Eventos: Evento[];
}

const VACIA: BaseDatos = { Actualizado: null, Alumnos: {}, PrimerasSangres: {}, Eventos: [] };

async function leerJson<T>(ruta: string): Promise<T> {
  const txt = await readFile(ruta, 'utf8');
  return JSON.parse(txt.charCodeAt(0) === 0xfeff ? txt.slice(1) : txt) as T;
}

function comoLista<T>(v: unknown): T[] {
  if (Array.isArray(v)) return v as T[];
  if (v === null || v === undefined) return [];
  return [v as T];
}

export function texto(v: unknown, idioma: Idioma): string {
  if (v === null || v === undefined) return '';
  if (typeof v === 'string') return expandir(v);
  if (typeof v === 'object') {
    const o = v as Record<string, unknown>;
    const elegido = o[idioma] ?? o['en'] ?? o['es'] ?? '';
    return expandir(String(elegido));
  }
  return expandir(String(v));
}

function normalizar(d: BaseDatos): BaseDatos {
  d.Alumnos = d.Alumnos ?? {};
  d.PrimerasSangres = d.PrimerasSangres ?? {};
  d.Eventos = comoLista<Evento>(d.Eventos);
  for (const ficha of Object.values(d.Alumnos)) {
    ficha.Copias = comoLista(ficha.Copias);
    ficha.Alertas = comoLista(ficha.Alertas);
    ficha.DiasCompletos = comoLista<number>(ficha.DiasCompletos);
    ficha.Resueltos = ficha.Resueltos ?? {};
  }
  return d;
}

let cache: { datos: BaseDatos; hasta: number } | null = null;

export async function leerBase(): Promise<BaseDatos> {
  const ahora = Date.now();
  if (cache && cache.hasta > ahora) return cache.datos;
  try {
    const datos = normalizar(await leerJson<BaseDatos>(config.rutaDb));
    cache = { datos, hasta: ahora + 3000 };
    return datos;
  } catch {
    return cache?.datos ?? VACIA;
  }
}

export function fichaDe(db: BaseDatos, slot: string, sam: string): FichaAlumno | null {
  const a = db.Alumnos[slot];
  if (a) return a;
  const b = db.Alumnos[sam];
  if (b) return b;
  for (const f of Object.values(db.Alumnos)) {
    if (f.Sam && f.Sam.toLowerCase() === sam.toLowerCase()) return f;
  }
  return null;
}

export async function leerProgreso(slot: string, sam: string): Promise<unknown | null> {
  for (const carpeta of [slot, sam]) {
    if (!carpeta || !/^[a-zA-Z0-9._-]{1,64}$/.test(carpeta)) continue;
    try {
      return await leerJson(join(config.rutaHome, carpeta, '.progreso.json'));
    } catch {
      continue;
    }
  }
  return null;
}

export interface RetoPublico {
  id: string;
  dia: number;
  puntos: number;
  opcional: boolean;
  tipo: string;
  titulo: string;
  pistaPublica: string;
}

export interface RetoInstructor extends RetoPublico {
  donde: string;
  pista: string;
}

interface Catalogo {
  Challenges?: unknown;
  Days?: unknown;
}

let cacheCatalogo: { datos: Catalogo; hasta: number } | null = null;

async function catalogo(): Promise<Catalogo> {
  const ahora = Date.now();
  if (cacheCatalogo && cacheCatalogo.hasta > ahora) return cacheCatalogo.datos;
  try {
    const datos = await leerJson<Catalogo>(config.rutaCatalogo);
    cacheCatalogo = { datos, hasta: ahora + 60000 };
    return datos;
  } catch {
    return cacheCatalogo?.datos ?? {};
  }
}

function publico(r: Record<string, unknown>, idioma: Idioma): RetoPublico {
  return {
    id: String(r['Id'] ?? ''),
    dia: Number(r['Day'] ?? 0),
    puntos: Number(r['Points'] ?? 0),
    opcional: Boolean(r['Optional']),
    tipo: String(r['Kind'] ?? ''),
    titulo: texto(r['Title'], idioma),
    pistaPublica: texto(r['PublicHint'], idioma),
  };
}

export async function leerCatalogo(idioma: Idioma): Promise<RetoPublico[]> {
  const c = await catalogo();
  return comoLista<Record<string, unknown>>(c.Challenges)
    .filter((r) => r && r['Id'])
    .map((r) => publico(r, idioma));
}

export async function leerCatalogoInstructor(idioma: Idioma): Promise<RetoInstructor[]> {
  const c = await catalogo();
  return comoLista<Record<string, unknown>>(c.Challenges)
    .filter((r) => r && r['Id'])
    .map((r) => ({ ...publico(r, idioma), donde: texto(r['Where'], idioma), pista: texto(r['Hint'], idioma) }));
}

export interface DiaCurso {
  dia: number;
  titulo: string;
  apertura: Date | null;
}

export async function leerDias(idioma: Idioma): Promise<DiaCurso[]> {
  const c = await catalogo();
  const cal = await leerCalendarioCrudo();
  const mapa = new Map<number, DiaCurso>();
  for (const d of comoLista<Record<string, unknown>>(c.Days)) {
    const n = Number(d['Day'] ?? 0);
    if (n > 0) mapa.set(n, { dia: n, titulo: texto(d['Title'], idioma), apertura: null });
  }
  for (const r of comoLista<Record<string, unknown>>(c.Challenges)) {
    const n = Number(r['Day'] ?? 0);
    if (n > 0 && !mapa.has(n)) mapa.set(n, { dia: n, titulo: '', apertura: null });
  }
  for (const [k, v] of Object.entries(cal)) {
    const n = Number(k);
    if (!(n > 0)) continue;
    const actual = mapa.get(n) ?? { dia: n, titulo: '', apertura: null };
    if (!actual.titulo && v.Titulo) actual.titulo = texto(v.Titulo, idioma);
    if (v.Apertura) {
      const f = new Date(v.Apertura);
      if (!Number.isNaN(f.getTime())) actual.apertura = f;
    }
    mapa.set(n, actual);
  }
  return [...mapa.values()].sort((a, b) => a.dia - b.dia);
}

function escaparRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

export const FORMATO_BANDERA = new RegExp(`^${escaparRegex(config.prefijoBandera)}\\{[\\x20-\\x7E]{1,120}\\}$`);

async function leerCalendarioCrudo(): Promise<Record<string, { Apertura?: string; Titulo?: unknown }>> {
  try {
    const cal = await leerJson<{ Dias?: Record<string, { Apertura?: string; Titulo?: unknown }> }>(
      join(config.rutaContenido, 'calendario.json'));
    return cal.Dias ?? {};
  } catch {
    return {};
  }
}

export async function leerCalendario(): Promise<Record<string, Date>> {
  const salida: Record<string, Date> = {};
  for (const [dia, v] of Object.entries(await leerCalendarioCrudo())) {
    if (v?.Apertura) {
      const f = new Date(v.Apertura);
      if (!Number.isNaN(f.getTime())) salida[dia] = f;
    }
  }
  return salida;
}

export interface Ruta {
  Intro?: unknown;
  Before?: {
    Text?: unknown;
    Cards?: Array<{ Command?: string; Text?: unknown }>;
    Rules?: Array<{ Term?: unknown; Tone?: string; Text?: unknown }>;
    Stuck?: unknown;
  };
  Days?: Array<{
    Day?: number;
    Lede?: unknown;
    Start?: unknown;
    Pitfall?: unknown;
    Vocab?: unknown;
    Tips?: Record<string, unknown>;
  }>;
  Writeups?: {
    Title?: unknown;
    Text?: unknown;
    Steps?: Array<{ Label?: unknown; Text?: unknown }>;
    Tip?: unknown;
  };
}

export async function leerRuta(): Promise<Ruta> {
  for (const r of [join(config.rutaContenido, 'ruta.json'), join(config.rutaWeb, 'content', 'ruta.json')]) {
    try {
      return await leerJson<Ruta>(r);
    } catch {
      continue;
    }
  }
  return {};
}

export async function guardarComentario(textoLibre: string, animo: string, tema: string): Promise<void> {
  await mkdir(config.rutaContenido, { recursive: true });
  const ahora = new Date();
  ahora.setMinutes(0, 0, 0);
  const registro = {
    Momento: ahora.toISOString(),
    Animo: animo.slice(0, 20),
    Tema: tema.slice(0, 60),
    Texto: textoLibre.slice(0, 2000),
  };
  await appendFile(join(config.rutaContenido, 'comentarios.jsonl'), JSON.stringify(registro) + '\n', 'utf8');
}

export async function guardarPregunta(
  identidad: { sam: string; nombre: string } | null,
  reto: string,
  textoLibre: string,
): Promise<void> {
  await mkdir(config.rutaContenido, { recursive: true });
  const registro = {
    Id: randomUUID().slice(0, 8),
    Momento: new Date().toISOString(),
    Reto: reto.slice(0, 12),
    Texto: textoLibre.slice(0, 2000),
    Usuario: identidad ? identidad.sam : null,
    Nombre: identidad ? identidad.nombre : null,
    Respondida: false,
  };
  await appendFile(join(config.rutaContenido, 'preguntas.jsonl'), JSON.stringify(registro) + '\n', 'utf8');
}

export async function entregarBandera(
  identidad: { sam: string; slot: string },
  bandera: string,
  comentario: string,
  origen: string,
): Promise<void> {
  await mkdir(config.rutaDropWeb, { recursive: true });
  const registro = {
    Bandera: bandera.trim(),
    Usuario: identidad.sam,
    Slot: identidad.slot,
    Equipo: `web:${origen}`,
    Momento: new Date().toISOString(),
    Comentario: comentario.slice(0, 500),
    Via: 'web',
    Autenticado: true,
  };
  const sello = new Date().toISOString().replace(/[-:.TZ]/g, '').slice(0, 17);
  const nombre = `${sello}_${identidad.sam}_${randomUUID().slice(0, 8)}.json`;
  await writeFile(join(config.rutaDropWeb, nombre), JSON.stringify(registro, null, 2), 'utf8');
}

export async function reiniciarRegistros(): Promise<string[]> {
  const hechos: string[] = [];
  let lista: string[] = [];
  try {
    lista = await readdir(config.rutaLogs);
  } catch {
    return hechos;
  }
  for (const f of lista) {
    if (!f.toLowerCase().endsWith('.log')) continue;
    if (f.toLowerCase() === 'setup.log') continue;
    try {
      await writeFile(join(config.rutaLogs, f), '', 'utf8');
      hechos.push(f);
    } catch {
      continue;
    }
  }
  return hechos;
}

export interface DatosMonitor {
  Generado?: string;
  Sesiones?: Array<{ Usuario: string; Tipo: string; Origen: string; Cuando: string }>;
  Tickets?: Array<{ Usuario: string; Clase: string; Que: string; Cuando: string }>;
  Shares?: Array<{ Usuario: string; Recurso: string; Fichero: string; Cuando: string }>;
  Fallos?: Array<{ Usuario: string; Desde: string; Motivo: string; Cuando: string }>;
  Equipos?: Array<{ Nombre: string; Visto: string }>;
}

export async function leerMonitor(): Promise<DatosMonitor> {
  try {
    const d = await leerJson<DatosMonitor>(join(config.rutaScore, 'monitor.json'));
    d.Sesiones = comoLista(d.Sesiones);
    d.Tickets = comoLista(d.Tickets);
    d.Shares = comoLista(d.Shares);
    d.Fallos = comoLista(d.Fallos);
    d.Equipos = comoLista(d.Equipos);
    return d;
  } catch {
    return {};
  }
}

export interface FichaPadron {
  Slot: string;
  Usuario: string;
  Nombre: string;
  Correo: string;
  Modalidad: string;
  Activa?: boolean;
}

export interface SesionClase {
  Id: string;
  Titulo: string;
  Fecha: string;
}

export type Marca = 'presente' | 'remoto' | 'tarde' | 'ausente' | 'justificado';

export const MARCAS: ReadonlyArray<{ id: Marca; clase: string }> = [
  { id: 'presente', clase: 'peer-checked:bg-neon peer-checked:text-noche peer-checked:font-medium' },
  { id: 'remoto', clase: 'peer-checked:bg-cian/20 peer-checked:text-cian peer-checked:font-medium' },
  { id: 'tarde', clase: 'peer-checked:bg-ambar/20 peer-checked:text-ambar peer-checked:font-medium' },
  { id: 'justificado', clase: 'peer-checked:bg-violeta/20 peer-checked:text-violeta peer-checked:font-medium' },
  { id: 'ausente', clase: 'peer-checked:bg-rosa/20 peer-checked:text-rosa peer-checked:font-medium' },
];

export interface Asistencia {
  Sesiones: SesionClase[];
  Registro: Record<string, Record<string, Marca>>;
  Actualizado?: string;
}

function clasesPorDefecto(n: number): SesionClase[] {
  return Array.from({ length: Math.max(1, n) }, (_, i) => ({ Id: `clase${i + 1}`, Titulo: '', Fecha: '' }));
}

export async function leerPadron(): Promise<FichaPadron[]> {
  try {
    const d = await leerJson<FichaPadron[] | FichaPadron>(join(config.rutaScore, 'padron.json'));
    return comoLista<FichaPadron>(d);
  } catch {
    return [];
  }
}

export async function leerAsistencia(dias = 7): Promise<Asistencia> {
  try {
    const d = await leerJson<Asistencia>(join(config.rutaScore, 'asistencia.json'));
    return {
      Sesiones: Array.isArray(d.Sesiones) && d.Sesiones.length ? d.Sesiones : clasesPorDefecto(dias),
      Registro: d.Registro ?? {},
      ...(d.Actualizado !== undefined ? { Actualizado: d.Actualizado } : {}),
    };
  } catch {
    return { Sesiones: clasesPorDefecto(dias), Registro: {} };
  }
}

export async function guardarAsistencia(clase: string, marcas: Record<string, Marca>): Promise<void> {
  const actual = await leerAsistencia();
  actual.Registro[clase] = marcas;
  actual.Actualizado = new Date().toISOString();
  await mkdir(config.rutaScore, { recursive: true });
  const destino = join(config.rutaScore, 'asistencia.json');
  const temporal = `${destino}.tmp`;
  await writeFile(temporal, JSON.stringify(actual, null, 2), 'utf8');
  await rename(temporal, destino);
}

export async function listarLogs(): Promise<Array<{ nombre: string; kb: number }>> {
  try {
    const fs = await readdir(config.rutaLogs);
    const salida: Array<{ nombre: string; kb: number }> = [];
    for (const f of fs) {
      if (!f.endsWith('.log')) continue;
      const s = await stat(join(config.rutaLogs, f));
      salida.push({ nombre: f, kb: Math.round(s.size / 1024) });
    }
    return salida.sort((a, b) => b.kb - a.kb);
  } catch {
    return [];
  }
}
