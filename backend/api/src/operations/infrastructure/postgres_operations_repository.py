from datetime import datetime
from uuid import UUID
from ...database import pool


class PostgresOperationsRepository:

    async def active_campaigns(self)->list[dict]:
        async with pool.connection() as c:r=await c.execute("SELECT id,title,description,campaign_type,starts_at,ends_at,points_reward FROM campaigns WHERE active=TRUE AND starts_at<=NOW() AND ends_at>=NOW() ORDER BY ends_at");return await r.fetchall()

    async def create_campaign(self,d:object)->UUID:
        async with pool.connection() as c:r=await c.execute("INSERT INTO campaigns (title,description,campaign_type,starts_at,ends_at,points_reward) VALUES (%s,%s,%s,%s,%s,%s) RETURNING id",(d.title,d.description,d.campaign_type,d.starts_at,d.ends_at,d.points_reward));row=await r.fetchone();await c.commit();return row["id"]

    async def create_sensitive_area(self,d:object)->UUID:
        async with pool.connection() as c:r=await c.execute("INSERT INTO sensitive_areas (name,area_type,criticality,location,protection_radius_m) VALUES (%s,%s,%s,ST_SetSRID(ST_MakePoint(%s,%s),4326)::geography,%s) RETURNING id",(d.name,d.area_type,d.criticality,d.longitude,d.latitude,d.protection_radius_m));row=await r.fetchone();await c.commit();return row["id"]

    async def contributions(self,user_id:UUID)->list[dict]:
        async with pool.connection() as c:r=await c.execute("SELECT id,incident_id,contribution_type,points,created_at FROM citizen_contributions WHERE user_id=%s ORDER BY created_at DESC LIMIT 200",(user_id,));return await r.fetchall()

    async def dashboard(self,since:datetime)->dict:
        async with pool.connection() as c:
            a=await c.execute("SELECT category,severity,workflow_status,count(*) AS total,round(avg(risk_score),2) AS average_risk FROM incidents WHERE occurred_at>=%s GROUP BY category,severity,workflow_status ORDER BY total DESC",(since,));breakdown=await a.fetchall()
            b=await c.execute("SELECT ST_Y(ST_Centroid(ST_Collect(location::geometry))) AS latitude,ST_X(ST_Centroid(ST_Collect(location::geometry))) AS longitude,count(*) AS total,max(risk_score) AS maximum_risk FROM incidents WHERE occurred_at>=%s GROUP BY ST_SnapToGrid(location::geometry,0.01) HAVING count(*)>=2 ORDER BY total DESC LIMIT 50",(since,));hotspots=await b.fetchall()
            d=await c.execute("SELECT date_trunc('day',occurred_at) AS day,count(*) AS total,count(*) FILTER (WHERE severity='critico') AS critical FROM incidents WHERE occurred_at>=%s GROUP BY day ORDER BY day",(since,));trend=await d.fetchall();return {"breakdown":breakdown,"hotspots":hotspots,"trend":trend}

    async def metrics(self)->dict:
        async with pool.connection() as c:r=await c.execute("SELECT (SELECT count(*) FROM outbox) AS outbox_pending,(SELECT count(*) FROM outbox WHERE attempts>0) AS outbox_retries,(SELECT count(*) FROM notifications WHERE created_at>=NOW()-INTERVAL '24 hours') AS notifications_24h,(SELECT count(*) FROM processed_events WHERE processed_at>=NOW()-INTERVAL '24 hours') AS events_24h");return await r.fetchone()
