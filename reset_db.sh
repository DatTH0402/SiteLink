#!/bin/bash
echo "WARNING: This will DELETE all data!"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read
docker compose down -v
docker compose up -d --build
echo "Database reset complete."
