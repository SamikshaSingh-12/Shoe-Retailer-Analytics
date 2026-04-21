import json
from datetime import date, datetime
from decimal import Decimal

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

import db
import queries


class DBJSONEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, Decimal):
            return float(o)
        if isinstance(o, (date, datetime)):
            return o.isoformat()
        return super().default(o)


class DBJSONResponse(JSONResponse):
    def render(self, content) -> bytes:
        return json.dumps(content, cls=DBJSONEncoder, allow_nan=False).encode("utf-8")


app = FastAPI(
    title="Footwear Retailer Analytics",
    default_response_class=DBJSONResponse,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)


@app.get("/api/health")
def health():
    try:
        with db.get_cursor() as cur:
            cur.execute("SELECT 1")
        return {"ok": True, "db": "connected"}
    except Exception as e:
        raise HTTPException(500, f"db unreachable: {e}")


@app.get("/api/q1")
def api_q1():
    return queries.q1()


@app.get("/api/q2")
def api_q2():
    return queries.q2()


@app.get("/api/q3")
def api_q3():
    return queries.q3()


@app.get("/api/q4")
def api_q4():
    return queries.q4()


@app.get("/api/q5")
def api_q5(limit: int = Query(20, ge=1, le=200)):
    return queries.q5(limit=limit)


@app.get("/api/q6")
def api_q6():
    return queries.q6()


@app.get("/api/q7")
def api_q7(
    category: str = Query("Running"),
    limit: int = Query(30, ge=1, le=200),
):
    return queries.q7(category=category, limit=limit)


@app.get("/api/q8")
def api_q8(groupby: str = Query("year", regex="^(year|month)$")):
    return queries.q8(groupby=groupby)


@app.get("/api/q9")
def api_q9():
    return queries.q9()


@app.get("/api/categories")
def api_categories():
    return queries.categories()


app.mount("/", StaticFiles(directory="static", html=True), name="static")
