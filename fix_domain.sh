#!/bin/bash
set -e

echo "=== Fixing SiteLink for domain https://mlmt.mobifone.vn/sitelink/ ==="

ROOT="/home/mlmt/work/src/SiteLink"

# ─────────────────────────────────────────────────────────────────────────────
# PART A: Fix on 10.24.15.169 (app server)
# No change needed to api/client.ts – window.location.origin handles it.
# But we need to make sure the outer nginx on 10.24.15.169 also
# exposes /api/ so both direct IP and domain access work.
# ─────────────────────────────────────────────────────────────────────────────

# 1. vite.config.ts – keep base: '/sitelink/'
cat > "$ROOT/frontend/vite.config.ts" << 'EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  base: '/sitelink/',
  plugins: [react()],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  server: {
    proxy: {
      '/api': { target: 'http://localhost:8000', changeOrigin: true },
    },
  },
})
EOF
echo "[OK] vite.config.ts"

# 2. frontend/nginx.conf – unchanged, keep working
cat > "$ROOT/frontend/nginx.conf" << 'EOF'
server {
    listen 80;
    root /usr/share/nginx/html;
    index index.html;

    location = / {
        return 301 /sitelink/;
    }

    location /sitelink/assets/ {
        alias /usr/share/nginx/html/assets/;
        expires 1y;
        access_log off;
        add_header Cache-Control "public, immutable";
    }

    location /sitelink/ {
        try_files $uri @spa;
    }

    location @spa {
        root /usr/share/nginx/html;
        try_files /index.html =404;
    }
}
EOF
echo "[OK] frontend/nginx.conf"

# 3. frontend/src/main.tsx – keep basename="/sitelink"
cat > "$ROOT/frontend/src/main.tsx" << 'EOF'
import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App'
import 'antd/dist/reset.css'
import './index.css'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <BrowserRouter basename="/sitelink">
      <App />
    </BrowserRouter>
  </React.StrictMode>,
)
EOF
echo "[OK] frontend/src/main.tsx"

# 4. nginx/nginx.conf on 10.24.15.169
#    CRITICAL: must expose /api/ at the top level so that when the
#    domain nginx at 10.0.146.10 forwards /api/v1/... → 10.24.15.169:8081/api/v1/...
#    it reaches the FastAPI backend correctly.
cat > "$ROOT/nginx/nginx.conf" << 'EOF'
worker_processes 1;
events { worker_connections 1024; }

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;
    client_max_body_size 100M;

    upstream backend  { server backend:8000; }
    upstream frontend { server frontend:80; }

    server {
        listen 80;
        server_name _;

        # ── API – proxy to FastAPI backend ──────────────────────────────
        # Accessible at both:
        #   http://10.24.15.169:8081/api/...   (direct)
        #   https://mlmt.mobifone.vn/api/...   (via domain nginx forward)
        location /api/ {
            proxy_pass         http://backend/api/;
            proxy_set_header   Host              $host;
            proxy_set_header   X-Real-IP         $remote_addr;
            proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto $http_x_forwarded_proto;
            proxy_read_timeout 300s;
            proxy_send_timeout 120s;
            client_max_body_size 100M;
        }

        location /docs {
            proxy_pass http://backend/docs;
            proxy_set_header Host $host;
        }

        location /openapi.json {
            proxy_pass http://backend/openapi.json;
            proxy_set_header Host $host;
        }

        # ── Redirect bare root ──────────────────────────────────────────
        location = / {
            return 301 /sitelink/;
        }

        # ── Frontend SPA ────────────────────────────────────────────────
        location /sitelink/ {
            proxy_pass         http://frontend/sitelink/;
            proxy_set_header   Host              $host;
            proxy_set_header   X-Real-IP         $remote_addr;
            proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto $http_x_forwarded_proto;
            proxy_read_timeout 60s;
        }
    }
}
EOF
echo "[OK] nginx/nginx.conf (10.24.15.169)"

# ─────────────────────────────────────────────────────────────────────────────
# PART B: Generate the snippet to add to mlmt.conf on 10.0.146.10
#         We print it – you must apply it manually on that server.
# ─────────────────────────────────────────────────────────────────────────────
cat << 'DOMAIN_CONF'

=======================================================================
MANUAL STEP REQUIRED on domain server 10.0.146.10
=======================================================================

Edit /etc/nginx/conf.d/mlmt.conf on the domain server.

upstream sitelink_up {
  zone sitelink_up 64k;
  server 10.24.15.169:8081 max_fails=3 fail_timeout=10s max_conns=200;
  keepalive 64;
  keepalive_timeout 60s;
}

# ── NEW: separate upstream for SiteLink API ──────────────────────────────────
# Points to the same server/port as sitelink_up but kept separate
# so we can tune it independently in the future.
upstream sitelink_api_up {
  zone sitelink_api_up 64k;
  server 10.24.15.169:8081 max_fails=3 fail_timeout=10s max_conns=200;
  keepalive 64;
  keepalive_timeout 60s;
}


# ========================
# SERVER :443 SSL (Public)
# ========================
  # ── NEW: SiteLink API ────────────────────────────────────────────────────
  # MUST be placed BEFORE /sitelink/ so nginx matches /api/ first.
  # When browser is at https://mlmt.mobifone.vn/sitelink/, all axios calls
  # go to https://mlmt.mobifone.vn/api/v1/... → this block catches them
  # and forwards to the FastAPI backend at 10.24.15.169:8081/api/v1/...
  location /api/ {
    allow 10.0.0.0/8;
    deny all;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_connect_timeout 3s;
    proxy_send_timeout 120s;
    proxy_read_timeout 120s;
    proxy_next_upstream error timeout http_502 http_503 http_504;
    proxy_next_upstream_tries 2;
    client_max_body_size 100M;
    proxy_pass http://sitelink_api_up/api/;
  }

  # ── SiteLink frontend SPA ────────────────────────────────────────────────
  location /sitelink/ {
    allow 10.0.0.0/8;
    deny all;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_connect_timeout 3s;
    proxy_send_timeout 120s;
    proxy_read_timeout 120s;
    proxy_next_upstream error timeout http_502 http_503 http_504;
    proxy_next_upstream_tries 2;
    client_max_body_size 100M;
    proxy_pass http://sitelink_up/sitelink/;
  }


-- Then reload nginx on 10.0.146.10: -----------------------------------

  sudo nginx -t && sudo systemctl reload nginx

=======================================================================
DOMAIN_CONF

# ─────────────────────────────────────────────────────────────────────────────
# 5. Rebuild app server containers
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Rebuilding containers on 10.24.15.169 ==="
cd "$ROOT"
sudo docker compose down
sudo docker compose up -d --build

echo ""
echo "=== Waiting 10s for containers to be ready ==="
sleep 10

echo ""
echo "=== Verifying /api/ is reachable on this server ==="
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:8081/api/v1/auth/login \
  -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin&password=admin")
echo "Login endpoint HTTP status: $HTTP_CODE"
if [ "$HTTP_CODE" = "200" ]; then
  echo "[OK] API is working correctly"
else
  echo "[WARN] Expected 200, got $HTTP_CODE - check backend logs"
fi

echo ""
echo "=== Done! ==="
echo ""
echo "Direct access (working now):"
echo "  http://10.24.15.169:8081/sitelink/"
echo ""
echo "Domain access (after manual step on 10.0.146.10):"
echo "  https://mlmt.mobifone.vn/sitelink/"
echo ""
echo "How it works:"
echo "  Browser → https://mlmt.mobifone.vn/sitelink/  → domain nginx → 10.24.15.169:8081/sitelink/"
echo "  Browser → https://mlmt.mobifone.vn/api/v1/... → domain nginx → 10.24.15.169:8081/api/v1/..."




