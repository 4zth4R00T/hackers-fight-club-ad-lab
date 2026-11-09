(function () {
  'use strict';

  var reducir = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  function semilla(n) {
    var s = n >>> 0;
    return function () {
      s = (s + 0x6d2b79f5) >>> 0;
      var t = s;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  function constelacion(lienzo) {
    var ctx = lienzo.getContext('2d');
    if (!ctx) return;
    var puntos = [];
    var neones = [];
    var ancho = 0;
    var alto = 0;
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    var colores = ['0,255,163', '0,255,163', '0,255,163', '0,255,163', '0,229,255', '255,46,99'];

    function preparar() {
      ancho = window.innerWidth;
      alto = window.innerHeight;
      lienzo.width = Math.round(ancho * dpr);
      lienzo.height = Math.round(alto * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      var azar = semilla(1090);
      var cantidad = Math.max(40, Math.min(150, Math.round((ancho * alto) / 15000)));
      puntos = [];
      for (var i = 0; i < cantidad; i++) {
        puntos.push({ x: azar() * (ancho + 80) - 40, y: azar() * (alto + 80) - 40, r: [1.1, 1.4, 1.9][Math.floor(azar() * 3)] });
      }
      neones = [];
      for (var j = 0; j < puntos.length && neones.length < 9; j++) {
        var p = puntos[j];
        var dx = (p.x - ancho / 2) / (ancho * 0.32);
        var dy = (p.y - alto / 2) / (alto * 0.36);
        if (Math.sqrt(dx * dx + dy * dy) > 1 && p.x > 0 && p.y > 0 && p.x < ancho && p.y < alto && azar() > 0.45) {
          neones.push({ p: p, c: colores[neones.length % colores.length], fase: azar() * Math.PI * 2 });
        }
      }
    }

    function dibujar(t) {
      ctx.clearRect(0, 0, ancho, alto);
      var maximo = 190;
      ctx.lineWidth = 0.6;
      for (var i = 0; i < puntos.length; i++) {
        var a = puntos[i];
        for (var j = i + 1; j < puntos.length; j++) {
          var b = puntos[j];
          var dx = b.x - a.x;
          var dy = b.y - a.y;
          var d = Math.sqrt(dx * dx + dy * dy);
          if (d < maximo) {
            var mx = (a.x + b.x) / 2 - ancho / 2;
            var my = (a.y + b.y) / 2 - alto / 2;
            var centro = Math.min(1, Math.sqrt(Math.pow(mx / (ancho * 0.34), 2) + Math.pow(my / (alto * 0.4), 2)));
            var alfa = 0.42 * (1 - d / maximo) * (0.2 + 0.8 * centro);
            ctx.strokeStyle = 'rgba(41,94,73,' + alfa.toFixed(3) + ')';
            ctx.beginPath();
            ctx.moveTo(a.x, a.y);
            ctx.lineTo(b.x, b.y);
            ctx.stroke();
          }
        }
      }
      ctx.fillStyle = 'rgba(52,104,84,0.6)';
      for (var k = 0; k < puntos.length; k++) {
        ctx.beginPath();
        ctx.arc(puntos[k].x, puntos[k].y, puntos[k].r, 0, Math.PI * 2);
        ctx.fill();
      }
      for (var n = 0; n < neones.length; n++) {
        var e = neones[n];
        var brillo = reducir ? 0.8 : 0.55 + 0.45 * Math.sin(t / 1400 + e.fase);
        var g = ctx.createRadialGradient(e.p.x, e.p.y, 0, e.p.x, e.p.y, 12);
        g.addColorStop(0, 'rgba(' + e.c + ',' + (0.45 * brillo).toFixed(3) + ')');
        g.addColorStop(1, 'rgba(' + e.c + ',0)');
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(e.p.x, e.p.y, 12, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = 'rgba(' + e.c + ',' + (0.6 + 0.4 * brillo).toFixed(3) + ')';
        ctx.beginPath();
        ctx.arc(e.p.x, e.p.y, 2.1, 0, Math.PI * 2);
        ctx.fill();
      }
    }

    var ultimo = 0;
    function ciclo(t) {
      if (t - ultimo > 66) {
        dibujar(t);
        ultimo = t;
      }
      window.requestAnimationFrame(ciclo);
    }

    var espera = null;
    window.addEventListener('resize', function () {
      if (espera) window.clearTimeout(espera);
      espera = window.setTimeout(function () { preparar(); dibujar(performance.now()); }, 150);
    });

    preparar();
    dibujar(0);
    if (!reducir) window.requestAnimationFrame(ciclo);
  }

  function marcarTodos() {
    var botones = document.querySelectorAll('[data-todos]');
    Array.prototype.forEach.call(botones, function (b) {
      b.addEventListener('click', function () {
        var grupo = b.getAttribute('data-todos');
        var marca = b.getAttribute('data-marca');
        var filas = document.querySelectorAll('[data-grupo="' + grupo + '"]');
        Array.prototype.forEach.call(filas, function (li) {
          var r = li.querySelector('input[value="' + marca + '"]');
          if (r) r.checked = true;
        });
      });
    });
  }

  function confirmaciones() {
    var formularios = document.querySelectorAll('form[data-confirmar]');
    Array.prototype.forEach.call(formularios, function (f) {
      f.addEventListener('submit', function (ev) {
        if (!window.confirm(f.getAttribute('data-confirmar') || '')) ev.preventDefault();
      });
    });
  }

  function iniciar() {
    var lienzo = document.querySelector('canvas[data-constelacion]');
    if (lienzo) constelacion(lienzo);
    marcarTodos();
    confirmaciones();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', iniciar);
  else iniciar();
})();
