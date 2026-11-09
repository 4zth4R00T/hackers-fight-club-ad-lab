import type { Request, Response, NextFunction } from 'express';
import { createGzip } from 'node:zlib';

const COMPRIMIBLE = /^(?:text\/|application\/(?:json|javascript|xml)|image\/svg)/i;
const MINIMO = 1024;

export function comprimir(req: Request, res: Response, next: NextFunction): void {
  if (req.method === 'HEAD') return next();
  if (!/\bgzip\b/i.test(String(req.headers['accept-encoding'] ?? ''))) return next();

  const escribirOriginal = res.write.bind(res) as (...a: unknown[]) => boolean;
  const terminarOriginal = res.end.bind(res) as (...a: unknown[]) => Response;
  const cabecerasOriginal = res.writeHead.bind(res) as (...a: unknown[]) => Response;

  let gz: ReturnType<typeof createGzip> | false | null = null;

  function decidir(): void {
    if (gz !== null) return;
    if (res.headersSent) { gz = false; return; }
    const tipo = String(res.getHeader('content-type') ?? '');
    const largo = Number(res.getHeader('content-length') ?? Infinity);
    const yaCodificado = Boolean(res.getHeader('content-encoding'));
    const sinCuerpo = res.statusCode === 204 || res.statusCode === 304;
    if (sinCuerpo || yaCodificado || !COMPRIMIBLE.test(tipo) || largo < MINIMO) {
      gz = false;
      return;
    }
    res.removeHeader('content-length');
    res.setHeader('content-encoding', 'gzip');
    res.setHeader('vary', 'Accept-Encoding');
    gz = createGzip({ level: 6 });
    gz.on('data', (trozo: Buffer) => escribirOriginal(trozo));
    gz.on('end', () => terminarOriginal());
    gz.on('error', () => terminarOriginal());
  }

  res.writeHead = function (estado: number, ...resto: unknown[]): Response {
    const mensaje = typeof resto[0] === 'string' ? resto[0] : undefined;
    const cabeceras = resto.find((x) => x !== null && typeof x === 'object');
    if (cabeceras) {
      for (const [k, v] of Object.entries(cabeceras as Record<string, unknown>)) {
        if (v !== undefined) res.setHeader(k, v as string | string[]);
      }
    }
    res.statusCode = estado;
    decidir();
    return mensaje ? cabecerasOriginal(estado, mensaje) : cabecerasOriginal(estado);
  } as typeof res.writeHead;

  res.write = function (trozo: unknown, cod?: unknown, cb?: unknown): boolean {
    decidir();
    if (gz === false) return escribirOriginal(trozo, cod, cb);
    if (trozo) gz!.write(trozo as Buffer | string, cod as BufferEncoding);
    if (typeof cb === 'function') (cb as () => void)();
    return true;
  } as typeof res.write;

  res.end = function (trozo?: unknown, cod?: unknown, cb?: unknown): Response {
    decidir();
    if (gz === false) return terminarOriginal(trozo, cod, cb);
    if (trozo && typeof trozo !== 'function') gz!.write(trozo as Buffer | string, cod as BufferEncoding);
    gz!.end();
    if (typeof cb === 'function') (cb as () => void)();
    return res;
  } as typeof res.end;

  next();
}
