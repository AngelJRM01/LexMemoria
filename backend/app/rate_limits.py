"""Persistent per-account fixed-window counters using existing versioned records."""
import hashlib
import time
from datetime import datetime,timedelta,timezone
from fastapi import HTTPException
from sqlalchemy import select,delete
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm.exc import StaleDataError
from .db import Record


def account_limit(session,user_id,action,limit=10,seconds=60):
    bucket=int(time.time())//seconds
    key='rate:'+hashlib.sha256(f'{user_id}:{action}:{bucket}'.encode()).hexdigest()
    for _ in range(8):
        row=session.scalar(select(Record).where(Record.id==key).with_for_update().execution_options(populate_existing=True))
        if row and row.data['count']>=limit:
            raise HTTPException(429,'Espera antes de realizar más solicitudes',headers={'Retry-After':str(seconds)})
        if row:row.data={**row.data,'count':row.data['count']+1}
        else:session.add(Record(id=key,kind='rate_window',owner=user_id,data={'action':action,'count':1}))
        try:
            session.commit()
            cutoff=(datetime.now(timezone.utc)-timedelta(hours=1)).isoformat()
            session.execute(delete(Record).where(Record.kind=='rate_window',Record.created_at<cutoff))
            session.commit();return
        except (IntegrityError,StaleDataError):session.rollback()
    raise HTTPException(429,'Demasiadas solicitudes simultáneas',headers={'Retry-After':str(seconds)})
