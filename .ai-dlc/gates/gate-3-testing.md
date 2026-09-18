# Gate 3 — Testing

- [x] Plan de pruebas con dos niveles: CI (integración aislada) y appliance (staging real)
      (`docs/04-testing/test-plan.md`)
- [x] Frontera de confianza en la red real: F1–F3 (incluido un PC real de la LAN) y F2 (docker0 → 403)
- [x] Endurecimiento, topes, digest, NFS `ro`+`rslave` y `network.xml` verificados en el appliance
- [x] RNF02: Heimdall sin alertas durante un transcode con el tope puesto
- [ ] **RF03**: transcode a ≥ 1,0x con `cpus: 3.0`. Medido 0,78x con contención y **0,92x sin
      contención** (H5). `superfast` con 3.0: **1,13x**; `veryfast` con 4.0: 1,11x. Pendiente la decisión HITL
- [ ] H4 (arranque tras apagón) pasa al Gate 4 con prueba de reinicio HITL

Evidencia: tabla de resultados y C4 anotado en el plan de pruebas; salida de `prueba-appliance.sh`.
