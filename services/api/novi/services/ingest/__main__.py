import asyncio

from novi.services.ingest.run import main

if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
