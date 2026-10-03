# Decisiones de arquitectura (ADR) — CuentasBot

> Todas en estado **Propuesta** hasta que el dueño apruebe el plan.

## ADR-001 — Colas en Postgres con pgmq
- **Contexto:** webhooks de Meta deben responder rápido; el trabajo pesado (IA, LibreOffice) es lento y debe reintentarse.
- **Decisión:** colas `inbound`, `jobs`, `outbound` en pgmq (Supabase). Reintento por *visibility timeout*, máximo 5 intentos, luego `job_failures` (DLQ visible en el panel).
- **Alternativas:** Redis/BullMQ (otra pieza que operar), SQS (otro proveedor).
- **Consecuencias:** una sola base de datos; transaccionalidad entre "guardar mensaje" y "encolar". A 10× (5.000 cuentas) sigue holgado.

## ADR-002 — Worker y panel en Railway
- **Decisión:** worker (Docker con LibreOffice) y panel Next.js en Railway, región US East, misma región que Supabase `us-east-1`.
- **Alternativas:** Fly.io (más operación), Render (instancias fijas más caras con 2 GB RAM), Vercel para el panel (Hobby no permite uso comercial; Pro suma US$20/mes).
- **Consecuencias:** un proveedor, red privada, despliegue desde GitHub.

## ADR-003 — Motor de plantillas docx-templates
- **Decisión:** `docx-templates` (MIT): bucles, condicionales, imágenes, etiquetas en encabezados. Los DOCX los sube solo el superadmin; el código JS en plantillas se desactiva/limita y se valida contra el catálogo de etiquetas.
- **Alternativas:** docxtemplater (imágenes = módulo de pago), Carbone (servidor adicional), generar DOCX por código (cada entidad requeriría programar).
- **Riesgo a verificar en Fase 0:** imágenes en tabla de 2 columnas y etiquetas en encabezado repetido.

## ADR-004 — Conversión DOCX→PDF con LibreOffice headless
- **Decisión:** `soffice --headless --convert-to pdf`, un proceso por réplica con cola interna y timeout; fuentes métricamente compatibles instaladas en la imagen.
- **Consecuencias:** fidelidad visual depende de fuentes; golden tests por texto + revisión visual.

## ADR-005 — Cifrado de columnas en la aplicación
- **Decisión:** AES-256-GCM en el worker/panel con `ENCRYPTION_KEY` (versionada en el texto cifrado); índice ciego HMAC para búsquedas exactas por documento; valores enmascarados (últimos 4) en columnas separadas.
- **Alternativas:** pgsodium (marcado en desuso por Supabase), Vault (pensado para secretos, no para datos de filas).
- **Consecuencias:** la base de datos nunca ve texto plano de datos sensibles; rotación de clave por re-cifrado en lote.

## ADR-006 — Transcripción con OpenAI gpt-4o-transcribe tras adaptador
- **Decisión:** `STT_PROVIDER=openai` modelo `gpt-4o-transcribe` con pista de vocabulario; adaptador para `gpt-4o-mini-transcribe` y Deepgram Nova-3.
- **Consecuencias:** evaluación con ~30 audios reales en Fase 1 decide el modelo definitivo.

## ADR-007 — Máquina de estados de conversación hecha a mano
- **Decisión:** reductores tipados por flujo (`flow`, `step`, `context`) en `packages/conversation`, independientes del canal; la IA solo interpreta texto libre, clasifica, extrae y redacta.
- **Alternativas:** XState (más abstracción de la necesaria), agente LLM libre (no determinístico, difícil de probar).
- **Consecuencias:** conversaciones grabadas como tests; simulador y WhatsApp comparten código.

## ADR-008 — Montos en pesos enteros (bigint)
- **Decisión:** todos los valores en COP como `bigint`; prorrateo con redondeo explícito y ajuste en el último pago (convención configurable por entidad).

## ADR-009 — Monorepo pnpm + Turborepo, Biome, Vitest
- **Decisión:** `apps/{worker,panel,simulator}`, `packages/{shared,docgen,conversation}`, `supabase/`. Biome para lint/formato (una herramienta, rápida), Vitest para tests, pgTAP para RLS.
