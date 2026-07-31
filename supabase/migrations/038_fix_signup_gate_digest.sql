-- ============================================================
-- 038_fix_signup_gate_digest.sql — fix broken invite gate
--
-- Migration 037 called digest()/pgcrypto to hash the invite token,
-- but pinned the function to `search_path = public`. On Supabase
-- pgcrypto lives in the `extensions` schema, so `digest` was not
-- resolvable — the trigger threw "function digest(...) does not
-- exist" on EVERY auth.users insert, surfacing as the generic
-- "Database error saving new user" ({}). That blocked all signups,
-- including valid invite links and dashboard-created users.
--
-- Fix:
--   1. Schema-qualify the call as `extensions.digest(...)`.
--   2. Widen search_path to `public, extensions` as a belt-and-
--      braces guard for any other extension helper.
--   3. Wrap the invite check in its own BEGIN/EXCEPTION so that an
--      unexpected error in the gate can never again hard-fail the
--      whole signup with an opaque message — a lookup error is
--      treated as "not a valid invite" and rejected cleanly.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_full_name TEXT;
  v_account_id UUID;
  v_token TEXT;
  v_token_hash TEXT;
  v_valid_invite BOOLEAN := FALSE;
BEGIN
  -- ----------------------------------------------------------
  -- Invitation gate (skipped only while the install is empty).
  -- ----------------------------------------------------------
  IF EXISTS (SELECT 1 FROM public.accounts) THEN
    v_token := NEW.raw_user_meta_data->>'invite_token';

    IF v_token IS NOT NULL THEN
      BEGIN
        v_token_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');

        SELECT TRUE INTO v_valid_invite
        FROM public.account_invitations
        WHERE token_hash = v_token_hash
          AND accepted_at IS NULL
          AND expires_at > NOW()
        LIMIT 1;
      EXCEPTION WHEN OTHERS THEN
        -- Any failure hashing or looking up the token is treated
        -- as an invalid invite rather than crashing the signup.
        RAISE WARNING 'Invite validation failed for user %: %', NEW.id, SQLERRM;
        v_valid_invite := FALSE;
      END;
    END IF;

    IF NOT COALESCE(v_valid_invite, FALSE) THEN
      RAISE EXCEPTION
        'Signup is by invitation only. Ask an administrator for an invite link.';
    END IF;
  END IF;

  -- ----------------------------------------------------------
  -- Bootstrap account + profile. Failures here are only warned,
  -- so a validated signup still succeeds.
  -- ----------------------------------------------------------
  BEGIN
    v_full_name := COALESCE(NEW.raw_user_meta_data->>'full_name', '');

    INSERT INTO public.accounts (name, owner_user_id)
    VALUES (COALESCE(NULLIF(v_full_name, ''), NEW.email, 'My account'), NEW.id)
    RETURNING id INTO v_account_id;

    INSERT INTO public.profiles (user_id, full_name, email, account_id, account_role)
    VALUES (NEW.id, v_full_name, NEW.email, v_account_id, 'owner');
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Failed to bootstrap account/profile for user %: %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;

ALTER FUNCTION public.handle_new_user() OWNER TO postgres;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
