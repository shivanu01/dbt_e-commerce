"""
Production API → Snowflake ingestion script
Install: pip install snowflake-connector-python requests python-dotenv
Run:     python api_ingestion.py
"""

import os
import json
import uuid
import logging
import time
from datetime import datetime, timezone
from typing import Optional

import requests
import snowflake.connector
from dotenv import load_dotenv
import pandas as pd
from snowflake.connector.pandas_tools import write_pandas

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)s  %(message)s"
)
log = logging.getLogger(__name__)

# ── Config ───────────────────────────────────────────
API_BASE_URL  = os.getenv("API_BASE_URL",  "http://localhost:8000")
API_KEY       = os.getenv("API_KEY",       "")
PAGE_SIZE     = int(os.getenv("PAGE_SIZE", "100"))
MAX_RETRIES   = int(os.getenv("MAX_RETRIES", "3"))
RETRY_BACKOFF = float(os.getenv("RETRY_BACKOFF", "2.0"))
SOURCE_NAME   = "marketing_events_api"

SF_CONFIG = {
    "account":   os.environ["SNOWFLAKE_ACCOUNT"],
    "user":      os.environ["SNOWFLAKE_USER"],
    "password":  os.environ["SNOWFLAKE_PASSWORD"],
    "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE"),
    "database":  os.getenv("SNOWFLAKE_DATABASE", "RAW_DB"),
    "schema":    os.getenv("SNOWFLAKE_SCHEMA",   "LANDING"),
    "role":      os.getenv("SNOWFLAKE_ROLE",     "SYSADMIN"),
}


# ── Snowflake helpers ────────────────────────────────
def get_conn():
    return snowflake.connector.connect(**SF_CONFIG)


def get_watermark(conn) -> tuple:
    cur = conn.cursor()
    cur.execute("""
        SELECT last_fetched_at, last_cursor
        FROM RAW_DB.LANDING.API_WATERMARKS
        WHERE source_name = %s
    """, (SOURCE_NAME,))
    row = cur.fetchone()
    if row:
        return row[0], row[1]
    return datetime(2023, 1, 1, tzinfo=timezone.utc), None


def update_watermark(conn, fetched_at, cursor, records):
    conn.cursor().execute("""
        MERGE INTO RAW_DB.LANDING.API_WATERMARKS AS t
        USING (SELECT %s AS source_name) AS s
          ON  t.source_name = s.source_name
        WHEN MATCHED THEN UPDATE SET
            last_fetched_at = %s,
            last_cursor     = %s,
            records_fetched = records_fetched + %s,
            updated_at      = CURRENT_TIMESTAMP()
        WHEN NOT MATCHED THEN INSERT
            (source_name, last_fetched_at, last_cursor, records_fetched)
            VALUES (%s, %s, %s, %s)
    """, (
        SOURCE_NAME, fetched_at, cursor, records,
        SOURCE_NAME, fetched_at, cursor, records,
    ))
    conn.commit()


def bulk_insert(conn, events: list, batch_id: str, cursor_token: str):
    if not events:
        return

    rows = []
    for e in events:
        props = e.get("properties", {}) or {}
        rows.append({
            "EVENT_ID":        e["event_id"],
            "EVENT_TYPE":      e["event_type"],
            "CUSTOMER_ID":     e.get("customer_id"),
            "ANONYMOUS_ID":    e.get("anonymous_id"),
            "SESSION_ID":      e.get("session_id"),
            "OCCURRED_AT":     e["occurred_at"],
            "PROPERTIES":      json.dumps(props),
            "PAGE_URL":        props.get("page_url"),
            "PRODUCT_ID":      props.get("product_id"),
            "CAMPAIGN_ID":     props.get("campaign_id"),
            "EMAIL_SUBJECT":   props.get("email_subject"),
            "REVENUE_CENTS":   props.get("revenue_cents"),
            "_BATCH_ID":       batch_id,
            "_SOURCE_CURSOR":  cursor_token,
        })

    # conn.cursor().executemany("""
    #     INSERT INTO RAW_DB.LANDING.RAW_MARKETING_EVENTS (
    #         event_id, event_type, customer_id, anonymous_id, session_id,
    #         occurred_at, properties,
    #         page_url, product_id, campaign_id, email_subject, revenue_cents,
    #         _batch_id, _source_cursor
    #     )
    #     SELECT %s, %s, %s, %s, %s,
    #            %s, PARSE_JSON(%s),
    #            %s, %s, %s, %s, %s,
    #            %s, %s
    # """, rows)
    # conn.commit()
    # log.info("Inserted %d events (batch %s)", len(rows), batch_id)

    df = pd.DataFrame(rows)

    success, nchunks, nrows, _ = write_pandas(
        conn,
        df,
        table_name="RAW_MARKETING_EVENTS",
        database="RAW_DB",
        schema="LANDING",
        auto_create_table=False,
        quote_identifiers=False,
        overwrite=False
    )
    log.info("Inserted %d rows in %d chunks (batch %s)", nrows, nchunks, batch_id)


# ── API helpers ──────────────────────────────────────
def fetch_page(since: str, cursor: Optional[str], until: Optional[str] = None) -> dict:
    params = {"since": since, "limit": PAGE_SIZE}
    if cursor:
        params["cursor"] = cursor
    if until:
        params["until"] = until

    headers = {"Content-Type": "application/json"}
    if API_KEY:
        headers["Authorization"] = f"Bearer {API_KEY}"

    backoff = RETRY_BACKOFF
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            resp = requests.get(
                f"{API_BASE_URL}/events",
                params=params,
                headers=headers,
                timeout=30,
            )
            resp.raise_for_status()
            return resp.json()
        except requests.exceptions.HTTPError as e:
            status = e.response.status_code if e.response else 0
            if status == 429:
                retry_after = float(e.response.headers.get("Retry-After", backoff))
                log.warning("Rate limited. Sleeping %.1fs", retry_after)
                time.sleep(retry_after)
            elif status >= 500:
                log.warning("Server error %d. Retry %d/%d", status, attempt, MAX_RETRIES)
                time.sleep(backoff)
                backoff *= 2
            else:
                raise
        except requests.exceptions.ConnectionError:
            log.warning("Connection error. Retry %d/%d", attempt, MAX_RETRIES)
            time.sleep(backoff)
            backoff *= 2

    raise RuntimeError(f"Failed after {MAX_RETRIES} retries")


# ── Main ─────────────────────────────────────────────
def run():
    run_start    = datetime.now(tz=timezone.utc)
    batch_id     = str(uuid.uuid4())
    total_loaded = 0

    log.info("Starting ingestion — batch_id=%s", batch_id)

    conn = get_conn()
    try:
        last_fetched_at, _ = get_watermark(conn)
        since_str = last_fetched_at.strftime("%Y-%m-%dT%H:%M:%SZ")
        until_str = run_start.strftime("%Y-%m-%dT%H:%M:%SZ")

        log.info("Fetching events since=%s until=%s", since_str, until_str)

        cursor = None
        page   = 0

        while True:
            page   += 1
            payload = fetch_page(since=since_str, cursor=cursor, until=until_str)
            events  = payload.get("data", [])
            meta    = payload.get("meta", {})
            seen = set()
            unique_events = []
            for e in events:
                if e["event_id"] not in seen:
                    seen.add(e["event_id"])
                    unique_events.append(e)

            if len(unique_events) < len(events):
                log.warning("Dropped %d duplicate event_ids on page %d",
                len(events) - len(unique_events), page)

            if not events:
                log.info("No events on page %d — stopping.", page)
                break

            log.info("Page %d — %d events", page, len(events))
            bulk_insert(conn, events, batch_id, str(cursor or "0"))
            total_loaded += len(events)

            cursor = meta.get("next_cursor")
            if not meta.get("has_more"):
                break

        update_watermark(conn, run_start, str(cursor), total_loaded)
        log.info("Done — %d total events loaded.", total_loaded)

    except Exception:
        log.exception("Ingestion failed — watermark NOT updated")
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    run()