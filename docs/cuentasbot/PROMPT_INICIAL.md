# PROMPT PARA CLAUDE CODE — "CuentasBot": asistente de WhatsApp para cuentas de cobro de contratistas del Estado (SaaS)

> Copia del documento de requisitos entregado por el dueño el 2026-10-03. Es la fuente de verdad del alcance; los cambios se registran en `DECISIONES.md`.

## 0. Cómo debes trabajar (instrucciones para Claude Code)

- Lee todo este documento antes de escribir código. Luego entra en modo plan y entrégame: arquitectura propuesta, esquema de base de datos, lista de servicios externos, variables de entorno y el plan de la Fase 1. Espera mi aprobación antes de construir.
- Crea un CLAUDE.md en la raíz con: resumen del producto, stack, convenciones, comandos (dev, test, deploy), y un glosario del dominio (sección 2). Mantenlo actualizado al cerrar cada fase.
- Construye por fases (sección 14). No adelantes fases. Al cerrar cada fase: pruebas en verde, README actualizado, y una lista corta de lo que debo probar manualmente.
- Pregunta antes de crear recursos que cuesten dinero, cambiar el esquema de datos ya en producción, o enviar mensajes a números reales.
- Nunca subas secretos al repositorio. Todo va en .env (con .env.example documentado) y en los secretos de Supabase / del proveedor de hosting.
- Idioma: código, nombres de tablas y comentarios en inglés; todo lo que ve el usuario final (mensajes de WhatsApp, panel, documentos) en español de Colombia, tono cordial y profesional, tuteo.
- Cuando una decisión técnica no esté definida aquí, elige la opción más simple que cumpla los requisitos de seguridad y escala, y regístrala en docs/DECISIONES.md (formato ADR corto).
- Verifica en la documentación oficial vigente (Meta WhatsApp Cloud API, Supabase, Anthropic, Wompi) cualquier detalle de API, límites o precios antes de implementarlo; no confíes en memoria.

## 1. Visión del producto

CuentasBot es un servicio de pago por suscripción que acompaña por WhatsApp a contratistas de prestación de servicios de entidades públicas colombianas (ESE, hospitales, alcaldías, gobernaciones) para que cada mes:

- Registren en el día a día sus actividades y evidencias (texto, notas de voz, fotos, capturas, PDFs).
- Reciban recordatorios para enviar los soportes de su cuenta de cobro (planilla de seguridad social, certificados de antecedentes, afiliaciones, etc.).
- Obtengan, al cierre del periodo, sus documentos listos para firmar y cargar: Informe de Actividades, Informe de Supervisión (borrador para el supervisor) y los PDF consolidados (antecedentes, afiliaciones), organizados como los exige su entidad.

Meta de escala inicial: ~500 cuentas de cobro al mes (≈300–500 contratistas activos, varios contratos por persona), con capacidad de crecer 10× sin rediseño.

Primera entidad (piloto): ESE Hospital Regional Noroccidental (HRNO), Ábrego, Norte de Santander. Sus formatos se describen en la sección 9 y deben ser la plantilla de referencia. El sistema debe ser multi-entidad desde el diseño: cada entidad tiene sus propias plantillas, checklist de soportes y reglas.

Principio rector: el contratista sigue siendo el responsable de lo que firma. El bot organiza, calcula, redacta borradores y valida, pero nunca inventa actividades y siempre pide aprobación antes de generar documentos finales.

## 2. Glosario del dominio (ponlo en CLAUDE.md)

- **Contratista:** persona natural con Contrato de Prestación de Servicios (CPS) con una entidad pública.
- **Contrato:** número (ej. CPS-0330-2026), código SECOP (ej. CO1.PCCNTR.9618889), objeto, plazo (fecha inicio–fin), valor total, valor mensual, número de pagos/informes, supervisor, ordenador del gasto, obligaciones específicas y generales.
- **Periodo / cuenta de cobro:** tramo del contrato que se cobra. Puede ser mes calendario (1–31) o mes aniversario (ej. del 24 al 23). El primer y el último periodo pueden ser proporcionales (ej. inicio 06/07 → primer periodo 06/07–31/07).
- **Informe No. X de N:** consecutivo del periodo dentro del contrato.
- **Pago No. X de N:** normalmente igual al número de informe; configurable.
- **Planilla PILA:** pago de seguridad social del independiente a través de un operador (Aportes en Línea, SOI, Mi Planilla, etc.). Datos: número de planilla, clave/PIN o número de autorización, fecha de pago, periodo de cotización, IBC, valores de salud (EPS), pensión (AFP), ARL, total, entidad financiera.
- **IBC:** Ingreso Base de Cotización. Para contratistas independientes es por regla general el 40% de los honorarios mensuales (sin IVA), con mínimo 1 SMMLV y máximo 25 SMMLV. Si la persona tiene varios contratos, una sola planilla puede cubrirlos y el IBC se calcula sobre la suma. Las reglas exactas deben ser configurables y verificarse con la norma vigente.
- **Antecedentes:** certificados de Policía (judiciales), Registro Nacional de Medidas Correctivas (RNMC), Procuraduría (disciplinarios) y Contraloría (fiscales). Los portales usan captcha → el contratista los descarga y los envía; el bot no hace scraping.
- **Afiliaciones:** certificados de EPS, ARL y fondo de pensiones.
- **Informe de supervisión:** documento que firma el supervisor certificando el cumplimiento; el bot genera el borrador prellenado.
- **SECOP II:** plataforma donde el contratista carga los documentos. El bot no se conecta a SECOP; entrega los archivos listos para cargar.

## 3. Decisiones ya tomadas (no las cambies sin consultarme)

| Tema | Decisión |
|------|----------|
| Usuarios | Multiusuario, multi-entidad, con roles (sección 4) |
| Canal | WhatsApp Cloud API oficial de Meta (número dedicado, Meta Business verificado). Nada de librerías no oficiales |
| Backend / datos | Supabase: Postgres (con RLS), Storage, Auth (panel), Edge Functions, colas (pgmq) y pg_cron |
| Procesamiento pesado | Un worker Node.js/TypeScript en contenedor (Railway, Fly.io o Render — propón uno) con LibreOffice headless para DOCX→PDF, y librerías de PDF/imagen |
| IA | Claude API (Anthropic) para extracción de documentos (visión), clasificación y redacción. Modelos configurables por variable de entorno |
| Voz | Proveedor de transcripción configurable (Claude no transcribe audio). Propón uno con buen español colombiano y costo bajo |
| Pagos | Suscripción mensual por contrato, cobrada con Wompi (PSE, Nequi, tarjeta) mediante links de pago enviados por WhatsApp + webhook |
| Onboarding | Auto-registro por WhatsApp: el contratista acepta tratamiento de datos, envía el PDF del contrato/clausulado y la IA extrae los datos; él confirma |
| Actividades | La IA redacta a partir de las notas, audios y fotos que el contratista envía durante el mes, asignándolas a cada obligación; el contratista aprueba antes de generar |
| Extracción de soportes | Sí: la IA lee planillas y certificados, extrae datos y pide confirmación |
| Configuración | Panel web admin para lo estructural + comandos de WhatsApp para el contratista |
| Entrega | PDF/DOCX directamente por WhatsApp (canal principal y único en el MVP). El ZIP con la estructura de carpetas también se envía como documento por WhatsApp. Google Drive y correo al supervisor quedan como opcionales de Fase 4 |
| Panel web | Next.js (App Router) + Supabase Auth, desplegado en Vercel (o el mismo proveedor del worker si simplifica) |

## 4. Roles y permisos

- **Superadmin** (dueño del servicio): todo. Crea entidades, plantillas, precios, ve métricas y costos.
- **Operador** (soporte): ve contratistas y cuentas, puede corregir datos y reenviar documentos; no ve pagos completos ni borra.
- **Contratista** (usuario final, vía WhatsApp; opcionalmente un portal web de solo lectura con login por código OTP enviado por WhatsApp): sus contratos, sus cuentas, sus documentos.
- **(Futuro) Entidad:** una ESE puede contratar el servicio para todos sus contratistas y ver estado agregado. Deja el modelo preparado (tabla organizations con plan de facturación) pero no lo construyas aún.

Implementa RLS en todas las tablas. El webhook y el worker usan la service_role solo del lado servidor.

## 5. Arquitectura

```
WhatsApp (contratista)
   │
   ▼
Meta Cloud API ──webhook──► Edge Function `wa-webhook`
                              • verifica firma X-Hub-Signature-256
                              • responde 200 de inmediato
                              • guarda el mensaje crudo (idempotencia por wamid)
                              • encola en pgmq `inbound`
                                   │
                                   ▼
                          Worker (Node/TS, contenedor)
                              • orquestador de conversación (máquina de estados)
                              • descarga de medios (Graph API, URL expira en minutos)
                              • transcripción de audio
                              • clasificación y extracción con Claude
                              • validaciones y cálculos
                              • generación DOCX (plantillas) → PDF (LibreOffice)
                              • unión de PDFs, compresión de imágenes, ZIP
                              • envío de mensajes salientes (cola `outbound` con rate-limit y reintentos)
                                   │
                                   ▼
                          Supabase Postgres + Storage
                                   ▲
                                   │
               Panel admin (Next.js)    pg_cron → recordatorios programados
               Webhook Wompi (Edge Function) → activa/suspende suscripciones
```

Requisitos no funcionales:

- Idempotencia: Meta reintenta webhooks; nunca procesar dos veces el mismo wamid. Lo mismo con eventos de Wompi.
- Reintentos con backoff y cola de mensajes muertos (dead letter) visible en el panel.
- Rate limiting saliente según el tier del número de WhatsApp.
- Observabilidad: logs estructurados, tabla events de auditoría, métricas de costo de IA por contratista y por cuenta.
- Tiempo de respuesta: acuse de recibo al usuario en < 5 s; procesamiento de documentos puede tardar más, avisando "Estoy revisando tu planilla…".
- Respaldo: backups diarios de Postgres; Storage con versionado o copia periódica.

## 6. Modelo de datos (propuesta; refínala en el plan)

- **organizations** — (futuro) cliente corporativo.
- **entities** — entidad pública contratante: nombre, NIT, municipio, logo, configuración (tipo de periodo por defecto, vigencia de certificados en días, reglas de IBC, textos fijos).
- **templates** — por entidad y tipo (activity_report, supervision_report, cover_letter…): archivo DOCX base en Storage, versión, catálogo de etiquetas que usa, estado (borrador/activa).
- **support_types** — catálogo de soportes por entidad: código (PILA, POLICIA, RNMC, PROCURADURIA, CONTRALORIA, EPS, ARL, AFP, RUT, CEDULA, CUENTA_BANCARIA, EVIDENCIA…), si es obligatorio, frecuencia (cada periodo / una vez / al inicio), vigencia máxima, orden dentro del PDF consolidado, a qué paquete pertenece (ANTECEDENTES.pdf, AFILIACIONES.pdf, suelto).
- **users** — contratista: teléfono WhatsApp (E.164, único), nombre, tipo y número de documento, lugar de expedición, régimen tributario, banco, tipo y número de cuenta (cifrado), firma escaneada opcional (cifrada, con consentimiento), estado, fecha de aceptación de tratamiento de datos y versión de la política.
- **contracts** — usuario, entidad, número, código SECOP, objeto (texto completo), proceso/área, fecha inicio, fecha fin, valor total, valor mensual, número de pagos, tipo de periodo (calendario/aniversario + día de corte), supervisor (nombre, cargo), ordenador del gasto, adiciones/prórrogas, estado, PDF del contrato y del clausulado.
- **obligations** — contrato, tipo (specific/general), número, texto literal, texto por defecto cuando no hay novedad (ej. "Actividad cumplida."), si requiere evidencia.
- **periods** (la "cuenta de cobro") — contrato, número de informe, fecha desde, fecha hasta, valor a cobrar (con prorrateo), estado (máquina de estados en sección 7), fechas de cierre y entrega.
- **social_security_payments** — planilla: usuario, operador, número de planilla, PIN/autorización, fecha de pago, periodo de cotización, IBC, salud (entidad, valor), pensión (entidad, valor), FSP, ARL (entidad, valor, clase de riesgo), total, entidad financiera, archivo, datos extraídos (JSON) y confirmados. Relación N:M con periods (una planilla puede respaldar periodos de varios contratos del mismo mes).
- **supports** — archivo recibido: usuario, periodo (si aplica), tipo, archivo original y normalizado (PDF), fecha de expedición extraída, vigente hasta, estado (received, extracted, confirmed, rejected, expired), motivo de rechazo.
- **activity_notes** — bitácora: usuario, contrato (o "sin asignar"), fecha de la actividad, texto (o transcripción), audio original, medios adjuntos, obligación sugerida por IA, obligación confirmada, confianza.
- **evidences** — imagen/archivo asociado a obligación y periodo, con pie de foto, orden.
- **drafts** — borrador de texto por obligación y periodo: generado por IA, editado por el usuario, aprobado (sí/no), fuentes (ids de notas usadas).
- **generated_documents** — periodo, tipo, versión, DOCX y PDF en Storage, hash, generado por, fecha.
- **subscriptions / payments** — plan, precio, estado (trial, active, past_due, suspended), periodo pagado, referencia Wompi, eventos.
- **conversations** — estado actual de la conversación por usuario (flujo, paso, contexto JSON, expira).
- **messages** — log de entrada/salida (wamid, dirección, tipo, contenido resumido, estado de entrega).
- **reminder_rules** — por entidad (y sobreescribible por contrato): disparador relativo al periodo (ej. "5 días antes del cierre", "día 20", "día de cierre"), soporte o acción, plantilla de mensaje de WhatsApp aprobada.
- **ai_usage** — modelo, tokens de entrada/salida, costo estimado, propósito, usuario, periodo.
- **events** — auditoría inmutable de acciones relevantes.

Storage: buckets privados contracts/, supports/, evidences/, templates/, outputs/; ruta {entity_id}/{user_id}/{contract_id}/{period_number}/.... Acceso solo con URLs firmadas de vida corta.

## 7. Máquina de estados de una cuenta (periodo)

```
SCHEDULED ──(inicia periodo)──► COLLECTING
COLLECTING ──(checklist completo + fin de periodo o usuario dice "cerrar")──► READY_TO_DRAFT
READY_TO_DRAFT ──(IA redacta)──► DRAFT_REVIEW
DRAFT_REVIEW ──(usuario aprueba todas las obligaciones)──► APPROVED
APPROVED ──(suscripción activa)──► GENERATING ──► DELIVERED
DELIVERED ──(usuario pide cambios)──► DRAFT_REVIEW   (nueva versión)
Cualquiera ──(pago vencido)──► BLOCKED_PAYMENT (sigue recibiendo notas y soportes; no genera)
```

Reglas:

- El usuario puede registrar notas y soportes en cualquier momento del periodo.
- La generación final exige: checklist obligatorio completo y validado, todas las obligaciones con texto aprobado, suscripción activa.
- Se permite "generar de todas formas" con faltantes solo si la entidad lo permite y queda marcado en el documento interno de control (nunca en el informe oficial).

## 8. Conversaciones de WhatsApp

### 8.1 Reglas generales

- Respeta la ventana de servicio de 24 h de Meta: fuera de ella solo se pueden enviar plantillas aprobadas. Todos los recordatorios proactivos deben usar plantillas (categoría utilidad). Crea el catálogo de plantillas necesarias en docs/WHATSAPP_TEMPLATES.md con texto, variables y categoría para que yo las registre en Meta.
- Usa mensajes interactivos (botones de respuesta — máx. 3 — y listas — máx. 10 opciones) siempre que haya opciones; acepta también texto libre y entiende sinónimos.
- Mensajes cortos, uno por idea. Emojis con moderación (✅ ⚠️ 📎 📄).
- Siempre hay salida: "menú", "ayuda", "hablar con soporte" (crea un ticket visible en el panel).
- Si el usuario tiene varios contratos, cada nota o soporte ambiguo se confirma con botones: "¿A cuál contrato corresponde? [0330 Salud Pública] [0385 EBS] [Ambos]".
- Opt-out: "STOP"/"no más recordatorios" desactiva recordatorios (no la cuenta).

### 8.2 Onboarding (auto-registro)

1. Saludo + qué hace el servicio + precio + enlace a política de tratamiento de datos (Ley 1581 de 2012, Decreto 1377 de 2013) → botón Acepto / No acepto. Sin aceptación no se guarda nada más allá del número y el rechazo.
2. Datos personales: nombre completo, tipo y número de documento, lugar de expedición. (Valida formato de cédula.)
3. Datos de pago de honorarios: banco, tipo y número de cuenta, régimen. (Se guardan cifrados; se muestran enmascarados.)
4. "Envíame el PDF de tu contrato y, si lo tienes aparte, el clausulado/estudio previo con las obligaciones."
5. La IA extrae: entidad (buscar/crear), número, SECOP, objeto, plazo, valor total y mensual, número de pagos, supervisor, obligaciones específicas y generales (texto literal, numeradas). Muestra un resumen y pide confirmar campo por campo los críticos (fechas, valores, número de pagos). Permite corregir con texto libre ("el valor mensual es 8.500.000").
6. Detecta el tipo de periodo (calendario vs aniversario) y propone el calendario de cuentas con prorrateos; pide confirmación.
7. Si la entidad no existe o no tiene plantillas activas: queda en estado pending_templates, avisa al superadmin y le dice al usuario que en máximo X horas hábiles queda listo (sigue pudiendo registrar notas).
8. Activa prueba gratuita (configurable) o envía link de pago.
9. Explica en 3 mensajes cómo usarlo día a día.

### 8.3 Registro diario de actividades

- El usuario envía texto, audio, foto(s), captura, PDF o combinación. Ejemplos: "hoy capacité a 30 personas de EBS en misión médica en El Carmen" + 2 fotos.
- El bot: transcribe audio → resume → sugiere contrato y obligación con confianza → si confianza alta, confirma en una línea con botón [Cambiar]; si baja, pregunta con lista de obligaciones.
- Fotos sin texto: pregunta "¿Qué actividad muestra esta foto?" (agrupa álbumes enviados juntos, ventana de ~60 s).
- Registra fecha (por defecto hoy; entiende "ayer", "el martes", "el 15").
- Recordatorio diario opcional a la hora que elija el usuario: "¿Qué hiciste hoy? Puedes mandarme un audio."

### 8.4 Soportes

- El usuario puede enviar cualquier archivo cuando quiera; la IA clasifica el tipo (planilla, Policía, RNMC, Procuraduría, Contraloría, EPS, ARL, AFP, otro).
- Planilla: extrae número, PIN/autorización, operador, fecha de pago, periodo de cotización, IBC, valores por subsistema, total, banco. Muestra tabla y pide confirmar. Pregunta a qué contratos aplica (por defecto, todos los vigentes ese mes).
- Certificados: extrae fecha de expedición, nombre y documento del titular; valida que coincidan con el usuario; para ARL extrae fechas de cobertura.
- Comando "¿qué me falta?" → checklist del periodo con ✅/⚠️/❌ por contrato.
- Recordatorios automáticos según reminder_rules (ej. HRNO: día 20 "paga tu planilla", día 25 "descarga antecedentes", último día "cierra tu informe").

### 8.5 Validaciones (cada una con mensaje claro y accionable)

- Periodo de cotización de la planilla corresponde al periodo cobrado (regla de la entidad: mes vencido o mes en curso — configurable).
- IBC ≥ 40% de la suma de honorarios mensuales de los contratos que respalda (con mínimo y tope en SMMLV configurables por año). Si no cuadra: advertencia, no bloqueo, salvo que la entidad lo marque como bloqueante.
- Fecha de pago de la planilla dentro del rango permitido por la entidad.
- Certificados expedidos dentro de la vigencia configurada (ej. ≤ 30 días antes de la fecha de radicación).
- Titular del certificado = contratista.
- Cobertura de ARL cubre todo el periodo de cada contrato (alerta típica: la ARL quedó con fecha de retiro del contrato que terminó primero).
- Contrato vigente en todo el periodo; alerta 15 días antes del fin del contrato ("¿tienes contrato nuevo? envíamelo").
- Suma de pagos no supera el valor total del contrato.

### 8.6 Redacción con IA y aprobación

Al pasar a READY_TO_DRAFT:

- Para cada obligación específica, Claude redacta 1–4 oraciones en tono institucional, en pasado/presente impersonal ("Se realizó…", "Se participó en…"), usando solo los hechos de las notas asignadas (fechas, lugares, cantidades, nombres de comités o programas).
- Si una obligación no tiene notas: no inventa. Pregunta al usuario: "Para la obligación 6 (enlace en actividades extramurales) no tengo registros este mes. ¿Qué hiciste? [Escribir/Audio] [Usar texto por defecto] [No aplicó]".
- Las obligaciones generales usan el texto por defecto configurado salvo que haya notas.
- Envía el borrador por bloques (o un PDF de vista previa) con botones [✅ Aprobar todo] [✏️ Editar una] . Editar: el usuario elige la obligación y dicta el cambio; la IA reescribe y vuelve a mostrar.
- Las evidencias se asignan por obligación (máx. configurable por obligación, ej. 3), ordenadas por fecha; el usuario puede quitar o reordenar.

### 8.7 Entrega

- Genera: Informe de Actividades (DOCX + PDF), Borrador de Informe de Supervisión (DOCX + PDF), ANTECEDENTES.pdf, AFILIACIONES.pdf, planilla en PDF, y un ZIP con la estructura de carpetas de la entidad (para HRNO: carpeta del periodo y subcarpeta DOCUMENTOS A CARGAR).
- Envía todo por WhatsApp como documentos: primero los PDF principales (para revisar en el celular), luego los DOCX editables y al final el ZIP. Respeta el límite de tamaño de documentos de la Cloud API; si el ZIP lo supera, divídelo en partes. El contratista puede pedir reenviar documentos en cualquier momento (los archivos quedan guardados en Storage según la retención configurada).
- Mensaje final con checklist de lo que falta hacer fuera del bot: firmar, entregar al supervisor, cargar en SECOP II.

### 8.8 Comandos del contratista (texto o menú)

menú, ayuda, estado / ¿qué me falta?, mis contratos, nuevo contrato, nota (forzar registro), ver borrador, generar, reenviar documentos, mis datos, pagar, recordatorio a las 5 pm, no más recordatorios, borrar mis datos (flujo de supresión con confirmación), soporte.

## 9. Plantillas y formato de la entidad piloto (HRNO)

Implementa un motor de plantillas DOCX basado en etiquetas (recomendado: docx-templates, porque soporta bucles e imágenes sin licencia de pago; evalúa alternativas y justifica). El superadmin sube un DOCX con etiquetas y el sistema valida que todas las etiquetas existan en el catálogo. Crea docs/TEMPLATE_TAGS.md con el catálogo completo.

Funciones auxiliares obligatorias: número a letras en español colombiano para valores ("CUATRO MILLONES DE PESOS M/CTE ($4.000.000)"), formato de moneda $ 4.000.000, fechas dd/mm/aaaa y "1 al 31 de agosto de 2026", número de informe con ceros ("02 DE 03"), porcentajes con coma decimal ("66,66%").

### 9.1 Informe de Actividades (HRNO)

Encabezado repetido en cada página: "INFORME DE ACTIVIDADES – CONTRATO DE PRESTACIÓN DE SERVICIOS ({objeto}) No. {numero_contrato} – {NOMBRE CONTRATISTA} – INFORME – No. {nn} DE {NN} – DEL {d} AL {d} DE {MES} DE {AAAA}".

- Datos generales: contrato No., proceso, plazo de ejecución desde/hasta, periodo de la cuenta, nombre, documento, régimen (común/simplificado), cuenta, banco, tipo de cuenta, Pago No. X de N, No. de planilla, ARL sí/no.
- Información de seguridad social: aportes salud, pensión, Fondo de Solidaridad Pensional, AFC voluntario, ARL, total, con la nota fija sobre el 40% de los honorarios.
- Informe de actividades: tabla de dos columnas (obligación literal | actividad realizada), primero específicas y luego generales.
- Certificación juramentada: texto fijo configurable por entidad con variables (contrato y periodo) + nombre, documento y lugar de expedición + espacio de firma (firma escaneada solo si el usuario la cargó y la autoriza en esa generación).
- Anexos – evidencias: por cada obligación con evidencia, título "Actividad N." y sus imágenes escaladas al ancho útil, máximo 2 por fila.

La entidad usa variaciones del mismo formato por tipo de contrato (ej. contratos de Coordinación de Salud Pública y de Equipos Básicos en Salud tienen encabezados con tipografía distinta y "Pago No. 02-06" en lugar de "02 de 03"). El motor debe permitir varias plantillas por entidad y asignar plantilla por contrato.

### 9.2 Informe de Supervisión (HRNO — código MA-GH-IS-03, versión 4.0)

Borrador prellenado para el supervisor:

- Párrafo legal fijo (Ley 1474 de 2011, manual de contratación de la entidad) con nombre del supervisor y número de contrato.
- Información general: periodo desde/hasta, fecha del informe (vacía para el supervisor o configurable), desempeño deficiente SI/NO (por defecto NO), % ejecución física (100%) y % presupuestal = (valor acumulado cobrado incluyendo este periodo / valor total) con 2 decimales, valor del contrato, plazo, prórroga/adición, objeto.
- Asistentes: supervisor y cargo; contratista con documento y lugar de expedición; otros asistentes ("NO HUBO" por defecto); lugar; hora inicio/fin (configurables por entidad).
- Objetivo de la reunión: "Recibo informe de actividades realizadas por parte del contratista durante el periodo del {d} al {d} de {mes} de {aaaa}, en cumplimiento a lo establecido en el contrato No. {numero}".
- Actividad/compromiso: "Certificar que el informe de actividades {n} de {N} del presente contrato…".
- 1.2 Grado de cumplimiento de obligaciones generales: tabla con escala (Deficiente / A mejorar / Satisfactorio / Sobresaliente / No aplica); por defecto "Sobresaliente", editable por el supervisor.
- 2.1 Relación de pagos a seguridad social: tabla vertical con mes, operador, pensión (entidad y valor), salud (entidad y valor), ARL (entidad y valor), total, No. de planilla, PIN, entidad financiera, periodo de cotización, fecha de pago.
- 2.2 Inhabilidades: fechas de los certificados de Contraloría, Procuraduría y Medidas Correctivas.
- 2.3 Cumplimiento de actividades: tabla de obligaciones especiales con columna de aprobación.
- Balance financiero: valor inicial, adiciones, valor total, valor pagado, valor causado no pagado, valor ejecutado, valor no ejecutado, y columna de pagos/actas. Calcula con fórmulas configurables por entidad (las entidades no siempre usan la misma convención) y muestra al usuario los valores antes de generar para que confirme.
- Párrafo de certificación del pago con valor en letras y números.
- Compromisos adquiridos: "Presentar informe de actividades" con fecha de entrega = fin del siguiente periodo (en el último periodo: "N/A – informe final").
- "En constancia se firma a los __ días del mes de ____ de {aaaa}" + firmas supervisor y contratista.

### 9.3 Paquetes PDF

- ANTECEDENTES.pdf = Policía + Medidas Correctivas + Procuraduría + Contraloría (orden configurable por entidad).
- AFILIACIONES.pdf = EPS + ARL + Pensión (orden configurable).
- Convierte imágenes (incluye HEIC de iPhone) a PDF, corrige orientación, comprime a un tamaño razonable (objetivo < 2 MB por documento, configurable) y verifica legibilidad mínima.
- Si el usuario tiene varios contratos en el mismo mes, los paquetes se copian en el ZIP de cada contrato.

### 9.4 Fixtures de prueba

Te entregaré PDFs reales anonimizados de HRNO (informe de actividades de dos tipos de contrato, informe de supervisión, planilla, certificados). Úsalos para:

- Construir las plantillas DOCX de HRNO con etiquetas.
- Pruebas "golden": generar con datos de prueba y comparar texto extraído del PDF contra el esperado.
- Pruebas de extracción de planilla y certificados. No subas documentos reales al repositorio: van en una carpeta ignorada (fixtures/private/) y los tests usan versiones sintéticas.

## 10. Uso de IA (Claude API)

- Modelos por variable de entorno: uno rápido/económico para clasificación y extracción simple (ej. claude-haiku-4-5-20251001) y uno más capaz para redacción y contratos largos (ej. claude-sonnet-5-5). Verifica los identificadores vigentes en la documentación de Anthropic.
- Salidas estructuradas siempre (tool use / JSON schema validado con Zod). Nunca parsees texto libre.
- Prompts versionados en src/ai/prompts/*.ts, con pruebas de regresión sobre fixtures.
- Reglas anti-alucinación en el prompt de redacción: usar solo hechos de las notas proporcionadas; no agregar cifras, fechas, lugares ni nombres que no estén en las notas; si falta información, devolver needs_input en vez de inventar; mantener el texto literal de las obligaciones.
- Cada extracción devuelve confidence por campo; por debajo de un umbral configurable se pregunta al usuario.
- Envía PDFs e imágenes directamente como entrada de visión; para contratos largos, extrae primero texto y usa visión solo en páginas necesarias para controlar costos.
- Usa caché de prompts para los bloques fijos (instrucciones, obligaciones del contrato).
- Registra tokens y costo en ai_usage; el panel muestra costo por cuenta y alerta si una cuenta supera un umbral.
- Los datos personales se envían a la API solo en la medida necesaria; documenta esto en la política de tratamiento.

## 11. Pagos (Wompi)

- Planes configurables en el panel (precio mensual por contrato, descuento por 2+ contratos, prueba gratis de N días/1 cuenta).
- Cada mes, antes de generar, si la suscripción no está paga: envía link de pago Wompi por WhatsApp.
- Webhook de Wompi en Edge Function: verifica la firma/checksum del evento, idempotencia por id de transacción, actualiza payments y subscriptions, notifica al usuario.
- Estados: trial → active → past_due (gracia configurable) → suspended. En suspended sigue recibiendo notas y soportes, pero no genera.
- Panel: listado de pagos, conciliación, reembolso manual (marcar), exportar CSV.
- Usa el ambiente de pruebas (sandbox) de Wompi hasta que yo autorice producción.

## 12. Panel web admin

Secciones:

- Dashboard: cuentas por estado este mes, contratistas activos, cuentas listas sin generar, soportes vencidos, ingresos del mes, costo de IA y de WhatsApp, tasa de éxito de extracción.
- Entidades: CRUD, configuración (tipo de periodo, vigencias, reglas IBC, textos fijos, horas de reunión, fórmulas de balance), checklist de soportes, reglas de recordatorio.
- Plantillas: subir DOCX, validar etiquetas, vista previa con datos de ejemplo, activar versión, asignar a tipos de contrato.
- Contratistas: buscar por nombre/teléfono/documento, ver contratos, cuentas, conversación (últimos mensajes), soportes, documentos generados; acciones: corregir datos, regenerar, reenviar, suspender, enviar mensaje manual (dentro de la ventana de 24 h).
- Cuentas: tabla filtrable por entidad/mes/estado, con acceso al detalle y al ZIP.
- Bandeja de soporte: tickets abiertos desde WhatsApp.
- Pagos y planes.
- Plantillas de WhatsApp: catálogo y su estado de aprobación (registro manual del estado).
- Auditoría y cola de errores (dead letter) con botón de reintento.

Login con Supabase Auth (correo + contraseña con 2FA para superadmin). Diseño sobrio, responsive, accesible.

## 13. Seguridad, privacidad y cumplimiento

- Ley 1581 de 2012 / Decreto 1377 de 2013 (habeas data): aviso de privacidad, política de tratamiento versionada, consentimiento previo, expreso e informado guardado con fecha y versión; canal para consultas, rectificación y supresión ("borrar mis datos" → borrado/anonimización en ≤ 15 días hábiles, conservando solo lo que la ley exija). Genera borradores de docs/legal/politica_tratamiento.md y docs/legal/terminos.md marcados como "PENDIENTE DE REVISIÓN POR ABOGADO".
- Datos sensibles (documento, cuenta bancaria, firma): cifrado a nivel de columna (pgsodium/Vault o cifrado de aplicación con clave en secretos) y enmascarados en el panel.
- RLS en todo; buckets privados; URLs firmadas cortas; sin datos personales en logs.
- Verificación de firma en todos los webhooks (Meta, Wompi).
- Políticas de Meta: opt-in explícito, plantillas solo para lo permitido, opción de salida.
- Retención configurable de archivos (ej. 24 meses) con purga automática.
- Descargo en los términos: el servicio es una herramienta de apoyo; el contratista revisa y firma bajo su responsabilidad; el servicio no tiene relación con la entidad contratante salvo acuerdo.
- La firma escaneada solo se inserta si el usuario la cargó, aceptó su uso, y confirma en cada generación.

## 14. Fases de entrega

**Fase 0 — Base (sin WhatsApp real).** Repositorio monorepo (apps/panel, apps/worker, supabase/ con migraciones y funciones, packages/shared con tipos y utilidades), CI con lint + tests, esquema inicial con RLS, seed con entidad HRNO, motor de plantillas + utilidades (número a letras, fechas, cálculos de periodos y prorrateo, % presupuestal, balance), y un simulador de chat local (CLI o página) que usa el mismo orquestador que WhatsApp. Criterio de aceptación: con datos de prueba, genero desde el simulador el informe de actividades y de supervisión de HRNO para un periodo completo y uno prorrateado, y los PDF se ven como los originales.

**Fase 1 — MVP WhatsApp (HRNO, sin cobro).** Webhook Cloud API, colas, onboarding con contrato cargado por el superadmin desde el panel, registro de notas (texto, foto, audio), recepción y clasificación de soportes, checklist, recordatorios con plantillas, redacción con IA + aprobación, generación y entrega. Criterio: 5 contratistas piloto de HRNO cierran una cuenta real de punta a punta.

**Fase 2 — Extracción y validaciones.** Extracción de contrato por IA en el auto-registro, extracción de planillas y certificados, todas las validaciones de 8.5, múltiples contratos por usuario con planilla compartida.

**Fase 3 — Pagos y operación comercial.** Wompi, planes, prueba gratis, suspensión, panel de pagos, métricas de costo, bandeja de soporte, términos y política publicados.

**Fase 4 — Multi-entidad autoservicio y extras.** Flujo para entidades sin plantilla (operador las crea a partir de un PDF de ejemplo que envía el usuario), exportación a Google Drive, envío por correo al supervisor, portal web de solo lectura para el contratista, rol "Entidad".

## 15. Pruebas

- Unitarias: cálculos de periodos (calendario, aniversario, prorrateo, último periodo), IBC, % presupuestal, balance, número a letras (incluye millones, miles, ceros), fechas en español.
- Integración: orquestador de conversación con conversaciones grabadas (fixtures JSON de mensajes entrantes → mensajes salientes esperados).
- Golden tests de plantillas.
- Evaluaciones de IA: set de 20+ notas reales anonimizadas → asignación de obligación correcta ≥ 90%; set de planillas de distintos operadores → extracción exacta de número/PIN/fecha/total; prueba de "no inventa" (notas vacías → needs_input).
- Prueba de carga: 500 cuentas generadas en una ventana de 48 h (cierre de mes) sin errores ni duplicados.

## 16. Variables de entorno (mínimo; complétalas)

```
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
WA_PHONE_NUMBER_ID=
WA_BUSINESS_ACCOUNT_ID=
WA_ACCESS_TOKEN=
WA_APP_SECRET=
WA_VERIFY_TOKEN=
ANTHROPIC_API_KEY=
AI_MODEL_FAST=
AI_MODEL_SMART=
STT_PROVIDER=
STT_API_KEY=
WOMPI_PUBLIC_KEY=
WOMPI_PRIVATE_KEY=
WOMPI_EVENTS_SECRET=
WOMPI_INTEGRITY_SECRET=
WOMPI_ENV=sandbox
APP_BASE_URL=
ENCRYPTION_KEY=
SUPPORT_PHONE=
TZ=America/Bogota
```

## 17. Lo que yo (el dueño) voy a preparar en paralelo — recuérdamelo cuando lo necesites

- Cuenta de Meta Business verificada, app de Meta con WhatsApp, número dedicado y token permanente (usuario del sistema).
- Proyecto de Supabase (plan con backups) y cuenta en el proveedor del worker.
- Cuenta de Wompi (sandbox y luego producción).
- API key de Anthropic y del proveedor de transcripción.
- Dominio para el panel y la página de política de datos.
- PDFs anonimizados de HRNO y los DOCX originales de los formatos.
- Revisión legal de política de tratamiento y términos.
- Nombre comercial definitivo y precio.

## 18. Primera respuesta que espero de ti

- Preguntas que te queden (máximo 10, concretas).
- Plan de arquitectura con diagrama, esquema SQL inicial y justificación de proveedores (worker, transcripción, librería de plantillas).
- Estimación de costos mensuales para 500 cuentas/mes (WhatsApp, IA, transcripción, hosting, Supabase), con supuestos explícitos.
- Plan detallado de la Fase 0 con tareas y criterios de aceptación.

No escribas código de producto hasta que apruebe el plan.
