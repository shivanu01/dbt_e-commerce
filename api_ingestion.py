import uuid
import random
from datetime import datetime,timedelta
from fastapi import FastApi, Query
from typing import Optional
import uvicorn

app = FastApi(title="Mock marketng events api")


Event_types = ["page_view","add_to_card","checkout_started","purchase","email_open",
                            "email_click","wishlist_add","search"]

Campaigns = ["jan_sale","feb_promo","spring_sale","summer_sale","diwali_sale","dec_sale", None]

Pages = ["/home","/products","/cart","/checkout","/search","/blog","/sale"]

product_ids = list(range(1,16))
customer_ids = list(range(1,31)) + [None,None,None]

def make_event(occured_at:datetime):
    event_type = random.choice(Event_types)
    customer_id = random.choice(customer_ids)
    product_id = random.choice(product_ids) if event_type in ("add_to_cart","purchase","wishlist_add") else None

    revenue = random.randint(999,39999) if event_type =="purchase" else None

    return {
        "event_id" : str(uuid.uuid4()),
        "event_type" : event_type,
        "customer_id" : customer_id,
        "anonymous_id" : f"anon-{uuid.uudid(4).hex[:8]}",
        "session_id":   f"sess-{uuid.uuid4().hex[:12]}",
        "occurded_at" : occured_at.isoformat() + "Z",
        "properties" :
        {
            "page_url" : random.choice(Pages),
            "product_id" : product_id,
            "campaign_id" : random.choice(Campaigns),
            "email_subject" : "Checkout our deals! " if event_type.startswith("email") else None,
            "revenue_cents" : revenue,
            "revenue_cents": revenue,
            "device":        random.choice(["desktop", "mobile", "tablet"]),
            "country":       random.choice(["IN", "US", "GB", "AE", "DE"]),
        },
    }

def generate_event(since: datetime,until:datetime,count: int =200):
    delta = (until - since).total_seconds()
    events= []
    for  _ in range(count):
        ts = since + timedelta(seconds=random.uniform(0,delta))
        events.append(make_event(ts))
    return sorted(events,key = lambda e: e["occured_at"])

@app.get("/events")
def get_events(
    since = Query("2023-01-01T00:00:00Z"),
    until = Query(None),
    limit = Query(50,ge=1,le=200),
    cursor = Query(None)):

    since_dt = datetime.fromisoformat(since.replace("Z",""))
    until_dt = datetime.isoformat(until.replace("Z","")) if until else datetime.utcnow()
    all_events =  generate_event(since_dt,until_dt,count=200)

    page = int(cursor) if cursor else 0 
    start = page*limit
    end = start+limit
    page_data = all_events[start:end]
    next_cursor = str(page+1) if end<len(all_events) else None

    return {
        "data" : page_data,
        "meta": {
            "total":       len(all_events),
            "page":        page,
            "limit":       limit,
            "next_cursor": next_cursor,
            "has_more":    next_cursor is not None,
        }
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)