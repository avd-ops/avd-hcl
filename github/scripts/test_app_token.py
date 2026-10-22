"""Offline tests for app_token.py: a fake Key Vault and a fake GitHub, no network, no az."""

import base64
import hashlib
import io
import json
import os
import sys
import unittest
import urllib.error
from contextlib import redirect_stderr, redirect_stdout

sys.path.insert(0, os.path.dirname(__file__))
import app_token  # noqa: E402

KEY = "https://contoso-kv.vault.azure.net/keys/settings-reader"
KID = KEY + "/0123456789abcdef0123456789abcdef"


class Resp(io.BytesIO):
    def __init__(self, status, body):
        super().__init__(json.dumps(body).encode())
        self.status = status

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class FakeApi:
    def __init__(self, routes):
        self.routes = routes
        self.calls = []

    def __call__(self, req, timeout=None):
        body = json.loads(req.data) if req.data else None
        self.calls.append((req.get_method(), req.full_url, body, dict(req.header_items())))
        status, payload = self.routes[(req.get_method(), req.full_url)]
        if status >= 400:
            raise urllib.error.HTTPError(req.full_url, status, "err", {}, io.BytesIO(json.dumps(payload).encode()))
        return Resp(status, payload)


def routes(over=None):
    base = {
        ("GET", KEY + "?api-version=7.4"): (200, {"key": {"kid": KID}, "tags": {"client_id": "Iv1.example"}}),
        ("POST", KID + "/sign?api-version=7.4"): (200, {"value": "c2lnbmF0dXJl"}),
        ("GET", "https://api.github.com/repos/contoso/kit/installation"): (200, {"id": 42}),
        ("POST", "https://api.github.com/app/installations/42/access_tokens"): (201, {"token": "ghs_example"}),
    }
    base.update(over or {})
    return base


class AppTokenTests(unittest.TestCase):
    def client(self, api):
        return app_token.Client(opener=api, token_source=lambda: "kv-token")

    def test_mints_a_scoped_token(self):
        api = FakeApi(routes())
        token = self.client(api).installation_token(KEY, "contoso/kit", {"administration": "read"})
        self.assertEqual(token, "ghs_example")
        method, url, body, headers = api.calls[-1]
        self.assertEqual(body, {"repositories": ["kit"], "permissions": {"administration": "read"}})
        jwt = api.calls[2][3]["Authorization"].removeprefix("Bearer ")
        claims = json.loads(base64.urlsafe_b64decode(jwt.split(".")[1] + "=="))
        self.assertEqual(claims["iss"], "Iv1.example")
        self.assertEqual(claims["exp"] - claims["iat"], 600)
        self.assertEqual(jwt.split(".")[2], "c2lnbmF0dXJl")

    def test_signs_the_sha256_of_the_signing_input(self):
        api = FakeApi(routes())
        jwt = self.client(api).app_jwt(KEY, now=1_000_000)
        unsigned = jwt.rsplit(".", 1)[0]
        expected = app_token.b64url(hashlib.sha256(unsigned.encode()).digest())
        self.assertEqual(api.calls[1][2], {"alg": "RS256", "value": expected})

    def test_missing_client_id_tag(self):
        api = FakeApi(routes({("GET", KEY + "?api-version=7.4"): (200, {"tags": {}})}))
        with self.assertRaisesRegex(app_token.TokenError, "client_id"):
            self.client(api).app_jwt(KEY)

    def test_sign_refused_reports_status_and_code(self):
        api = FakeApi(routes({("POST", KID + "/sign?api-version=7.4"): (403, {"error": {"code": "Forbidden"}})}))
        with self.assertRaisesRegex(app_token.TokenError, "HTTP 403: Forbidden"):
            self.client(api).app_jwt(KEY)

    def test_signs_with_the_versioned_kid(self):
        api = FakeApi(routes())
        self.client(api).app_jwt(KEY)
        self.assertEqual(api.calls[1][1], KID + "/sign?api-version=7.4")

    def test_network_failure_is_a_token_error(self):
        def down(req, timeout=None):
            raise urllib.error.URLError("proxy refused")
        with self.assertRaisesRegex(app_token.TokenError, "failed before a response"):
            self.client(down).app_jwt(KEY)

    def test_not_installed(self):
        api = FakeApi(routes({("GET", "https://api.github.com/repos/contoso/kit/installation"): (404, {"message": "Not Found"})}))
        with self.assertRaisesRegex(app_token.TokenError, "isn't installed"):
            self.client(api).installation_token(KEY, "contoso/kit", {"issues": "read"})

    def test_permissions_parsing(self):
        self.assertEqual(app_token.parse_permissions(["administration=read", "issues=write"]),
                         {"administration": "read", "issues": "write"})
        for bad in (["administration"], ["issues=admin"], []):
            with self.assertRaises(app_token.TokenError):
                app_token.parse_permissions(bad)

    def test_main_prints_only_the_token(self):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = app_token.main(["--key-url", KEY, "--repository", "contoso/kit",
                                   "--permission", "administration=read"], client=self.client(FakeApi(routes())))
        self.assertEqual((code, out.getvalue()), (0, "ghs_example\n"))

    def test_main_error_never_prints_a_token(self):
        api = FakeApi(routes({("POST", "https://api.github.com/app/installations/42/access_tokens"): (422, {"message": "bad"})}))
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = app_token.main(["--key-url", KEY, "--repository", "contoso/kit",
                                   "--permission", "administration=read"], client=self.client(api))
        self.assertEqual((code, out.getvalue()), (1, ""))
        self.assertIn("HTTP 422", err.getvalue())


if __name__ == "__main__":
    unittest.main()
