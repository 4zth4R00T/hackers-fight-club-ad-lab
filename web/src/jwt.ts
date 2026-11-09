import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

export interface Reclamaciones {
  readonly sub: string;
  readonly nom: string;
  readonly slot: string;
  readonly cor: string;
  readonly ins: boolean;
  readonly alu: boolean;
  readonly jti: string;
  readonly iat: number;
  readonly exp: number;
  readonly iss: string;
  readonly aud: string;
}

const EMISOR = 'lab';
const PUBLICO = 'lab-web';
const ALGORITMO = 'HS256';
const CABECERA = b64u(Buffer.from(JSON.stringify({ alg: ALGORITMO, typ: 'JWT' })));

function b64u(b: Buffer): string {
  return b.toString('base64url');
}

function firmar(datos: string, secreto: Buffer): string {
  return b64u(createHmac('sha256', secreto).update(datos).digest());
}

function igual(a: string, b: string): boolean {
  const ha = createHmac('sha256', 'cmp').update(a).digest();
  const hb = createHmac('sha256', 'cmp').update(b).digest();
  return timingSafeEqual(ha, hb);
}

export function emitir(
  datos: Omit<Reclamaciones, 'jti' | 'iat' | 'exp' | 'iss' | 'aud'>,
  secreto: Buffer,
  duracionSeg: number,
): { testigo: string; jti: string; exp: number } {
  const ahora = Math.floor(Date.now() / 1000);
  const jti = randomBytes(16).toString('base64url');
  const exp = ahora + duracionSeg;
  const cuerpo: Reclamaciones = { ...datos, jti, iat: ahora, exp, iss: EMISOR, aud: PUBLICO };
  const partes = `${CABECERA}.${b64u(Buffer.from(JSON.stringify(cuerpo)))}`;
  return { testigo: `${partes}.${firmar(partes, secreto)}`, jti, exp };
}

export type Fallo = 'formato' | 'algoritmo' | 'firma' | 'caducado' | 'futuro' | 'emisor' | 'contenido';

export function comprobar(
  testigo: string,
  secreto: Buffer,
): { ok: true; datos: Reclamaciones } | { ok: false; motivo: Fallo } {
  const p = testigo.split('.');
  if (p.length !== 3) return { ok: false, motivo: 'formato' };
  const [cab, cuerpo, firma] = p as [string, string, string];
  if (cab !== CABECERA) return { ok: false, motivo: 'algoritmo' };
  if (!igual(firma, firmar(`${cab}.${cuerpo}`, secreto))) return { ok: false, motivo: 'firma' };

  let d: Reclamaciones;
  try {
    d = JSON.parse(Buffer.from(cuerpo, 'base64url').toString('utf8')) as Reclamaciones;
  } catch {
    return { ok: false, motivo: 'formato' };
  }
  if (typeof d !== 'object' || d === null) return { ok: false, motivo: 'contenido' };
  if (typeof d.sub !== 'string' || !d.sub) return { ok: false, motivo: 'contenido' };
  if (typeof d.jti !== 'string' || !d.jti) return { ok: false, motivo: 'contenido' };
  if (typeof d.ins !== 'boolean' || typeof d.alu !== 'boolean') return { ok: false, motivo: 'contenido' };
  if (d.iss !== EMISOR || d.aud !== PUBLICO) return { ok: false, motivo: 'emisor' };

  const ahora = Math.floor(Date.now() / 1000);
  if (typeof d.exp !== 'number' || d.exp + 60 < ahora) return { ok: false, motivo: 'caducado' };
  if (typeof d.iat !== 'number' || d.iat - 60 > ahora) return { ok: false, motivo: 'futuro' };
  return { ok: true, datos: d };
}

export function testigoCsrf(jti: string, secreto: Buffer): string {
  return b64u(createHmac('sha256', secreto).update(`csrf:${jti}`).digest());
}

export function csrfValido(enviado: string, jti: string, secreto: Buffer): boolean {
  if (!enviado || !jti) return false;
  return igual(enviado, testigoCsrf(jti, secreto));
}
