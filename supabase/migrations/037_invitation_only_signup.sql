-- ============================================================
-- 037_invitation_only_signup.sql — closed signup
--
-- Problem: any visitor (or any direct call to the Supabase auth
-- API with the public key) could sign up and receive a fresh
-- workspace as its owner, invisible to the operating team.
--
-- Fix: `handle_new_user` now rejects signups unless the new user
-- presents a valid invite token in `raw_user_meta_data.invite_token`
-- (the /signup page forwards the token from /join/<token> links).
-- Raising inside this AFTER INSERT trigger aborts the auth.users
-- insert, so the rule holds for every entry point — UI or API.
--
-- Bootstrap escape hatch: when NO account exists yet (fresh
-- install), the first signup is allowed without an invite and
-- becomes the owner. Once at least one account exists, every
-- signup must be invited.
--
-- The guard deliberately sits OUTSIDE the exception handler: the
-- original function swallowed all errors so signup always
-- succeeded; the invite check must be allowed to fail the signup.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_full_name TEXT;
  v_account_id UUID;
  v_token TEXT;
BEGIN
  -- ----------------------------------------------------------
  -- Invitation gate (skipped only while the install is empty).
  -- ----------------------------------------------------------
  IF EXISTS (SELECT 1 FROM public.accounts) THEN
    v_token := NEW.raw_user_meta_data->>'invite_token';

    IF v_token IS NULL OR NOT EXISTS (
      SELECT 1
      FROM public.account_invitations
      WHERE token_hash = encode(digest(v_token, 'sha256'), 'hex')
        AND accepted_at IS NULL
        AND expires_at > NOW()
    ) THEN
      RAISE EXCEPTION
        'Signup is by invitation only. Ask an administrator for an invite link.';
    END IF;
  END IF;

  -- ----------------------------------------------------------
  -- Bootstrap account + profile (same behavior as 017: invited
  -- users get a temporary personal account that redeem_invitation
  -- replaces and cleans up). Failures here are only warned, so a
  -- validated signup still succeeds even if bootstrap hiccups.
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
