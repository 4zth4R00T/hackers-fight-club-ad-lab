function aEntero(ip: string): number | null {
  const p = ip.split('.');
  if (p.length !== 4) return null;
  let n = 0;
  for (const x of p) {
    if (!/^\d{1,3}$/.test(x)) return null;
    const v = Number(x);
    if (v > 255) return null;
    n = n * 256 + v;
  }
  return n >>> 0;
}

export interface Red {
  readonly base: number;
  readonly mascara: number;
  readonly texto: string;
}

export function parsearRed(cidr: string): Red | null {
  const [dir, pre] = cidr.trim().split('/');
  const base = aEntero(dir ?? '');
  if (base === null) return null;
  const bits = pre === undefined ? 32 : Number(pre);
  if (!Number.isInteger(bits) || bits < 0 || bits > 32) return null;
  const mascara = bits === 0 ? 0 : (0xffffffff << (32 - bits)) >>> 0;
  return { base: (base & mascara) >>> 0, mascara, texto: cidr.trim() };
}

export function normalizarIp(ip: string): string {
  const v = ip.trim();
  if (v.startsWith('::ffff:')) return v.slice(7);
  return v;
}

export function esLocal(ip: string): boolean {
  const v = normalizarIp(ip);
  return v === '127.0.0.1' || v === '::1';
}

export function dentroDe(ip: string, redes: readonly Red[]): boolean {
  const n = aEntero(normalizarIp(ip));
  if (n === null) return false;
  return redes.some((r) => ((n & r.mascara) >>> 0) === r.base);
}

export function compilarRedes(textos: readonly string[]): Red[] {
  const salida: Red[] = [];
  for (const t of textos) {
    const r = parsearRed(t);
    if (r) salida.push(r);
  }
  return salida;
}
