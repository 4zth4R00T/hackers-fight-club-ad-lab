import { Client } from 'ldapts';
import { config } from './config.js';

export interface Identidad {
  readonly sam: string;
  readonly nombre: string;
  readonly correo: string;
  readonly slot: string;
  readonly esInstructor: boolean;
  readonly esAlumno: boolean;
}

const CUENTA_VALIDA = /^[a-zA-Z0-9._-]{1,64}$/;

function escaparFiltro(v: string): string {
  return v.replace(/[\\*()\u0000]/g, (c) => {
    switch (c) {
      case '\\': return '\\5c';
      case '*': return '\\2a';
      case '(': return '\\28';
      case ')': return '\\29';
      default: return '\\00';
    }
  });
}

function cnDe(dn: string): string {
  const m = /^CN=((?:\\,|[^,])+),/i.exec(dn);
  return m ? m[1]!.replace(/\\,/g, ',').toUpperCase() : '';
}

export async function autenticar(usuario: string, clave: string): Promise<Identidad | null> {
  const sam = usuario.includes('\\') ? usuario.split('\\').pop()! : usuario.split('@')[0]!;
  if (!CUENTA_VALIDA.test(sam)) return null;
  if (!clave) return null;

  const cliente = new Client({
    url: config.ldapUrl,
    timeout: 8000,
    connectTimeout: 8000,
    tlsOptions: {
      rejectUnauthorized: false,
      checkServerIdentity: (_host, cert) => {
        if (!config.huellaLdaps) return undefined;
        const fuente = config.huellaLdaps.length === 64 ? cert.fingerprint256 : cert.fingerprint;
        const visto = String(fuente ?? '').replace(/[^0-9A-Fa-f]/g, '').toUpperCase();
        return visto === config.huellaLdaps ? undefined : new Error('Unexpected directory certificate');
      },
    },
  });

  try {
    await cliente.bind(`${sam}@${config.dominio}`, clave);
    const base = config.dominio.split('.').map((p) => `DC=${p}`).join(',');
    const { searchEntries } = await cliente.search(base, {
      scope: 'sub',
      filter: `(&(objectClass=user)(sAMAccountName=${escaparFiltro(sam)}))`,
      attributes: ['sAMAccountName', 'displayName', 'mail', 'employeeNumber', 'memberOf'],
    });
    const e = searchEntries[0];
    if (!e) return null;

    const grupos = (Array.isArray(e['memberOf']) ? e['memberOf'] : [e['memberOf']])
      .filter(Boolean)
      .map((g) => cnDe(String(g)));
    const instructores = config.gruposInstructores.map((g) => g.toUpperCase());
    const slot = String(e['employeeNumber'] ?? '');
    const cuenta = String(e['sAMAccountName'] ?? sam);

    return {
      sam: cuenta,
      nombre: String(e['displayName'] ?? cuenta),
      correo: String(e['mail'] ?? `${cuenta}@${config.dominio}`),
      slot: slot || cuenta,
      esInstructor: grupos.some((g) => instructores.includes(g)),
      esAlumno: slot.length > 0,
    };
  } catch {
    return null;
  } finally {
    try { await cliente.unbind(); } catch { }
  }
}
