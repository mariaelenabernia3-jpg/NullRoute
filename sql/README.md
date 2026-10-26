# Migración 001 · Cofre Básico + Varita de Venta x1

Archivo SQL: `2026-10-26_001_cofre_basico_y_varita.sql`

## Cómo aplicarla

1. Entra en Supabase → **SQL Editor**.
2. Abre el archivo `sql/2026-10-26_001_cofre_basico_y_varita.sql`.
3. Pega **todo** el contenido y pulsa **Run**.
4. Ejecuta las consultas del bloque **18. VERIFICACIÓN** que están al final del archivo.

La migración es idempotente y está envuelta en `BEGIN/COMMIT`. No borra
tablas, filas ni funciones existentes.

## Qué cambia

### Columnas nuevas en `galaxy_players`
- `wand_unlocked boolean` → desbloqueo permanente del x1.
- `sales_multiplier numeric` → 0 sin varita, 1 con x1.

### Tablas nuevas
- `galaxy_chest_rewards`: configuración de la recompensa extra del Cofre Básico.
- `galaxy_chest_opens`: registro idempotente por `request_id`.
- `galaxy_player_wands`: varitas físicas del jugador (stack por jugador).
- `galaxy_wand_listings`: publicaciones de varitas en el mercado.

### RPC nuevas
- `galaxy_assert_session(uuid, text)`
- `galaxy_grant_wand(uuid, integer)`
- `galaxy_chest_rewards_get(text)`
- `galaxy_open_chest_v2(uuid, integer, text, uuid)`
- `galaxy_wand_status(uuid, text)`
- `galaxy_wand_inventory_get(uuid, text)`
- `galaxy_wand_list(uuid, text, uuid, text, numeric)`
- `galaxy_wand_cancel(uuid, text, uuid)`
- `galaxy_wand_buy(uuid, text, uuid)`
- `galaxy_wand_shop_listings(uuid, text, uuid)`
- `galaxy_sell_warehouse_v2(uuid, text)`
- `galaxy_sell_warehouse_item_v2(uuid, integer, text, text)`
- `galaxy_sell_generator_v2(uuid, uuid, text)`

### Permisos
Las RPC antiguas `galaxy_open_chest`, `galaxy_sell_warehouse`,
`galaxy_sell_warehouse_item` y `galaxy_sell_generator` pierden EXECUTE para
`anon`/`authenticated`. Las versiones `_v2` las llaman internamente como
`SECURITY DEFINER`. Si necesitas revertirlo, usa el bloque de rollback.

## Probabilidades de la recompensa extra

Se definen en `galaxy_chest_rewards` y suman 100. Son probabilidades nuevas,
configurables por el propietario:

| Recompensa | Peso | % |
|---|---:|---:|
| 150.000 Orbes | 12 | 12% |
| 350.000 Orbes | 9 | 9% |
| 550.000 Orbes | 6 | 6% |
| 100.000 Créditos | 12 | 12% |
| 250.000 Créditos | 9 | 9% |
| 500.000 Créditos | 6 | 6% |
| Varita de Venta x1 | 2 | 2% |
| 2 Llaves Comunes | 18 | 18% |
| 1 Llave Básica | 19 | 19% |
| +2 Espacios de Mercado | 7 | 7% |

El Cofre Básico conserva sus recompensas actuales (1.500–3.500 CR y
3.000–6.000 PL) y añade **exactamente una** recompensa extra de la tabla.

## Fórmula de venta

Los wrappers de almacén y generador calculan:

```
bonus = round(importe_base * (multiplicador - 1), 2)
total = importe_base + bonus
```

Con `sales_multiplier = 1` el bonus es `0`: se paga el importe base una sola
vez, sin duplicar. Si en el futuro se sube a x2, el wrapper añade solo el
bonus adicional. La granja (`galaxy_farm_sell`) no pasa por estos wrappers.

## Verificación rápida en la interfaz

1. Abre un Cofre Básico y comprueba el toast con la recompensa.
2. Si sale la varita, el HUD debe mostrar `🪄 x1`.
3. Recarga la página o entra desde otro dispositivo: el `x1` debe seguir.
4. En `inventario.html` debe aparecer la sección **VARITAS DE VENTA**.
5. Publica una varita y compruébala en `tienda.html`.
6. Vende en `almacen.html` o `generadores.html`: el importe debe ser el base,
   sin doble pago.
7. La granja debe seguir funcionando igual.

## Rollback

Al final del archivo SQL hay un bloque comentado con los `GRANT` y `DROP`
necesarios. No lo ejecutes salvo que quieras deshacer la migración.

## Nota de despliegue

Esta migración **no se ha aplicado** a la base de datos de producción desde
este entorno porque no se dispone de la clave administrativa/service role de
Supabase. El propietario debe ejecutarla manualmente en el SQL Editor.

Los usuarios con una sesión antigua guardada sin `session_hash` serán
redirigidos una vez al login para obtener una sesión válida.
