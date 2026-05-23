# SI-APS CCFP — Sistema de Información APS
### ESE Hospital Regional Noroccidental · Salud Pública

Aplicación web local (PWA) para la captura y reporte del instrumento **APS124CCFP** del sistema PISIS del Ministerio de Salud de Colombia.

---

## Acceso

**GitHub Pages:** https://danto0702.github.io/si-aps-ccfp/

La aplicación funciona **100% offline** después de la primera carga. No requiere servidor, base de datos ni conexión permanente a internet.

---

## Funcionalidades

### Formulario principal (3 tablas, 90+ campos)
- **Tabla 1 — Identificación** del individuo y hogar
- **Tabla 2 — Caracterización familiar y de persona** (condiciones de vivienda, nutrición, salud mental, funcionalidad familiar)
- **Tabla 3 — Intervenciones** y seguimiento

### Herramientas clínicas integradas (Paso 5 · T2)

| Herramienta | Descripción |
|-------------|-------------|
| **Familiograma** | Genograma de 3 generaciones con símbolos estándar (casados, unión libre, separados, divorciados, biológico, adoptado, embarazo, aborto) + **8 tipos de relación emocional** (cercana, muy cercana, fusionada, distante, cortada, conflictiva, hostil, violencia) — estilo GenoPro |
| **Ecomapa** | Diagrama de relaciones del núcleo familiar con 8 sistemas externos (trabajo, salud, familia extensa, iglesia, amigos, recreación, servicios sociales, escuela) con 5 tipos de vínculo |
| **APGAR Familiar** | Escala de 5 ítems (adaptabilidad, cooperación, desarrollo, afectividad, resolución) con puntaje automático e interpretación |
| **Escala de Zarit** | Evaluación de sobrecarga del cuidador — 22 ítems con puntaje y categoría (sin sobrecarga / ligera / intensa) |

### Otras funcionalidades
- Modo offline (PWA con Service Worker)
- Persistencia en `localStorage` por sesión
- Exportación del reporte a Excel (`.xlsx`) vía SheetJS
- Validación de campos obligatorios por sección
- Indicadores de progreso por tabla
- Compatible con Chrome y Edge en Windows/Android

---

## Uso local

```
Abrir directamente en el navegador:
  SI-APS-CCFP.html
```

No requiere instalación. Solo abrir el archivo `.html` en Google Chrome o Microsoft Edge.

---

## Estructura

```
si-aps-ccfp/
├── SI-APS-CCFP.html   ← Aplicación completa (HTML + CSS + JS en un solo archivo)
├── index.html          ← Redirige a SI-APS-CCFP.html (para GitHub Pages)
├── manifest.json       ← Configuración PWA
├── sw.js               ← Service Worker (caché offline)
├── icon-192.png        ← Íconos PWA
├── icon-512.png
└── icon-180.png
```

---

## Tecnología

- **HTML5 + CSS3 + JavaScript** vanilla — sin frameworks, sin dependencias externas
- **SheetJS (xlsx)** — generación de Excel (carga dinámica online)
- **Leaflet** — captura de coordenadas GPS (carga dinámica online)
- **SVG** — renderizado de familiograma y ecomapa (100% offline)
- **localStorage** — persistencia de datos en el dispositivo

---

## Programa

**Coordinación de Salud Pública · ESE Hospital Regional Noroccidental**
Departamento de Norte de Santander, Colombia
Equipos Básicos de Salud (EBS) — Plan de Intervenciones Colectivas (PIC) — 2026

---

*Desarrollado con Claude Code · Mayo 2026*
