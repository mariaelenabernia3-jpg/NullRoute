-- ============================================================
-- GALAXYGENS · MIGRACIÓN 001
-- Cofre Básico ampliado + Varita de Venta x1 + espacios de mercado
-- Fecha: 2026-10-26
--
-- Cómo aplicar:
--   1. Abre Supabase > SQL Editor.
--   2. Pega TODO este archivo y pulsa Run.
--   3. Al final, ejecuta las consultas del bloque 18 para verificar.
--
-- Es idempotente: se puede ejecutar más de una vez sin duplicar datos.
-- NO elimina tablas, filas ni funciones existentes.
-- Las varitas se guardan en tablas propias para no tocar el inventario
-- de minerales ni las restricciones internas de galaxy_market_listings.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 0. COLUMNAS NUEVAS EN JUGADORES
-- wand_unlocked: TRUE cuando el jugador desbloqueó el x1 permanente.
-- sales_multiplier: 0 = sin varita, 1 = x1 desbloqueado.
-- El desbloqueo es independiente de las varitas físicas.
-- ------------------------------------------------------------
ALTER TABLE public.galaxy_players
  ADD COLUMN IF NOT EXISTS wand_unlocked boolean NOT NULL DEFAULT false;

ALTER TABLE public.galaxy_players
  ADD COLUMN IF NOT EXISTS sales_multiplier numeric(18,6) NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.galaxy_players.wand_unlocked IS
  'TRUE cuando el jugador ya desbloqueó permanentemente el multiplicador de ventas x1.';
COMMENT ON COLUMN public.galaxy_players.sales_multiplier IS
  'Multiplicador de ventas desbloqueado: 0 = ninguno, 1 = x1. No se pierde al vender varitas duplicadas.';

-- ------------------------------------------------------------
-- 1. CONFIGURACIÓN DE RECOMPENSAS EXTRA DEL COFRE BÁSICO
-- Estas probabilidades son NUEVAS y configurables. No existían antes.
-- El cofre básico conserva sus dos recompensas actuales:
--   * 1.500–3.500 CR
--   * 3.000–6.000 PL
-- Además, entrega EXACTAMENTE UNA recompensa extra de esta tabla.
-- Total de pesos = 100.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.galaxy_chest_rewards (
  id bigserial PRIMARY KEY,
  chest_kind text NOT NULL,
  reward_kind text NOT NULL,
  amount numeric NOT NULL DEFAULT 0,
  label text NOT NULL,
  weight integer NOT NULL CHECK (weight > 0),
  enabled boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT galaxy_chest_rewards_unique UNIQUE (chest_kind, reward_kind, amount)
);

INSERT INTO public.galaxy_chest_rewards
  (chest_kind, reward_kind, amount, label, weight, enabled, sort_order)
VALUES
  ('basico', 'orb',          150000, '150.000 Orbes',            12, true, 10),
  ('basico', 'orb',          350000, '350.000 Orbes',             9, true, 20),
  ('basico', 'orb',          550000, '550.000 Orbes',             6, true, 30),
  ('basico', 'credits',      100000, '100.000 Créditos',         12, true, 40),
  ('basico', 'credits',      250000, '250.000 Créditos',          9, true, 50),
  ('basico', 'credits',      500000, '500.000 Créditos',          6, true, 60),
  ('basico', 'wand',              1, 'Varita de Venta x1',        2, true, 70),
  ('basico', 'key_comun',         2, '2 Llaves Comunes',         18, true, 80),
  ('basico', 'key_basico',        1, '1 Llave Básica',           19, true, 90),
  ('basico', 'market_slots',      2, '2 Espacios de Mercado',     7, true, 100)
ON CONFLICT (chest_kind, reward_kind, amount) DO NOTHING;

-- ------------------------------------------------------------
-- 2. REGISTRO IDEMPOTENTE DE APERTURAS
-- Evita que un reintento con el mismo request_id cobre dos veces
-- o entregue dos veces la recompensa.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.galaxy_chest_opens (
  request_id uuid NOT NULL,
  user_id uuid NOT NULL,
  chest integer NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, request_id)
);

CREATE INDEX IF NOT EXISTS galaxy_chest_opens_user_idx
  ON public.galaxy_chest_opens (user_id, created_at DESC);

-- ------------------------------------------------------------
-- 3. INVENTARIO DE VARITAS
-- Una fila por jugador (stack). El desbloqueo permanente vive en
-- galaxy_players.wand_unlocked y NO se toca al vender una varita.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.galaxy_player_wands (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL,
  qty integer NOT NULL DEFAULT 1 CHECK (qty > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT galaxy_player_wands_owner_unique UNIQUE (owner_id)
);

COMMENT ON TABLE public.galaxy_player_wands IS
  'Varitas físicas del jugador. La primera desbloquea x1; las demás son objetos vendibles.';

-- ------------------------------------------------------------
-- 4. PUBLICACIONES DE VARITAS EN EL MERCADO
-- Tabla propia para no alterar galaxy_market_listings ni sus CHECK.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.galaxy_wand_listings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id uuid NOT NULL,
  seller_name text,
  shop_id uuid NOT NULL,
  quantity integer NOT NULL DEFAULT 1 CHECK (quantity > 0),
  price_amount numeric NOT NULL CHECK (price_amount > 0),
  price_currency text NOT NULL CHECK (price_currency IN ('credits', 'plasma', 'supernova')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'sold', 'cancelled')),
  buyer_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  sold_at timestamptz
);

CREATE INDEX IF NOT EXISTS galaxy_wand_listings_shop_idx
  ON public.galaxy_wand_listings (shop_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS galaxy_wand_listings_seller_idx
  ON public.galaxy_wand_listings (seller_id, status);

-- ------------------------------------------------------------
-- 5. RLS Y PERMISOS DE LAS TABLAS NUEVAS
-- Sin políticas: solo las funciones SECURITY DEFINER pueden leerlas
-- o escribir en ellas. El cliente nunca las consulta directamente.
-- ------------------------------------------------------------
ALTER TABLE public.galaxy_chest_rewards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.galaxy_chest_opens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.galaxy_player_wands ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.galaxy_wand_listings ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.galaxy_chest_rewards FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.galaxy_chest_opens FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.galaxy_player_wands FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.galaxy_wand_listings FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.galaxy_chest_rewards_id_seq FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- 6. VALIDACIÓN DE SESIÓN
-- Usa la tabla real galaxy_sessions (user_id, session_hash, expires_at).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.galaxy_assert_session(
  p_user_id uuid,
  p_session_hash text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL OR p_session_hash IS NULL OR btrim(p_session_hash) = '' THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.galaxy_sessions s
    WHERE s.user_id = p_user_id
      AND s.session_hash = p_session_hash
      AND (s.expires_at IS NULL OR s.expires_at > now())
  );
END;
$$;

REVOKE ALL ON FUNCTION public.galaxy_assert_session(uuid, text) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- 7. ENTREGA DE VARITA FÍSICA + DESBLOQUEO PERMANENTE
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.galaxy_grant_wand(
  p_user_id uuid,
  p_qty integer DEFAULT 1
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_qty integer := GREATEST(COALESCE(p_qty, 1), 1);
BEGIN
  INSERT INTO public.galaxy_player_wands (owner_id, qty)
  VALUES (p_user_id, v_qty)
  ON CONFLICT (owner_id) DO UPDATE
    SET qty = public.galaxy_player_wands.qty + EXCLUDED.qty,
        updated_at = now();

  UPDATE public.galaxy_players
     SET wand_unlocked = true,
         sales_multiplier = GREATEST(COALESCE(sales_multiplier, 0), 1)
   WHERE id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.galaxy_grant_wand(uuid, integer) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- 8. CONSULTA PÚBLICA DE PROBABILIDADES CONFIGURADAS
-- La UI del Lobby usa esto para no mostrar porcentajes inventados.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.galaxy_chest_rewards_get(
  p_chest_kind text DEFAULT 'basico'
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH base AS (
    SELECT
      r.*,
      sum(r.weight) OVER () AS total_weight
    FROM public.galaxy_chest_rewards r
    WHERE r.chest_kind = p_chest_kind
      AND r.enabled = true
  )
  SELECT jsonb_build_object(
    'success', true,
    'chest_kind', p_chest_kind,
    'total_weight', COALESCE(max(total_weight), 0),
    'rewards', COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'reward_kind', reward_kind,
          'amount', amount,
          'label', label,
          'weight', weight,
          'chance_pct', CASE
            WHEN COALESCE(total_weight, 0) = 0 THEN 0
            ELSE round(weight * 100.0 / total_weight, 2)
          END
        )
        ORDER BY sort_order, id
      ),
      '[]'::jsonb
    )
  )
  FROM base;
$$;

GRANT EXECUTE ON FUNCTION public.galaxy_chest_rewards_get(text) TO anon, authenticated;

-- ------------------------------------------------------------
-- 9. APERTURA DEL COFRE BÁSICO v2
-- Para cofres distintos del básico (índice 1) delega en la función
-- original existente. Para el básico implementa:
--   * 1.500–3.500 CR (existente)
--   * 3.000–6.000 PL (existente)
--   * 1 recompensa extra de galaxy_chest_rewards
-- Consume 1 llave 'basico' y registra request_id para idempotencia.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.galaxy_open_chest_v2(
  p_user_id uuid,
  p_chest integer,
  p_session_hash text,
  p_request_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rid uuid := COALESCE(p_request_id, gen_random_uuid());
  v_existing jsonb;
  v_res jsonb;
  v_fname text;
  v_player_exists boolean;
  v_total_weight integer := 0;
  v_roll numeric;
  v_reward record;
  v_cr_award numeric := 0;
  v_pl_award numeric := 0;
  v_orb_award numeric := 0;
  v_wand_award integer := 0;
  v_key_comun_award integer := 0;
  v_key_basico_award integer := 0;
  v_slots_award integer := 0;
  v_extra jsonb := '{}'::jsonb;
  v_keys jsonb;
  v_user jsonb;
BEGIN
  IF NOT public.galaxy_assert_session(p_user_id, p_session_hash) THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Sesión inválida o expirada');
  END IF;

  SELECT result INTO v_existing
  FROM public.galaxy_chest_opens
  WHERE request_id = v_rid
    AND user_id = p_user_id;

  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_user_id::text)::bigint);

  SELECT result INTO v_existing
  FROM public.galaxy_chest_opens
  WHERE request_id = v_rid
    AND user_id = p_user_id;

  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  -- Cofres distintos del básico: se conserva la función original.
  IF COALESCE(p_chest, 1) <> 1 THEN
    SELECT p.proname INTO v_fname
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname = 'galaxy_open_chest'
      AND p.pronargs = 2
    LIMIT 1;

    IF v_fname IS NULL THEN
      RETURN jsonb_build_object('success', false, 'msg', 'La función original galaxy_open_chest no está disponible');
    END IF;

    EXECUTE format('SELECT public.%I($1, $2)', v_fname)
      INTO v_res
      USING p_user_id, p_chest;

    IF v_res IS NOT NULL AND COALESCE((v_res->>'success')::boolean, false) THEN
      INSERT INTO public.galaxy_chest_opens (request_id, user_id, chest, result)
      VALUES (v_rid, p_user_id, p_chest, v_res)
      ON CONFLICT (user_id, request_id) DO NOTHING;
    END IF;

    RETURN v_res;
  END IF;

  -- Cofre básico: validar jugador y consumir 1 llave básica.
  SELECT EXISTS (SELECT 1 FROM public.galaxy_players WHERE id = p_user_id)
    INTO v_player_exists;

  IF NOT v_player_exists THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Jugador no encontrado');
  END IF;

  WITH target AS (
    SELECT ctid
    FROM public.galaxy_keys
    WHERE owner_id = p_user_id
      AND kind = 'basico'
      AND COALESCE(qty, 0) >= 1
    ORDER BY ctid
    LIMIT 1
    FOR UPDATE
  )
  UPDATE public.galaxy_keys g
     SET qty = g.qty - 1
    FROM target t
   WHERE g.ctid = t.ctid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'msg', 'No tienes ninguna Llave Básica');
  END IF;

  -- Recompensas existentes del cofre básico.
  v_cr_award := 1500 + floor(random() * 2001)::int; -- 1.500 a 3.500
  v_pl_award := 3000 + floor(random() * 3001)::int; -- 3.000 a 6.000

  -- Recompensa extra: exactamente una.
  SELECT COALESCE(sum(weight), 0)
    INTO v_total_weight
  FROM public.galaxy_chest_rewards
  WHERE chest_kind = 'basico'
    AND enabled = true;

  IF v_total_weight > 0 THEN
    v_roll := random() * v_total_weight;

    SELECT *
      INTO v_reward
    FROM (
      SELECT
        r.*,
        sum(r.weight) OVER (ORDER BY r.sort_order, r.id) AS cum
      FROM public.galaxy_chest_rewards r
      WHERE r.chest_kind = 'basico'
        AND r.enabled = true
    ) s
    WHERE s.cum >= v_roll
    ORDER BY s.cum
    LIMIT 1;

    IF v_reward.reward_kind = 'orb' THEN
      v_orb_award := v_reward.amount;
      v_extra := jsonb_build_object('kind', 'orb', 'amount', v_reward.amount, 'label', v_reward.label);

    ELSIF v_reward.reward_kind = 'credits' THEN
      v_cr_award := v_cr_award + v_reward.amount;
      v_extra := jsonb_build_object('kind', 'credits', 'amount', v_reward.amount, 'label', v_reward.label);

    ELSIF v_reward.reward_kind = 'wand' THEN
      PERFORM public.galaxy_grant_wand(p_user_id, 1);
      v_wand_award := 1;
      v_extra := jsonb_build_object('kind', 'wand', 'amount', 1, 'label', v_reward.label);

    ELSIF v_reward.reward_kind = 'key_comun' THEN
      v_key_comun_award := v_reward.amount::int;
      WITH target AS (
        SELECT ctid
        FROM public.galaxy_keys
        WHERE owner_id = p_user_id
          AND kind = 'comun'
        ORDER BY ctid
        LIMIT 1
      )
      UPDATE public.galaxy_keys g
         SET qty = COALESCE(g.qty, 0) + v_key_comun_award
        FROM target t
       WHERE g.ctid = t.ctid;

      IF NOT FOUND THEN
        INSERT INTO public.galaxy_keys (owner_id, kind, qty)
        VALUES (p_user_id, 'comun', v_key_comun_award);
      END IF;

      v_extra := jsonb_build_object('kind', 'key_comun', 'amount', v_key_comun_award, 'label', v_reward.label);

    ELSIF v_reward.reward_kind = 'key_basico' THEN
      v_key_basico_award := v_reward.amount::int;
      WITH target AS (
        SELECT ctid
        FROM public.galaxy_keys
        WHERE owner_id = p_user_id
          AND kind = 'basico'
        ORDER BY ctid
        LIMIT 1
      )
      UPDATE public.galaxy_keys g
         SET qty = COALESCE(g.qty, 0) + v_key_basico_award
        FROM target t
       WHERE g.ctid = t.ctid;

      IF NOT FOUND THEN
        INSERT INTO public.galaxy_keys (owner_id, kind, qty)
        VALUES (p_user_id, 'basico', v_key_basico_award);
      END IF;

      v_extra := jsonb_build_object('kind', 'key_basico', 'amount', v_key_basico_award, 'label', v_reward.label);

    ELSIF v_reward.reward_kind = 'market_slots' THEN
      v_slots_award := v_reward.amount::int;
      v_extra := jsonb_build_object('kind', 'market_slots', 'amount', v_slots_award, 'label', v_reward.label);
    END IF;
  END IF;

  UPDATE public.galaxy_players
     SET credits = COALESCE(credits, 0) + v_cr_award,
         plasma = COALESCE(plasma, 0) + v_pl_award,
         quantum = COALESCE(quantum, 0) + v_orb_award,
         market_slots = COALESCE(market_slots, 0) + v_slots_award
   WHERE id = p_user_id;

  SELECT COALESCE(jsonb_object_agg(kind, total_qty), '{}'::jsonb)
    INTO v_keys
  FROM (
    SELECT kind, sum(COALESCE(qty, 0)) AS total_qty
    FROM public.galaxy_keys
    WHERE owner_id = p_user_id
    GROUP BY kind
  ) k;

  SELECT to_jsonb(p) - 'password_hash' - 'avatar'
    INTO v_user
  FROM public.galaxy_players p
  WHERE p.id = p_user_id;

  v_res := jsonb_build_object(
    'success', true,
    'chest', 1,
    'reward', jsonb_build_object(
      'cr', v_cr_award,
      'pl', v_pl_award,
      'ec', v_orb_award,
      'ns', 0,
      'wand', v_wand_award,
      'key_comun', v_key_comun_award,
      'key_basico', v_key_basico_award,
      'market_slots', v_slots_award,
      'extra', v_extra
    ),
    'keys', v_keys,
    'user', v_user
  );

  INSERT INTO public.galaxy_chest_opens (request_id, user_id, chest, result)
  VALUES (v_rid, p_user_id, 1, v_res)
  ON CONFLICT (user_id, request_id) DO NOTHING;

  RETURN v_res;

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'msg', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.galaxy_open_chest_v2(uuid, integer, text, uuid) TO anon, authenticated;

-- ------------------------------------------------------------
-- 10. ESTADO DE LA VARITA
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.galaxy_wand_status(
  p_user_id uuid,
  p_session_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_unlocked boolean := false;
  v_mult numeric := 0;
  v_count numeric := 0;
BEGIN
  IF NOT public.galaxy_assert_session(p_user_id, p_session_hash) THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Sesión inválida o expirada');
  END IF;

  SELECT COALESCE(wand_unlocked, false), COALESCE(sales_multiplier, 0)
    INTO v_unlocked, v_mult
  FROM public.galaxy_players
  WHERE id = p_user_id;

  SELECT COALESCE(sum(qty), 0)
    INTO v_count
  FROM public.galaxy_player_wands
  WHERE owner_id = p_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'wand_unlocked', COALESCE(v_unlocked, false),
    'sales_multiplier', CASE WHEN COALESCE(v_unlocked, false) THEN GREATEST(COALESCE(v_mult, 0), 1) ELSE COALESCE(v_mult, 0) END,
    'wand_count', COALESCE(v_count, 0)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.galaxy_wand_status(uuid, text) TO anon, authenticated;

-- ------------------------------------------------------------
-- 11. INVENTARIO DE VARITAS
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.galaxy_wand_inventory_get(
  p_user_id uuid,
  p_session_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count numeric := 0;
  v_items jsonb := '[]'::jsonb;
BEGIN
  IF NOT public.galaxy_assert_session(p_user_id, p_session_hash) THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Sesión inválida o expirada');
  END IF;

  SELECT
    COALESCE(sum(qty), 0),
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', id,
          'item_name', 'Varita de Venta x1',
          'level', 1,
          'rarity', 'special',
          'qty', qty,
          'unit_val', 0
        )
        ORDER BY updated_at DESC, id
      ),
      '[]'::jsonb
    )
    INTO v_count, v_items
  FROM public.galaxy_player_wands
  WHERE owner_id = p_user_id
    AND qty > 0;

  RETURN jsonb_build_object(
    'success', true,
    'count', v_count,
    'wands', v_items
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.galaxy_wand_inventory_get(uuid, text) TO anon, authenticated;

-- ------------------------------------------------------------
-- 12. PUBLICAR VARITA EN EL MERCADO
-- Consume 1 varita física. No toca el desbloqueo permanente.
-- Valida sesión, planeta, tienda, precio y capacidad de mercado.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.galaxy_wand_list(
  p_user_id uuid,
  p_session_hash text,
  p_shop_id uuid,
  p_currency text,
  p_unit_price numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shop public.galaxy_shops%ROWTYPE;
  v_player public.galaxy_players%ROWTYPE;
  v_planet_id uuid;
  v_wand public.galaxy_player_wands%ROWTYPE;
  v_listing_id uuid;
  v_count numeric := 0;
  v_slots_max numeric := 1;
  v_slots_used integer := 0;
  v_wand_used integer := 0;
BEGIN
  IF NOT public.galaxy_assert_session(p_user_id, p_session_hash) THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Sesión inválida o expirada');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_user_id::text)::bigint);

  IF p_shop_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Tienda no indicada');
  END IF;

  IF p_currency NOT IN ('credits', 'plasma', 'supernova') THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Moneda no válida');
  END IF;

  IF p_unit_price IS NULL OR p_unit_price <= 0 THEN
    RETURN jsonb_build_object('success', false, 'msg', 'El precio debe ser mayor que 0');
  END IF;

  SELECT * INTO v_shop FROM public.galaxy_shops WHERE id = p_shop_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'msg', 'La tienda no existe');
  END IF;

  SELECT p.id
    INTO v_planet_id
  FROM public.galaxy_planets p
  JOIN public.galaxy_players pl ON pl.joined_planet_code = p.code
  WHERE pl.id = p_user_id
  LIMIT 1;

  IF v_planet_id IS NULL OR v_planet_id <> v_shop.planet_id THEN
    RETURN jsonb_build_object('success', false, 'msg', 'No perteneces al planeta de esta tienda');
  END IF;

  SELECT * INTO v_player FROM public.galaxy_players WHERE id = p_user_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Jugador no encontrado');
  END IF;

  -- Capacidad: publicaciones activas existentes + varitas activas.
  v_slots_max := GREATEST(COALESCE(v_player.market_slots, 1), 1);

  SELECT count(*)
    INTO v_slots_used
  FROM public.galaxy_market_listings
  WHERE seller_id = p_user_id
    AND COALESCE(quantity, 0) > 0
    AND COALESCE(status, '') NOT IN ('cancelled', 'empty', 'sold');

  SELECT count(*)
    INTO v_wand_used
  FROM public.galaxy_wand_listings
  WHERE seller_id = p_user_id
    AND status = 'active';

  IF v_slots_used + v_wand_used >= v_slots_max THEN
    RETURN jsonb_build_object(
      'success', false,
      'msg', format('No tienes espacios de mercado disponibles (%s/%s)', v_slots_used + v_wand_used, v_slots_max)
    );
  END IF;

  SELECT *
    INTO v_wand
  FROM public.galaxy_player_wands
  WHERE owner_id = p_user_id
    AND qty >= 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'msg', 'No tienes ninguna Varita de Venta x1');
  END IF;

  IF v_wand.qty <= 1 THEN
    DELETE FROM public.galaxy_player_wands
     WHERE id = v_wand.id;
  ELSE
    UPDATE public.galaxy_player_wands
       SET qty = qty - 1,
           updated_at = now()
     WHERE id = v_wand.id;
  END IF;

  INSERT INTO public.galaxy_wand_listings
    (seller_id, seller_name, shop_id, quantity, price_amount, price_currency, status)
  VALUES
    (p_user_id, v_player.username, p_shop_id, 1, p_unit_price, p_currency, 'active')
  RETURNING id INTO v_listing_id;

  SELECT COALESCE(sum(qty), 0)
    INTO v_count
  FROM public.galaxy_player_wands
  WHERE owner_id = p_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'msg', 'Varita publicada en el mercado',
    'listing_id', v_listing_id,
    'wand_count', v_count
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'msg', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.galaxy_wand_list(uuid, text, uuid, text, numeric) TO anon, authenticated;

-- ------------------------------------------------------------
-- 13. CANCELAR PUBLICACIÓN DE VARITA
-- Devuelve la varita física. El desbloqueo x1 no se toca.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.galaxy_wand_cancel(
  p_user_id uuid,
  p_session_hash text,
  p_listing_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_listing public.galaxy_wand_listings%ROWTYPE;
BEGIN
  IF NOT public.galaxy_assert_session(p_user_id, p_session_hash) THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Sesión inválida o expirada');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_user_id::text)::bigint);

  SELECT *
    INTO v_listing
  FROM public.galaxy_wand_listings
  WHERE id = p_listing_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Publicación no encontrada');
  END IF;

  IF v_listing.seller_id <> p_user_id THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Esa varita no es tuya');
  END IF;

  IF v_listing.status <> 'active' THEN
    RETURN jsonb_build_object('success', false, 'msg', 'La publicación ya no está activa');
  END IF;

  UPDATE public.galaxy_wand_listings
     SET status = 'cancelled'
   WHERE id = p_listing_id;

  PERFORM public.galaxy_grant_wand(p_user_id, v_listing.quantity);

  RETURN jsonb_build_object('success', true, 'msg', 'Varita retirada y devuelta a tu inventario');
END;
$$;

GRANT EXECUTE ON FUNCTION public.galaxy_wand_cancel(uuid, text, uuid) TO anon, authenticated;

-- ------------------------------------------------------------
-- 14. COMPRAR VARITA
-- Cobra al comprador, paga al vendedor y entrega la varita física.
-- Si el comprador ya tenía x1, el multiplicador sigue siendo x1.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.galaxy_wand_buy(
  p_user_id uuid,
  p_session_hash text,
  p_listing_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_listing public.galaxy_wand_listings%ROWTYPE;
  v_price numeric;
BEGIN
  IF NOT public.galaxy_assert_session(p_user_id, p_session_hash) THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Sesión inválida o expirada');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_user_id::text)::bigint);

  SELECT *
    INTO v_listing
  FROM public.galaxy_wand_listings
  WHERE id = p_listing_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Publicación no encontrada');
  END IF;

  IF v_listing.status <> 'active' OR COALESCE(v_listing.quantity, 0) < 1 THEN
    RETURN jsonb_build_object('success', false, 'msg', 'La varita ya no está disponible');
  END IF;

  IF v_listing.seller_id = p_user_id THEN
    RETURN jsonb_build_object('success', false, 'msg', 'No puedes comprar tu propia varita');
  END IF;

  v_price := COALESCE(v_listing.price_amount, 0);
  IF v_price <= 0 THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Precio inválido');
  END IF;

  IF v_listing.price_currency = 'credits' THEN
    UPDATE public.galaxy_players
       SET credits = COALESCE(credits, 0) - v_price
     WHERE id = p_user_id AND COALESCE(credits, 0) >= v_price;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'msg', 'Créditos insuficientes');
    END IF;
    UPDATE public.galaxy_players SET credits = COALESCE(credits, 0) + v_price WHERE id = v_listing.seller_id;

  ELSIF v_listing.price_currency = 'plasma' THEN
    UPDATE public.galaxy_players
       SET plasma = COALESCE(plasma, 0) - v_price
     WHERE id = p_user_id AND COALESCE(plasma, 0) >= v_price;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'msg', 'Plasma insuficiente');
    END IF;
    UPDATE public.galaxy_players SET plasma = COALESCE(plasma, 0) + v_price WHERE id = v_listing.seller_id;

  ELSIF v_listing.price_currency = 'supernova' THEN
    UPDATE public.galaxy_players
       SET supernova = COALESCE(supernova, 0) - v_price
     WHERE id = p_user_id AND COALESCE(supernova, 0) >= v_price;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'msg', 'Supernova insuficiente');
    END IF;
    UPDATE public.galaxy_players SET supernova = COALESCE(supernova, 0) + v_price WHERE id = v_listing.seller_id;

  ELSE
    RETURN jsonb_build_object('success', false, 'msg', 'Moneda no válida');
  END IF;

  UPDATE public.galaxy_wand_listings
     SET status = 'sold',
         buyer_id = p_user_id,
         sold_at = now()
   WHERE id = p_listing_id;

  PERFORM public.galaxy_grant_wand(p_user_id, v_listing.quantity);

  RETURN jsonb_build_object('success', true, 'msg', 'Varita comprada y añadida a tu inventario');
END;
$$;

GRANT EXECUTE ON FUNCTION public.galaxy_wand_buy(uuid, text, uuid) TO anon, authenticated;

-- ------------------------------------------------------------
-- 15. LISTADO DE VARITAS ACTIVAS DE UNA TIENDA
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.galaxy_wand_shop_listings(
  p_user_id uuid,
  p_session_hash text,
  p_shop_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_items jsonb := '[]'::jsonb;
BEGIN
  IF NOT public.galaxy_assert_session(p_user_id, p_session_hash) THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Sesión inválida o expirada');
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', l.id,
        'item_type', 'wand',
        'item_name', 'Varita de Venta x1',
        'item_rarity', 'special',
        'item_level', 1,
        'quantity', l.quantity,
        'unit_price', l.price_amount,
        'price_currency', l.price_currency,
        'price_amount', l.price_amount * l.quantity,
        'seller_id', l.seller_id,
        'seller_name', l.seller_name,
        'is_mine', (l.seller_id = p_user_id),
        'status', l.status,
        'created_at', l.created_at
      )
      ORDER BY l.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_items
  FROM public.galaxy_wand_listings l
  WHERE l.shop_id = p_shop_id
    AND l.status = 'active'
    AND COALESCE(l.quantity, 0) > 0;

  RETURN jsonb_build_object('success', true, 'listings', v_items);
END;
$$;

GRANT EXECUTE ON FUNCTION public.galaxy_wand_shop_listings(uuid, text, uuid) TO anon, authenticated;

-- ------------------------------------------------------------
-- 16. ENVOLTORIOS DE VENTA CON MULTIPLICADOR
-- x1 = multiplicador base. Con sales_multiplier = 1 el bono es 0,
-- por lo que NO se paga dos veces. Si en el futuro se sube a x2,
-- el envoltorio añade exactamente el bono adicional.
-- Solo se usan en almacén y generadores; la granja no pasa por aquí.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.galaxy_sell_warehouse_v2(
  p_user_id uuid,
  p_session_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_res jsonb;
  v_fname text;
  v_total numeric := 0;
  v_mult numeric := 1;
  v_bonus numeric := 0;
  v_unlocked boolean := false;
BEGIN
  IF NOT public.galaxy_assert_session(p_user_id, p_session_hash) THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Sesión inválida o expirada');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_user_id::text)::bigint);

  SELECT p.proname INTO v_fname
  FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND p.proname = 'galaxy_sell_warehouse'
    AND p.pronargs = 1
  LIMIT 1;

  IF v_fname IS NULL THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Función galaxy_sell_warehouse no disponible');
  END IF;

  EXECUTE format('SELECT public.%I($1)', v_fname) INTO v_res USING p_user_id;

  IF v_res IS NULL OR NOT COALESCE((v_res->>'success')::boolean, false) THEN
    RETURN v_res;
  END IF;

  SELECT COALESCE(wand_unlocked, false),
         CASE WHEN COALESCE(wand_unlocked, false)
              THEN GREATEST(COALESCE(sales_multiplier, 1), 1)
              ELSE 1
         END
    INTO v_unlocked, v_mult
  FROM public.galaxy_players
  WHERE id = p_user_id;

  v_mult := GREATEST(COALESCE(v_mult, 1), 1);
  v_total := COALESCE((v_res->>'total')::numeric, 0);
  v_bonus := round(v_total * (v_mult - 1), 2);

  IF v_bonus > 0 THEN
    UPDATE public.galaxy_players
       SET credits = COALESCE(credits, 0) + v_bonus
     WHERE id = p_user_id;
  END IF;

  RETURN v_res || jsonb_build_object(
    'total', v_total + v_bonus,
    'multiplier', v_mult,
    'bonus', v_bonus,
    'wand_unlocked', COALESCE(v_unlocked, false)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.galaxy_sell_warehouse_v2(uuid, text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.galaxy_sell_warehouse_item_v2(
  p_user_id uuid,
  p_level integer,
  p_rarity text,
  p_session_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_res jsonb;
  v_fname text;
  v_total numeric := 0;
  v_mult numeric := 1;
  v_bonus numeric := 0;
  v_unlocked boolean := false;
BEGIN
  IF NOT public.galaxy_assert_session(p_user_id, p_session_hash) THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Sesión inválida o expirada');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_user_id::text)::bigint);

  SELECT p.proname INTO v_fname
  FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND p.proname = 'galaxy_sell_warehouse_item'
    AND p.pronargs = 3
  LIMIT 1;

  IF v_fname IS NULL THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Función galaxy_sell_warehouse_item no disponible');
  END IF;

  EXECUTE format('SELECT public.%I($1, $2, $3)', v_fname) INTO v_res USING p_user_id, p_level, p_rarity;

  IF v_res IS NULL OR NOT COALESCE((v_res->>'success')::boolean, false) THEN
    RETURN v_res;
  END IF;

  SELECT COALESCE(wand_unlocked, false),
         CASE WHEN COALESCE(wand_unlocked, false)
              THEN GREATEST(COALESCE(sales_multiplier, 1), 1)
              ELSE 1
         END
    INTO v_unlocked, v_mult
  FROM public.galaxy_players
  WHERE id = p_user_id;

  v_mult := GREATEST(COALESCE(v_mult, 1), 1);
  v_total := COALESCE((v_res->>'total')::numeric, 0);
  v_bonus := round(v_total * (v_mult - 1), 2);

  IF v_bonus > 0 THEN
    UPDATE public.galaxy_players
       SET credits = COALESCE(credits, 0) + v_bonus
     WHERE id = p_user_id;
  END IF;

  RETURN v_res || jsonb_build_object(
    'total', v_total + v_bonus,
    'multiplier', v_mult,
    'bonus', v_bonus,
    'wand_unlocked', COALESCE(v_unlocked, false)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.galaxy_sell_warehouse_item_v2(uuid, integer, text, text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.galaxy_sell_generator_v2(
  p_user_id uuid,
  p_gen_id uuid,
  p_session_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_res jsonb;
  v_fname text;
  v_value numeric := 0;
  v_mult numeric := 1;
  v_bonus numeric := 0;
  v_unlocked boolean := false;
BEGIN
  IF NOT public.galaxy_assert_session(p_user_id, p_session_hash) THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Sesión inválida o expirada');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_user_id::text)::bigint);

  SELECT p.proname INTO v_fname
  FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND p.proname = 'galaxy_sell_generator'
    AND p.pronargs = 2
  LIMIT 1;

  IF v_fname IS NULL THEN
    RETURN jsonb_build_object('success', false, 'msg', 'Función galaxy_sell_generator no disponible');
  END IF;

  EXECUTE format('SELECT public.%I($1, $2)', v_fname) INTO v_res USING p_user_id, p_gen_id;

  IF v_res IS NULL OR NOT COALESCE((v_res->>'success')::boolean, false) THEN
    RETURN v_res;
  END IF;

  SELECT COALESCE(wand_unlocked, false),
         CASE WHEN COALESCE(wand_unlocked, false)
              THEN GREATEST(COALESCE(sales_multiplier, 1), 1)
              ELSE 1
         END
    INTO v_unlocked, v_mult
  FROM public.galaxy_players
  WHERE id = p_user_id;

  v_mult := GREATEST(COALESCE(v_mult, 1), 1);
  v_value := COALESCE((v_res->>'value')::numeric, 0);
  v_bonus := round(v_value * (v_mult - 1), 2);

  IF v_bonus > 0 THEN
    UPDATE public.galaxy_players
       SET credits = COALESCE(credits, 0) + v_bonus
     WHERE id = p_user_id;
  END IF;

  RETURN v_res || jsonb_build_object(
    'value', v_value + v_bonus,
    'multiplier', v_mult,
    'bonus', v_bonus,
    'wand_unlocked', COALESCE(v_unlocked, false)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.galaxy_sell_generator_v2(uuid, uuid, text) TO anon, authenticated;

-- ------------------------------------------------------------
-- 17. BLOQUEAR LLAMADAS DIRECTAS A LAS RPC ANTIGUAS
-- Las versiones _v2 las siguen usando internamente como SECURITY DEFINER.
-- Si necesitas revertirlo, ejecuta los GRANT del bloque de rollback.
-- ------------------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname IN (
        'galaxy_open_chest',
        'galaxy_sell_warehouse',
        'galaxy_sell_warehouse_item',
        'galaxy_sell_generator'
      )
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', r.sig);

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', r.sig);
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', r.sig);
    END IF;
  END LOOP;
END;
$$;

COMMIT;

-- ============================================================
-- 18. VERIFICACIÓN (ejecutar después del COMMIT)
-- ============================================================
-- Debe devolver 10 filas y peso total 100.
-- SELECT reward_kind, amount, label, weight, enabled
-- FROM public.galaxy_chest_rewards
-- WHERE chest_kind = 'basico'
-- ORDER BY sort_order;
--
-- SELECT sum(weight) AS peso_total
-- FROM public.galaxy_chest_rewards
-- WHERE chest_kind = 'basico' AND enabled;
--
-- Debe devolver las columnas nuevas.
-- SELECT column_name, data_type, column_default
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name = 'galaxy_players'
--   AND column_name IN ('wand_unlocked', 'sales_multiplier');
--
-- Debe devolver las tablas nuevas.
-- SELECT table_name
-- FROM information_schema.tables
-- WHERE table_schema = 'public'
--   AND table_name IN ('galaxy_chest_rewards', 'galaxy_chest_opens',
--                      'galaxy_player_wands', 'galaxy_wand_listings');

-- ============================================================
-- ROLLBACK MANUAL (NO ejecutar salvo que quieras deshacer todo)
-- ============================================================
-- GRANT EXECUTE ON FUNCTION public.galaxy_open_chest(uuid, integer) TO anon, authenticated;
-- GRANT EXECUTE ON FUNCTION public.galaxy_sell_warehouse(uuid) TO anon, authenticated;
-- GRANT EXECUTE ON FUNCTION public.galaxy_sell_warehouse_item(uuid, integer, text) TO anon, authenticated;
-- GRANT EXECUTE ON FUNCTION public.galaxy_sell_generator(uuid, uuid) TO anon, authenticated;
-- DROP FUNCTION IF EXISTS public.galaxy_open_chest_v2(uuid, integer, text, uuid);
-- DROP FUNCTION IF EXISTS public.galaxy_wand_status(uuid, text);
-- DROP FUNCTION IF EXISTS public.galaxy_wand_inventory_get(uuid, text);
-- DROP FUNCTION IF EXISTS public.galaxy_wand_list(uuid, text, uuid, text, numeric);
-- DROP FUNCTION IF EXISTS public.galaxy_wand_cancel(uuid, text, uuid);
-- DROP FUNCTION IF EXISTS public.galaxy_wand_buy(uuid, text, uuid);
-- DROP FUNCTION IF EXISTS public.galaxy_wand_shop_listings(uuid, text, uuid);
-- DROP FUNCTION IF EXISTS public.galaxy_sell_warehouse_v2(uuid, text);
-- DROP FUNCTION IF EXISTS public.galaxy_sell_warehouse_item_v2(uuid, integer, text, text);
-- DROP FUNCTION IF EXISTS public.galaxy_sell_generator_v2(uuid, uuid, text);
-- DROP FUNCTION IF EXISTS public.galaxy_chest_rewards_get(text);
-- DROP FUNCTION IF EXISTS public.galaxy_grant_wand(uuid, integer);
-- DROP FUNCTION IF EXISTS public.galaxy_assert_session(uuid, text);
-- DROP TABLE IF EXISTS public.galaxy_wand_listings;
-- DROP TABLE IF EXISTS public.galaxy_player_wands;
-- DROP TABLE IF EXISTS public.galaxy_chest_opens;
-- DROP TABLE IF EXISTS public.galaxy_chest_rewards;
-- ALTER TABLE public.galaxy_players DROP COLUMN IF EXISTS wand_unlocked;
-- ALTER TABLE public.galaxy_players DROP COLUMN IF EXISTS sales_multiplier;
-- ============================================================
