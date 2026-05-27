#!/bin/bash
set -e
echo "Starting SiteLink..."
sudo docker compose up -d --build
echo ""
echo "SiteLink is running!"
echo "  Frontend : http://localhost"
echo "  API docs : http://localhost/api/docs"
echo "  Login    : admin / admin"
