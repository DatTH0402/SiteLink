"""gunicorn settings for SiteLink (uvicorn workers)."""
import multiprocessing
import os
import uuid

bind = "0.0.0.0:8000"
worker_class = "uvicorn.workers.UvicornWorker"
workers = int(os.environ.get("WEB_CONCURRENCY") or max(2, min(4, multiprocessing.cpu_count())))
timeout = int(os.environ.get("GUNICORN_TIMEOUT", "300"))      # imports / exports can be long
graceful_timeout = 60
keepalive = 75
worker_tmp_dir = "/dev/shm"
forwarded_allow_ips = "*"          # trust X-Forwarded-* from the nginx in front
accesslog = None                   # nginx already logs every request
errorlog = "-"
loglevel = os.environ.get("LOG_LEVEL", "info")


def on_starting(server):
    # one id per container boot, inherited by every worker (used to run
    # "once per boot" jobs such as template regeneration in a single worker)
    os.environ["SITELINK_BOOT_ID"] = uuid.uuid4().hex
