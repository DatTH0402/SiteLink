#!/bin/bash
set -e

echo "=== Fixing SiteLink base path /sitelink/ - 404 fix ==="

ROOT="/home/mlmt/work/src/SiteLink"

# ─────────────────────────────────────────────────────────────────────────────
# 1. vite.config.ts  – base: '/sitelink/'
# ─────────────────────────────────────────────────────────────────────────────
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

# ─────────────────────────────────────────────────────────────────────────────
# 2. frontend/nginx.conf
#    - root stays at /usr/share/nginx/html  (where Vite puts index.html)
#    - location /sitelink/ serves files, falls back to /index.html (on disk)
#    - named location @spa breaks the rewrite cycle
# ─────────────────────────────────────────────────────────────────────────────
cat > "$ROOT/frontend/nginx.conf" << 'EOF'
server {
    listen 80;
    root /usr/share/nginx/html;
    index index.html;

    # Redirect bare root to /sitelink/
    location = / {
        return 301 /sitelink/;
    }

    # Vite-built assets (js, css, images) – served directly from disk
    location /sitelink/assets/ {
        alias /usr/share/nginx/html/assets/;
        expires 1y;
        access_log off;
        add_header Cache-Control "public, immutable";
    }

    # SPA catch-all: try real file first, then fall back to index.html
    location /sitelink/ {
        try_files $uri @spa;
    }

    # Named location – serves index.html without re-entering /sitelink/
    location @spa {
        root /usr/share/nginx/html;
        try_files /index.html =404;
    }
}
EOF
echo "[OK] frontend/nginx.conf"

# ─────────────────────────────────────────────────────────────────────────────
# 3. nginx/nginx.conf  – outer reverse proxy
# ─────────────────────────────────────────────────────────────────────────────
cat > "$ROOT/nginx/nginx.conf" << 'EOF'
worker_processes 1;
events { worker_connections 1024; }

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;
    client_max_body_size 50M;

    upstream backend  { server backend:8000; }
    upstream frontend { server frontend:80; }

    server {
        listen 80;
        server_name _;

        # API – proxy to FastAPI backend
        location /api/ {
            proxy_pass         http://backend/api/;
            proxy_set_header   Host              $host;
            proxy_set_header   X-Real-IP         $remote_addr;
            proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_read_timeout 300s;
        }

        location /docs {
            proxy_pass http://backend/docs;
            proxy_set_header Host $host;
        }

        location /openapi.json {
            proxy_pass http://backend/openapi.json;
            proxy_set_header Host $host;
        }

        # Redirect bare root to /sitelink/
        location = / {
            return 301 /sitelink/;
        }

        # All frontend traffic (SPA + assets) → frontend container
        location /sitelink/ {
            proxy_pass         http://frontend/sitelink/;
            proxy_set_header   Host              $host;
            proxy_set_header   X-Real-IP         $remote_addr;
            proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_read_timeout 60s;
        }
    }
}
EOF
echo "[OK] nginx/nginx.conf"

# ─────────────────────────────────────────────────────────────────────────────
# 4. frontend/src/main.tsx  – basename="/sitelink"
# ─────────────────────────────────────────────────────────────────────────────
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

# ─────────────────────────────────────────────────────────────────────────────
# 5. Rebuild and restart
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Rebuilding containers ==="
cd "$ROOT"
sudo docker compose down
sudo docker compose up -d --build

echo ""
echo "=== Waiting 10s for containers to be ready... ==="
sleep 10

echo ""
echo "=== Verifying frontend container file layout ==="
sudo docker exec sitelink_frontend sh -c "ls /usr/share/nginx/html/" && \
  echo "[OK] html root content listed above"

echo ""
echo "=== Done! ==="
echo "  App  : http://localhost:8081/sitelink/"
echo "  API  : http://localhost:8081/api/docs"
echo "  Login: admin / admin"