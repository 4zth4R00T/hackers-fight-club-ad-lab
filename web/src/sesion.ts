import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { join } from 'node:path';
import type { Request, Response } from 'express';

import { config } from './config.js';
import { comprobar, emitir, type Reclamaciones } from './jwt.js';
import type { Identidad } from './directorio.js';

export const COOKIE = 'lab.jwt';
export const DURACION_SEG = 8 * 3600;

function asegurarCarpeta(): void {
  try { mkdirSync(config.rutaDatosWeb, { recursive: true }); } catch { }
}

function secretoFirma(ruta: string): Buffer {
  try {
    const v = readFileSync(ruta, 'utf8').trim();
    if (v.length >= 64) return Buffer.from(v, 'base64url');
  } catch { }
  const nuevo = randomBytes(64);
  asegurarCarpeta();
  try {
    writeFileSync(ruta, nuevo.toString('base64url'), { encoding: 'utf8', mode: 0o600 });
  } catch { }
  return nuevo;
}

export const secreto = secretoFirma(join(config.rutaDatosWeb, '.jwt-secret'));

const RUTA_REVOCADOS = join(config.rutaDatosWeb, '.jwt-revocados.json');
let revocados = new Map<string, number>();

try {
  const crudo = JSON.parse(readFileSync(RUTA_REVOCADOS, 'utf8')) as Record<string, number>;
  revocados = new Map(Object.entries(crudo));
} catch { }

function purgar(): void {
  const ahora = Math.floor(Date.now() / 1000);
  for (const [jti, exp] of revocados) if (exp < ahora) revocados.delete(jti);
}

function guardar(): void {
  purgar();
  asegurarCarpeta();
  try {
    writeFileSync(RUTA_REVOCADOS, JSON.stringify(Object.fromEntries(revocados)), { encoding: 'utf8', mode: 0o600 });
  } catch { }
}

export function revocar(jti: string, exp: number): void {
  revocados.set(jti, exp);
  guardar();
}

export function abrirSesion(res: Response, id: Identidad, seguro: boolean): void {
  const { testigo } = emitir({
    sub: id.sam, nom: id.nombre, slot: id.slot, cor: id.correo, ins: id.esInstructor, alu: id.esAlumno,
  }, secreto, DURACION_SEG);
  res.cookie(COOKIE, testigo, {
    httpOnly: true, sameSite: 'strict', secure: seguro, maxAge: DURACION_SEG * 1000, path: '/',
  });
}

export function cerrarSesion(req: Request, res: Response): void {
  const d = leer(req);
  if (d) revocar(d.jti, d.exp);
  res.clearCookie(COOKIE, { path: '/' });
}

export function leer(req: Request): Reclamaciones | null {
  const crudo = (req.cookies as Record<string, unknown> | undefined)?.[COOKIE];
  if (typeof crudo !== 'string' || !crudo) return null;
  const r = comprobar(crudo, secreto);
  if (!r.ok) return null;
  if (revocados.has(r.datos.jti)) return null;
  return r.datos;
}

export function comoUsuario(d: Reclamaciones): Identidad {
  return { sam: d.sub, nombre: d.nom, correo: d.cor, slot: d.slot, esInstructor: d.ins, esAlumno: d.alu };
}
