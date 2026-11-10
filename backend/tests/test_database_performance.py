"""Data-preserving optimizations and actual index use, rather than timing limits."""
from sqlalchemy import event,insert,select,text
from sqlalchemy.dialects import postgresql
from app.db import connect,Record,RECORD_QUERY_INDEXES
from app.catalogue import rebuild_index,NormIndex


def test_rebuild_is_batched_repairs_metadata_and_does_not_rewrite_unchanged_rows(tmp_path):
    engine,factory=connect('sqlite:///'+str(tmp_path/'search.db'))
    with engine.begin() as c:
        c.execute(insert(Record),[{'id':str(i),'kind':'norm','data':{'title':'Ley de protección','source':'BOE'}} for i in range(250)])
    statements=[]
    def capture(_,__,sql,*args):statements.append(sql)
    event.listen(engine,'before_cursor_execute',capture)
    with factory() as s:
        rebuild_index(s)
        assert len([sql for sql in statements if sql.startswith('SELECT')])==1
        assert len([sql for sql in statements if sql.startswith('INSERT')])==3
        before=s.execute(text('SELECT total_changes()')).scalar_one()
        rebuild_index(s)
        assert s.execute(text('SELECT total_changes()')).scalar_one()==before
        search=s.get(NormIndex,'1')
        source=s.get(Record,'1');source.data={'title':'Reforma fiscal','source':'BOE','jurisdiction':'Estatal'}
        s.commit();rebuild_index(s)
        assert search.text.strip()=='reforma fiscal' and search.jurisdiction=='Estatal'
    engine.dispose()


def test_existing_database_gets_expression_index_and_lookup_keeps_owner_isolation(tmp_path):
    url='sqlite:///'+str(tmp_path/'old.db');engine,_=connect(url)
    with engine.begin() as c:
        for index in RECORD_QUERY_INDEXES:index.drop(c)
        c.execute(insert(Record),[{'id':str(i),'owner':owner,'kind':'card','data':{'clientId':'same-local-id'}} for i,owner in enumerate(['alice','bob'])])
    engine.dispose();engine,factory=connect(url)
    with factory() as s:
        query=select(Record).where(Record.owner=='alice',Record.kind=='card',Record.client_id=='same-local-id')
        assert s.scalar(query).id=='0'
        plan=s.execute(text('EXPLAIN QUERY PLAN '+str(query.compile(engine,compile_kwargs={'literal_binds':True})))).all()
        assert any('ix_records_owner_kind_client_id' in row[-1] for row in plan)
        sql=str(query.compile(dialect=postgresql.dialect()))
        assert "->> 'clientId'" in sql
    engine.dispose()
