import type { Lang } from './copy';

export interface Ui {
  eyebrow: { hero: string; lab: string; build: string; reqs: string; steps: string; course: string; network: string; wallpaper: string; weak: string; cutoff: string };
  hero: { title1: string; title2: string; sub: string; tagline: string; start: string; code: string; scroll: string };
  hud: { live: string; build: string; cutoff: string; target: string; domain: string; platform: string; course: string; courseValue: string };
  intro: string[];
  build: {
    title: string; text: string;
    first: string; region: string; host: string; mode: string; auto: string; yes: string; no: string;
    hostLinux: string; hostWindows: string;
    terminal: string; copyAll: string; copied: string;
    notes: Record<string, string>;
    modeNotes: Record<string, string>;
    lineConfig: string; lineIso: string; lineAuto: string; lineManual: string; lineMode: string;
  };
  steps: { progress: string; done: string; mark: string; reset: string; intro: string };
  course: { pick: string; points: string; optional: string; kinds: Record<string, string> };
  weak: { on: string };
  statement: { line1: string; line2: string; words: string[] };
  why: { eyebrow: string; title: string; body: string[]; sign: string; author: string; facts: { k: string; v: string }[] };
}

export const ui: Record<Lang, Ui> = {
  es: {
    eyebrow: { hero: 'Laboratorio de Active Directory', lab: 'El laboratorio', build: 'Tu instalación', reqs: 'Requisitos', steps: 'Paso a paso', course: 'El curso', network: 'Red', wallpaper: 'Identidad', weak: 'A propósito', cutoff: 'Fecha de corte' },
    hero: {
      title1: 'Hackers',
      title2: 'Fight Club',
      sub: 'Windows Server 2025   Siete días   Treinta y seis retos',
      tagline: 'Levanta el dominio, rómpelo y vuelve a defenderlo.',
      start: 'Empezar la instalación',
      code: 'Ver el código',
      scroll: 'Bajar',
    },
    hud: { live: 'En línea', build: 'Compilación 26100', cutoff: 'Corte 09 nov 2026', target: 'Objetivo', domain: 'Dominio', platform: 'Plataforma', course: 'Curso', courseValue: '36 retos en 7 días' },
    intro: [
      'Hackers Fight Club levanta desde cero un controlador de dominio listo para enseñar. Cada script hace una sola cosa, explica lo que hizo y te dice cuál sigue.',
      'El alumnado recorre siete días de práctica, de la consola de Windows a la enumeración de Active Directory, con banderas distintas para cada persona y una web que lleva la puntuación.',
    ],
    build: {
      title: 'Arma tu instalación',
      text: 'Elige cómo vas a instalar y la terminal te muestra exactamente lo que tienes que escribir.',
      first: 'es-MX',
      region: 'Región',
      host: 'Generas la ISO desde',
      mode: 'Modo de red',
      auto: 'Instalar solo al primer inicio',
      yes: 'Sí',
      no: 'No',
      hostLinux: 'Linux',
      hostWindows: 'Windows',
      terminal: 'Comandos para tu caso',
      copyAll: 'Copiar todo',
      copied: 'Copiado',
      notes: {
        'es-MX': 'Usa el ISO de Windows Server en español de España; la región es-MX pone teclado latinoamericano y formato mexicano.',
        'es-ES': 'Usa el ISO de Windows Server en español de España.',
        'en-US': 'Usa el ISO de Windows Server en inglés de Estados Unidos.',
        'ru-RU': 'Usa el ISO de Windows Server en ruso; el teclado queda en inglés con el ruso disponible y la hora de Moscú.',
      },
      modeNotes: {
        VMnet: 'El servidor y los equipos del alumnado comparten una red virtual de VMware.',
        LAN: 'Un salón con equipos físicos en la misma red.',
        Tailscale: 'Al terminar, conecta el servidor a tu tailnet con el último comando.',
        VPN: 'Ajusta VpnInterface y VpnClientCidr en la configuración antes de instalar.',
      },
      lineConfig: 'Edita config\\lab.config.psd1',
      lineIso: 'Genera la ISO de respuestas',
      lineAuto: 'Arranca la VM con el ISO de Windows y la ISO de respuestas. El laboratorio se instala solo.',
      lineManual: 'Ya en el servidor, como administrador',
      lineMode: 'Conecta el modo de red',
    },
    steps: { progress: 'listos', done: 'Hecho', mark: 'Marcar como hecho', reset: 'Reiniciar avance', intro: 'Los trece scripts en orden. Marca cada uno al terminarlo y tu avance se queda guardado en este navegador.' },
    course: {
      pick: 'Elige un día para ver sus retos',
      points: 'pts',
      optional: 'Opcional',
      kinds: { personal: 'Bandera personal', shared: 'Bandera común', check: 'Lo revisa el corrector', deliverable: 'Entrega' },
    },
    weak: { on: 'Activa' },
    why: {
      eyebrow: 'Por qué existe',
      title: 'Un laboratorio que cualquiera puede levantar',
      body: [
        'Lo construí para el módulo de Windows de Hackers Fight Club: siete días para pasar de abrir una consola a entender cómo se sostiene un dominio de Active Directory.',
        'Quería que cualquier persona pudiera levantar el mismo laboratorio en su casa o en un salón, sin depender de mi máquina ni de una red en particular, y que cada alumno trabajara con sus propias banderas para que aprender importara más que copiar.',
        'Lo publico para que otros clubes, docentes y autodidactas lo usen, lo rompan y lo mejoren.',
      ],
      sign: 'Aztharot',
      author: 'Autor',
      facts: [
        { k: 'Scripts', v: '13 pasos con nombre' },
        { k: 'Idiomas', v: 'Español, inglés y ruso' },
        { k: 'Redes', v: 'VMnet, LAN, Tailscale y VPN' },
        { k: 'Licencia', v: 'MIT' },
      ],
    },
    statement: {
      line1: 'Romper un dominio enseña poco',
      line2: 'si no entiendes cómo se construyó.',
      words: ['Construir', 'Romper', 'Defender'],
    },
  },
  en: {
    eyebrow: { hero: 'Active Directory lab', lab: 'The lab', build: 'Your install', reqs: 'Requirements', steps: 'Step by step', course: 'The course', network: 'Network', wallpaper: 'Identity', weak: 'On purpose', cutoff: 'Cutoff date' },
    hero: {
      title1: 'Hackers',
      title2: 'Fight Club',
      sub: 'Windows Server 2025   Seven days   Thirty six challenges',
      tagline: 'Stand up the domain, break it, then defend it again.',
      start: 'Start the install',
      code: 'View the code',
      scroll: 'Scroll',
    },
    hud: { live: 'Online', build: 'Build 26100', cutoff: 'Cutoff Nov 09 2026', target: 'Target', domain: 'Domain', platform: 'Platform', course: 'Course', courseValue: '36 challenges in 7 days' },
    intro: [
      'Hackers Fight Club builds a domain controller from scratch, ready to teach. Every script does one thing, explains what it did and tells you which one comes next.',
      'Students work through seven days of practice, from the Windows command prompt to Active Directory enumeration, with a different flag for every person and a website that keeps score.',
    ],
    build: {
      title: 'Build your install',
      text: 'Choose how you will install and the terminal shows exactly what you need to type.',
      first: 'en-US',
      region: 'Region',
      host: 'You build the ISO on',
      mode: 'Network mode',
      auto: 'Install by itself at first sign in',
      yes: 'Yes',
      no: 'No',
      hostLinux: 'Linux',
      hostWindows: 'Windows',
      terminal: 'Commands for your setup',
      copyAll: 'Copy all',
      copied: 'Copied',
      notes: {
        'es-MX': 'Use the Spanish (Spain) Windows Server ISO; the es-MX region sets a Latin American keyboard and Mexican formats.',
        'es-ES': 'Use the Spanish (Spain) Windows Server ISO.',
        'en-US': 'Use the US English Windows Server ISO.',
        'ru-RU': 'Use the Russian Windows Server ISO; the keyboard defaults to English with Russian available, on Moscow time.',
      },
      modeNotes: {
        VMnet: 'The server and the student machines share one VMware virtual network.',
        LAN: 'A classroom with physical machines on the same network.',
        Tailscale: 'Once it finishes, join the server to your tailnet with the last command.',
        VPN: 'Set VpnInterface and VpnClientCidr in the configuration before you install.',
      },
      lineConfig: 'Edit config\\lab.config.psd1',
      lineIso: 'Build the answer ISO',
      lineAuto: 'Boot the VM with the Windows ISO and the answer ISO. The lab installs itself.',
      lineManual: 'On the server, as an administrator',
      lineMode: 'Connect the network mode',
    },
    steps: { progress: 'done', done: 'Done', mark: 'Mark as done', reset: 'Reset progress', intro: 'The thirteen scripts in order. Mark each one as you finish it and your progress stays saved in this browser.' },
    course: {
      pick: 'Pick a day to see its challenges',
      points: 'pts',
      optional: 'Optional',
      kinds: { personal: 'Personal flag', shared: 'Shared flag', check: 'Checked by the scorer', deliverable: 'Deliverable' },
    },
    weak: { on: 'On' },
    why: {
      eyebrow: 'Why it exists',
      title: 'A lab anyone can stand up',
      body: [
        'I built it for the Hackers Fight Club Windows module: seven days to go from opening a console to understanding how an Active Directory domain holds together.',
        'I wanted anyone to be able to stand up the same lab at home or in a classroom, without depending on my machine or a specific network, and I wanted every student to work with their own flags so that learning mattered more than copying.',
        'I am publishing it so other clubs, teachers and self learners can use it, break it and make it better.',
      ],
      sign: 'Aztharot',
      author: 'Author',
      facts: [
        { k: 'Scripts', v: '13 named steps' },
        { k: 'Languages', v: 'Spanish, English and Russian' },
        { k: 'Networks', v: 'VMnet, LAN, Tailscale and VPN' },
        { k: 'License', v: 'MIT' },
      ],
    },
    statement: {
      line1: 'Breaking a domain teaches little',
      line2: 'if you do not understand how it was built.',
      words: ['Build', 'Break', 'Defend'],
    },
  },
  ru: {
    eyebrow: { hero: 'Лаборатория Active Directory', lab: 'Лаборатория', build: 'Ваша установка', reqs: 'Требования', steps: 'Шаг за шагом', course: 'Курс', network: 'Сеть', wallpaper: 'Идентичность', weak: 'Намеренно', cutoff: 'Дата актуальности' },
    hero: {
      title1: 'Hackers',
      title2: 'Fight Club',
      sub: 'Windows Server 2025   Семь дней   Тридцать шесть заданий',
      tagline: 'Подними домен, сломай его и снова защити.',
      start: 'Начать установку',
      code: 'Смотреть код',
      scroll: 'Вниз',
    },
    hud: { live: 'В сети', build: 'Сборка 26100', cutoff: 'Актуально на 09.11.2026', target: 'Цель', domain: 'Домен', platform: 'Платформа', course: 'Курс', courseValue: '36 заданий за 7 дней' },
    intro: [
      'Hackers Fight Club с нуля поднимает контроллер домена, готовый к обучению. Каждый скрипт делает одно дело, объясняет, что сделал, и подсказывает следующий.',
      'Учащиеся проходят семь дней практики, от командной строки Windows до разведки Active Directory, со своим флагом у каждого и сайтом, который ведёт счёт.',
    ],
    build: {
      title: 'Соберите свою установку',
      text: 'Выберите способ установки, и терминал покажет ровно то, что нужно ввести.',
      first: 'ru-RU',
      region: 'Регион',
      host: 'ISO собирается на',
      mode: 'Сетевой режим',
      auto: 'Установить само при первом входе',
      yes: 'Да',
      no: 'Нет',
      hostLinux: 'Linux',
      hostWindows: 'Windows',
      terminal: 'Команды для вашего варианта',
      copyAll: 'Копировать всё',
      copied: 'Скопировано',
      notes: {
        'es-MX': 'Используйте ISO Windows Server на испанском (Испания); регион es-MX задаёт латиноамериканскую раскладку и мексиканские форматы.',
        'es-ES': 'Используйте ISO Windows Server на испанском (Испания).',
        'en-US': 'Используйте ISO Windows Server на английском (США).',
        'ru-RU': 'Используйте русский ISO Windows Server; раскладка по умолчанию английская, русская доступна, время московское.',
      },
      modeNotes: {
        VMnet: 'Сервер и компьютеры учащихся находятся в одной виртуальной сети VMware.',
        LAN: 'Класс с физическими компьютерами в одной сети.',
        Tailscale: 'Когда установка закончится, подключите сервер к своей tailnet последней командой.',
        VPN: 'Перед установкой задайте VpnInterface и VpnClientCidr в конфигурации.',
      },
      lineConfig: 'Отредактируйте config\\lab.config.psd1',
      lineIso: 'Соберите ISO ответов',
      lineAuto: 'Загрузите ВМ с ISO Windows и ISO ответов. Лаборатория установится сама.',
      lineManual: 'На сервере, от имени администратора',
      lineMode: 'Подключите сетевой режим',
    },
    steps: { progress: 'готово', done: 'Готово', mark: 'Отметить как выполненный', reset: 'Сбросить прогресс', intro: 'Тринадцать скриптов по порядку. Отмечайте каждый по завершении, и прогресс сохранится в этом браузере.' },
    course: {
      pick: 'Выберите день, чтобы увидеть его задания',
      points: 'баллов',
      optional: 'Дополнительно',
      kinds: { personal: 'Личный флаг', shared: 'Общий флаг', check: 'Проверяется автоматически', deliverable: 'Сдача работы' },
    },
    weak: { on: 'Включено' },
    why: {
      eyebrow: 'Зачем это',
      title: 'Лаборатория, которую может поднять каждый',
      body: [
        'Эта лаборатория сделана для модуля Windows в Hackers Fight Club: семь дней, чтобы пройти путь от первой открытой консоли до понимания того, как держится домен Active Directory.',
        'Хотелось, чтобы любой мог поднять такую же лабораторию дома или в классе, не завися от моей машины или конкретной сети, и чтобы каждый учащийся работал со своими флагами: учиться важнее, чем списывать.',
        'Я публикую её, чтобы другие клубы, преподаватели и самоучки могли пользоваться ею, ломать её и улучшать.',
      ],
      sign: 'Aztharot',
      author: 'Автор',
      facts: [
        { k: 'Скрипты', v: '13 именованных шагов' },
        { k: 'Языки', v: 'Русский, английский и испанский' },
        { k: 'Сети', v: 'VMnet, LAN, Tailscale и VPN' },
        { k: 'Лицензия', v: 'MIT' },
      ],
    },
    statement: {
      line1: 'Взлом домена мало чему учит,',
      line2: 'если не понимаешь, как он был построен.',
      words: ['Строить', 'Ломать', 'Защищать'],
    },
  },
};
