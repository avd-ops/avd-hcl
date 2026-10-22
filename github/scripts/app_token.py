#!/usr/bin/env python3
# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), assistant/pipeline.py; see CREDITS.md.
"""Mint a short-lived GitHub App installation token with a key that never leaves Key Vault.

Changes from the source: a command-line script for the drift workflow and Cloud Shell, Azure tokens from the az CLI
instead of azure-identity, and the permissions passed in.

The App's private key is a non-exportable, sign-only Key Vault key tagged with the App's client ID.
Key Vault signs a 9-minute JWT; GitHub exchanges it for a one-hour token scoped to one repository
and the permissions asked for. The token is printed on stdout and nothing else is: callers mask it
(::add-mask::) and pass it to one process as GITHUB_TOKEN. Standard library only.

Usage:
  app_token.py --key-url https://<vault>.vault.azure.net/keys/<name> --repository <owner>/<repo> \\
               --permission administration=read --permission issues=read
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

GITHUB_API = "https://api.github.com"
KEY_VAULT_API = "7.4"
TIMEOUT = 30


class TokenError(Exception):
    """A failure the operator can act on; the message never holds a credential."""


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def signing_input(client_id: str, now: int) -> str:
    """The JWT's header and claims: issued a minute back for clock skew, valid 9 minutes."""
    header = b64url(json.dumps({"alg": "RS256", "typ": "JWT"}, separators=(",", ":")).encode())
    claims = b64url(json.dumps({"iat": now - 60, "exp": now + 540, "iss": client_id},
                               separators=(",", ":")).encode())
    return f"{header}.{claims}"


def parse_permissions(pairs: list[str]) -> dict:
    allowed = {"read", "write"}
    out = {}
    for pair in pairs:
        name, _, level = pair.partition("=")
        if not name or level not in allowed:
            raise TokenError(f"--permission takes name=read or name=write, not {pair!r}.")
        out[name] = level
    if not out:
        raise TokenError("Ask for at least one --permission; a token is scoped to what it needs.")
    return out


def az_token() -> str:
    """A Key Vault access token for whoever az is signed in as (OIDC in Actions, you in Cloud Shell)."""
    try:
        result = subprocess.run(
            ["az", "account", "get-access-token", "--resource", "https://vault.azure.net",
             "--query", "accessToken", "--output", "tsv"],
            capture_output=True, text=True, timeout=60, check=False)
    except FileNotFoundError as exc:
        raise TokenError("The az CLI isn't installed here.") from exc
    if result.returncode != 0 or not result.stdout.strip():
        raise TokenError("az couldn't get a Key Vault token: " + result.stderr.strip()[:500])
    return result.stdout.strip()


class Client:
    def __init__(self, opener=None, token_source=az_token):
        self._open = opener or urllib.request.urlopen
        self._token_source = token_source

    def request(self, method: str, url: str, headers: dict, body: dict | None = None) -> tuple[int, dict]:
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        host = urllib.parse.urlsplit(url).netloc
        try:
            with self._open(req, timeout=TIMEOUT) as resp:
                status, raw = resp.status, resp.read()
        except urllib.error.HTTPError as err:
            status, raw = err.code, err.read()
        except (urllib.error.URLError, OSError) as err:
            # DNS, proxy, connection reset or timeout: report the step, never a traceback.
            raise TokenError(f"{method} {host} failed before a response: {err}") from err
        try:
            return status, json.loads(raw or b"{}")
        except ValueError:
            return status, {"message": raw[:300].decode(errors="replace")}

    def _vault_headers(self) -> dict:
        return {"Authorization": f"Bearer {self._token_source()}", "Content-Type": "application/json"}

    def app_jwt(self, key_url: str, now: int | None = None) -> str:
        headers = self._vault_headers()
        status, key = self.request("GET", f"{key_url}?api-version={KEY_VAULT_API}", headers)
        if status != 200:
            raise TokenError(f"Couldn't read the App key's tags from Key Vault (HTTP {status}: "
                             f"{key.get('error', {}).get('code', key.get('message', ''))}).")
        client_id = (key.get("tags") or {}).get("client_id")
        if not client_id:
            raise TokenError("The Key Vault key has no client_id tag; tag it with the App's client ID.")
        # Sign with the current version's kid: Key Vault's sign operation is /keys/{name}/{version}/sign.
        kid = (key.get("key") or {}).get("kid")
        if not kid:
            raise TokenError("Key Vault returned the key without its kid.")
        unsigned = signing_input(client_id, int(time.time()) if now is None else now)
        digest = b64url(hashlib.sha256(unsigned.encode()).digest())
        status, signed = self.request("POST", f"{kid}/sign?api-version={KEY_VAULT_API}", headers,
                                      {"alg": "RS256", "value": digest})
        if status != 200 or "value" not in signed:
            raise TokenError(f"Key Vault wouldn't sign (HTTP {status}: "
                             f"{signed.get('error', {}).get('code', signed.get('message', ''))}). "
                             "Check the Key Vault Crypto User role on this key.")
        return f"{unsigned}.{signed['value']}"

    def installation_token(self, key_url: str, repository: str, permissions: dict) -> str:
        jwt = self.app_jwt(key_url)
        headers = {"Authorization": f"Bearer {jwt}", "Accept": "application/vnd.github+json",
                   "X-GitHub-Api-Version": "2022-11-28"}
        status, inst = self.request("GET", f"{GITHUB_API}/repos/{repository}/installation", headers)
        if status != 200:
            raise TokenError(f"The App isn't installed on {repository} (HTTP {status}: {inst.get('message', '')}).")
        # Scoped down to this one repository and the permissions asked for, whatever the App holds.
        status, tok = self.request("POST", f"{GITHUB_API}/app/installations/{inst['id']}/access_tokens", headers,
                                   {"repositories": [repository.split("/", 1)[1]], "permissions": permissions})
        if status != 201 or "token" not in tok:
            raise TokenError(f"GitHub wouldn't issue a token (HTTP {status}: {tok.get('message', '')}). "
                             "Check the App has the permissions asked for.")
        return tok["token"]


def main(argv: list[str] | None = None, client: Client | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--key-url", required=True, help="https://<vault>.vault.azure.net/keys/<name>")
    parser.add_argument("--repository", required=True, help="owner/repo")
    parser.add_argument("--permission", action="append", default=[], help="name=read or name=write; repeat")
    args = parser.parse_args(argv)
    if "/" not in args.repository or not args.key_url.startswith("https://"):
        print("error: --repository is owner/repo and --key-url is an https Key Vault key URL.", file=sys.stderr)
        return 2
    try:
        token = (client or Client()).installation_token(
            args.key_url.rstrip("/"), args.repository, parse_permissions(args.permission))
    except TokenError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1
    print(token)
    return 0


if __name__ == "__main__":
    sys.exit(main())
