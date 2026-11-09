declare namespace App {
  interface Locals {
    usuario?: {
      sam: string;
      nombre: string;
      correo: string;
      slot: string;
      esInstructor: boolean;
      esAlumno: boolean;
    } | null;
    csrf?: string;
    idioma?: 'es' | 'en' | 'ru';
  }
}
