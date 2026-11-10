from editorial_helpers import enable_editorial
from datetime import datetime, timedelta, timezone
import pytest
from fastapi.testclient import TestClient
from app.main import create_app
from app.db import Account,Record
from app.collaboration import Invitation

@pytest.fixture
def data(tmp_path):
    app=create_app('sqlite:///'+str(tmp_path/'collab.db'));c=TestClient(app)
    users=[c.post('/v1/auth/guest').json() for _ in range(3)]
    h=[{'Authorization':'Bearer '+u['accessToken']} for u in users]
    for i,headers in enumerate(h):
        assert c.put('/v1/account/profile',headers={**headers,'If-Match':'0'},json={'alias':f'person_{i}','allowLinkInvitations':True,'allowAliasInvitations':True}).status_code==200
    deck=c.post('/v1/decks',headers=h[0],json={'title':'Derecho privado'}).json()
    body={'deckId':deck['id'],'clientId':'shared-card-1','front':'Pregunta','back':'Respuesta','citations':[{'normId':'BOE-A-1978-31229','unitId':'a1','versionId':'mobile-v1','unitVersionHash':'a'*64}]}
    card=c.post('/v1/cards',headers=h[0],json=body).json()
    return app,c,users,h,deck,card,body


def invite(c,h,target,role):
    r=c.post(f'/v1/collaboration/{target}/invitations',headers=h,json={'role':role})
    assert r.status_code==201,r.text
    return r.json()

def accept(c,h,inv):return c.post('/v1/collaboration/invitations/accept',headers=h,json={'token':inv['token']})


def test_shared_roles_revocation_and_progress_privacy(data):
    app,c,users,(a,b,d),deck,card,body=data
    path='/v1/collaboration/decks/'+deck['id']
    assert c.get(path,headers=b).status_code==404
    inv=invite(c,a,deck['id'],'reader');assert accept(c,b,inv).status_code==200
    result=c.get(path,headers=b).json()
    assert result['items'][0]['citations']==body['citations']
    assert not any(k in str(result) for k in ['review_event','accessToken','refreshToken','lastActiveAt'])
    edit='/v1/collaboration/cards/'+card['id']
    assert c.put(edit,headers={**b,'If-Match':'1'},json={**body,'back':'Mala edición'}).status_code==404
    assert c.post('/v1/reviews',headers=b,json={'cardId':card['id'],'cardRevision':1,'rating':3,'occurredAt':datetime.now(timezone.utc).isoformat(),'idempotencyKey':'foreign-review'}).status_code==404
    rolepath=f"/v1/collaboration/{deck['id']}/members/{users[1]['userId']}"
    assert c.put(rolepath,headers=a,json={'role':'editor'}).status_code==200
    assert c.put(edit,headers={**b,'If-Match':'1'},json={**body,'back':'Nueva respuesta'}).json()['revision']==2
    assert c.put(edit,headers={**b,'If-Match':'1'},json=body).status_code==409
    assert c.get('/v1/cards/'+card['id']+'/history',headers=a).json()['items'][0]['content']['back']=='Respuesta'
    assert c.get('/v1/cards/'+card['id']+'/history',headers=b).status_code==404
    assert c.delete(rolepath,headers=d).status_code==404
    assert c.delete(rolepath,headers=a).status_code==200
    assert c.get(path,headers=b).status_code==404
    assert accept(c,b,inv).status_code==404


def test_personal_copy_survives_original_account_deletion(data):
    app,c,users,(a,b,d),deck,card,body=data
    assert accept(c,b,invite(c,a,deck['id'],'reader')).status_code==200
    assert c.post('/v1/reviews',headers=a,json={'cardId':card['id'],'cardRevision':1,'rating':4,'occurredAt':datetime.now(timezone.utc).isoformat(),'idempotencyKey':'owner-review'}).status_code==201
    assert c.post('/v1/collaboration/decks/'+deck['id']+'/copy',headers=b).status_code==201
    records=c.get('/v1/account/export',headers=b).json()['records']
    copied=next(r for r in records if r['kind']=='card')
    assert copied['id']!=card['id'] and copied['revision']==1 and copied['citations']==body['citations']
    assert copied['sourceCardId']==card['id'] and not any(r['kind']=='review_event' for r in records)
    assert c.delete('/v1/account?confirmation=ELIMINAR',headers=a).status_code==200
    assert c.get('/v1/account/export',headers=b).status_code==200
    edited={k:v for k,v in copied.items() if k in body or k in ['options','correct','type','explanation']};edited['back']='Personal'
    assert c.put('/v1/cards/'+copied['id'],headers={**b,'If-Match':'1'},json=edited).status_code==200


def test_invitation_expiry_uses_and_revocation(data):
    app,c,users,(a,b,d),deck,card,body=data
    inv=invite(c,a,deck['id'],'reader')
    assert inv['token'] not in c.get('/v1/collaboration/invitations',headers=a).text
    with app.state.factory() as s:
        s.get(Invitation,inv['id']).expires_at=(datetime.now(timezone.utc)-timedelta(days=1)).isoformat();s.commit()
    assert accept(c,b,inv).status_code==404
    inv=invite(c,a,deck['id'],'reader');assert accept(c,b,inv).status_code==200
    assert accept(c,d,inv).status_code==404
    inv=invite(c,a,deck['id'],'editor')
    assert c.delete('/v1/collaboration/invitations/'+inv['id'],headers=d).status_code==404
    assert c.delete('/v1/collaboration/invitations/'+inv['id'],headers=a).status_code==200
    assert accept(c,d,inv).status_code==404
    page=c.get('/invite');assert page.status_code==200 and deck['title'] not in page.text


def test_group_roles_materials_leave_and_delete(data):
    app,c,users,(a,b,d),deck,card,body=data
    group=c.post('/v1/collaboration/groups',headers=a,json={'name':'Civil','topic':'Contratos'}).json()
    gp='/v1/collaboration/groups/'+group['id']
    assert c.get(gp,headers=b).status_code==404
    assert accept(c,b,invite(c,a,group['id'],'member')).status_code==200
    assert c.post(gp+'/resources',headers=b,json={'deckId':deck['id']}).status_code==404
    assert c.post(gp+'/resources',headers=a,json={'deckId':deck['id'],'topic':'Parte general'}).status_code==201
    assert c.get(gp,headers=b).json()['resources'][0]['deckId']==deck['id']
    assert c.get('/v1/collaboration/decks/'+deck['id'],headers=b).status_code==200
    assert c.get('/v1/collaboration/decks/'+deck['id'],headers=d).status_code==404
    assert c.delete(f"/v1/collaboration/{group['id']}/members/{users[1]['userId']}",headers=b).status_code==200
    assert c.get('/v1/collaboration/decks/'+deck['id'],headers=b).status_code==404
    assert c.get(gp,headers=b).status_code==404
    assert c.delete(gp,headers=a).status_code==200
    assert c.get('/v1/decks',headers=a).json()['items'][0]['id']==deck['id']


def test_contacts_discovery_and_blocking(data):
    app,c,users,(a,b,d),deck,*_=data
    request=c.post('/v1/collaboration/contacts/requests',headers=a,json={'alias':'PERSON_1'}).json()
    assert c.post('/v1/collaboration/contacts/'+request['id']+'/accept',headers=d).status_code==404
    assert c.post('/v1/collaboration/contacts/'+request['id']+'/accept',headers=b).status_code==200
    contacts=c.get('/v1/collaboration/contacts',headers=a).json()['items']
    assert contacts[0]['person']['alias']=='person_1'
    assert not any(x in str(contacts) for x in ['email','notes','accessToken'])
    assert accept(c,b,invite(c,a,deck['id'],'reader')).status_code==200
    assert c.post('/v1/collaboration/blocks/'+users[0]['userId'],headers=b).status_code==200
    assert c.get('/v1/collaboration/decks/'+deck['id'],headers=b).status_code==404
    assert c.post('/v1/collaboration/contacts/requests',headers=a,json={'alias':'person_1'}).status_code==404
    blocks=c.get('/v1/collaboration/contacts',headers=b).json()['items']
    assert c.delete('/v1/collaboration/contacts/'+blocks[0]['id'],headers=b).status_code==200
    p=c.get('/v1/account/profile',headers=b).json()
    c.put('/v1/account/profile',headers={**b,'If-Match':str(p['revision'])},json={'alias':'person_1'})
    assert c.post('/v1/collaboration/contacts/requests',headers=a,json={'alias':'person_1'}).json()['title']==c.post('/v1/collaboration/contacts/requests',headers=a,json={'alias':'not_existing'}).json()['title']


def test_publication_and_moderation_do_not_certify_law(data,monkeypatch):
    monkeypatch.setenv("PUBLIC_DECK_PUBLICATION_ENABLED", "true")
    app,c,users,(a,b,d),deck,card,body=data
    pub='/v1/collaboration/decks/'+deck['id']+'/publication'
    assert c.post(pub,headers=a,json={'confirmation':'PUBLICAR','subject':'Civil'}).json()['state']=='pending'
    assert c.get('/v1/collaboration/catalogue').json()['items']==[]
    decision='/v1/admin/collaboration/'+deck['id']+'/decision'
    assert c.post(decision,headers=b,json={'action':'allow','reason':'Contenido admisible para compartir'}).status_code==403
    with app.state.factory() as s:s.get(Account,users[1]['userId']).role='reviewer';s.commit()
    assert c.post(decision,headers=b,json={'action':'allow','reason':'Contenido admisible para compartir'}).status_code==503
    enable_editorial(monkeypatch,c,app)
    assert c.post(decision,headers=b,json={'action':'allow','reason':'Contenido admisible para compartir'}).json()['legalReview'] is False
    catalogue=c.get('/v1/collaboration/catalogue?subject=Civil').json()['items']
    assert len(catalogue)==1 and catalogue[0]['contentStatus']=='user_content_not_legally_reviewed'
    assert c.put('/v1/cards/'+card['id'],headers={**a,'If-Match':'1'},json={**body,'back':'Cambio posterior'}).status_code==200
    assert c.get('/v1/collaboration/catalogue').json()['items']==[]


def test_contacts_link_direct_acceptance_and_group_role_changes(data):
    app,c,users,(a,b,d),deck,card,body=data
    link=c.post('/v1/collaboration/contacts/link',headers=a);assert link.status_code==201
    token=link.json()['path'].split('#',1)[1]
    assert c.post('/v1/collaboration/invitations/accept',headers=b,json={'token':token}).json()['role']=='contact'
    request=c.post('/v1/collaboration/'+deck['id']+'/invitations',headers=a,json={'role':'reader','recipientId':users[1]['userId']}).json()
    assert c.post('/v1/collaboration/invitations/'+request['id']+'/accept',headers=d).status_code==404
    assert c.post('/v1/collaboration/invitations/'+request['id']+'/accept',headers=b).status_code==200
    group=c.post('/v1/collaboration/groups',headers=a,json={'name':'Grupo'}).json()
    assert accept(c,b,invite(c,a,group['id'],'admin')).status_code==200
    assert c.post('/v1/collaboration/'+group['id']+'/invitations',headers=b,json={'role':'admin'}).status_code==403
    update=c.put('/v1/collaboration/groups/'+group['id'],headers={**b,'If-Match':str(group['revision'])},json={'name':'Nuevo nombre','type':'university'})
    assert update.status_code==200
    assert c.put('/v1/collaboration/groups/'+group['id'],headers={**b,'If-Match':str(group['revision'])},json={'name':'Stale'}).status_code==409


def test_reports_appeals_and_restrictions_preserve_private_data(data,monkeypatch):
    app,c,users,(a,b,d),deck,card,body=data
    report=c.post('/v1/collaboration/reports',headers=a,json={'targetId':deck['id'],'reason':'Material que requiere revisión'}).json()
    assert c.post('/v1/collaboration/reports',headers=b,json={'targetId':deck['id'],'reason':'Apelación de otra persona','appealOf':report['id']}).status_code==404
    with app.state.factory() as s:s.get(Account,users[2]['userId']).role='admin';s.commit()
    enable_editorial(monkeypatch,c,app)
    assert c.post('/v1/admin/collaboration/reports/'+report['id']+'/decision',headers=d,json={'status':'resolved','reason':'Se ha revisado el material y la incidencia'}).status_code==200
    assert c.post('/v1/collaboration/reports',headers=a,json={'targetId':deck['id'],'reason':'Solicito reconsiderar la decisión','appealOf':report['id']}).status_code==201
    assert len(c.get('/v1/collaboration/reports',headers=a).json()['items'])==2
    assert c.post('/v1/admin/collaboration/accounts/'+users[0]['userId']+'/restriction',headers=d,json={'suspended':True,'reason':'Suspensión de compartición justificada para la prueba'}).status_code==200
    assert c.post('/v1/collaboration/'+deck['id']+'/invitations',headers=a,json={'role':'reader'}).status_code==403
    assert c.get('/v1/account/export',headers=a).status_code==200
    assert c.get('/v1/study/today',headers=a).status_code==200
    assert c.post('/v1/collaboration/reports',headers=a,json={'targetId':deck['id'],'reason':'Solicito revisar mi suspensión'}).status_code==201


def test_copy_updates_are_explicit_revisioned_and_preserve_personal_edits(data):
    app,c,users,(a,b,d),deck,card,body=data
    assert accept(c,b,invite(c,a,deck['id'],'reader')).status_code==200
    endpoint='/v1/collaboration/decks/'+deck['id']+'/copy'
    first=c.post(endpoint,headers={**b,'Idempotency-Key':'same-copy-attempt'}).json()
    assert c.post(endpoint,headers={**b,'Idempotency-Key':'same-copy-attempt'}).json()['id']==first['id']
    own=c.get('/v1/account/export',headers=b).json()['records'];copy=next(r for r in own if r['kind']=='card')
    review={'cardId':copy['id'],'cardRevision':1,'rating':3,'occurredAt':datetime.now(timezone.utc).isoformat(),'idempotencyKey':'copy-review'}
    assert c.post('/v1/reviews',headers=b,json=review).status_code==201
    updated=c.put('/v1/cards/'+card['id'],headers={**a,'If-Match':'1'},json={**body,'back':'Origen actualizado'})
    assert updated.status_code==200
    path='/v1/collaboration/copies/'+first['id']+'/updates'
    preview=c.get(path,headers=b).json();assert preview['changed']==1
    # Nothing changes until the explicit update confirmation.
    assert c.get('/v1/collaboration/decks/'+first['id'],headers=b).json()['items'][0]['back']=='Respuesta'
    assert c.post(path,headers={**b,'If-Match':str(preview['revision'])},json={'confirmation':'ACTUALIZAR'}).json()['updated']==1
    history=c.get('/v1/cards/'+copy['id']+'/history',headers=b).json()['items'];assert history[0]['content']['back']=='Respuesta'
    records=c.get('/v1/account/export',headers=b).json()['records']
    assert len([r for r in records if r['kind']=='review_event'])==1
    current=next(r for r in records if r['kind']=='card')
    personal={k:current[k] for k in body if k in current};personal['back']='Mi modificación personal'
    assert c.put('/v1/cards/'+copy['id'],headers={**b,'If-Match':str(current['revision'])},json=personal).status_code==200
    # Source edits never replace detached personal work.
    c.put('/v1/cards/'+card['id'],headers={**a,'If-Match':'2'},json={**body,'back':'Otro cambio del autor'})
    preview=c.get(path,headers=b).json();assert preview['changed']==0 and preview['new']==0
    current=c.get('/v1/collaboration/decks/'+first['id'],headers=b).json()['items'][0]
    assert current['back']=='Mi modificación personal'
    assert c.post('/v1/cards',headers=b,json={**personal,'deckId':deck['id']}).status_code==404


def test_retry_same_edit_after_lost_response_and_client_id_lookup(data):
    app,c,users,(a,b,d),deck,card,body=data
    changed={**body,'back':'Cambio idempotente'}
    first=c.put('/v1/cards/'+card['id'],headers={**a,'If-Match':'1'},json=changed)
    retry=c.put('/v1/cards/'+card['id'],headers={**a,'If-Match':'1'},json=changed)
    assert first.status_code==retry.status_code==200 and first.json()==retry.json()
    assert len(c.get('/v1/cards/'+card['id']+'/history',headers=a).json()['items'])==1
    assert c.get('/v1/cards/by-client/'+body['clientId'],headers=b).status_code==404
    assert c.get('/v1/cards/by-client/'+body['clientId'],headers=a).json()['id']==card['id']


def test_alias_discovery_rate_limit_is_persistent_and_returns_retry_after(data):
    app,c,users,(a,b,d),deck,*_=data
    for _ in range(10):
        assert c.post('/v1/collaboration/contacts/requests',headers=a,json={'alias':'missing_person'}).status_code==404
    response=c.post('/v1/collaboration/contacts/requests',headers=a,json={'alias':'missing_person'})
    assert response.status_code==429 and response.headers['retry-after']=='60'


def test_optional_notices_respect_silence_and_frequency(data,monkeypatch):
    from app import notifications
    class Frozen(datetime):
        @classmethod
        def now(cls,tz=None):
            value=datetime(2026,11,6,12,tzinfo=timezone.utc)
            return value.astimezone(tz) if tz else value.replace(tzinfo=None)
    monkeypatch.setattr(notifications,'datetime',Frozen)
    app,c,users,(a,b,d),deck,*_=data
    p=c.get('/v1/account/profile',headers=b).json()
    settings={**p['data'],'collaborationNotifications':True,'noticeDailyLimit':1,'quietStart':'12:00','quietEnd':'14:00'}
    c.put('/v1/account/profile',headers={**b,'If-Match':str(p['revision'])},json=settings)
    for h in [a,d]:assert c.post('/v1/collaboration/contacts/requests',headers=h,json={'alias':'person_1'}).status_code==201
    assert c.get('/v1/notifications',headers=b).json()['items']==[]
    p=c.get('/v1/account/profile',headers=b).json();settings={**p['data'],'quietStart':'00:00','quietEnd':'00:00'}
    c.put('/v1/account/profile',headers={**b,'If-Match':str(p['revision'])},json=settings)
    notices=c.get('/v1/notifications',headers=b).json()['items']
    assert len(notices)==1 and notices[0]['category']=='collaboration'
    assert len(c.get('/v1/notifications',headers=b).json()['items'])==1
    assert c.get('/v1/notifications',headers=a).json()['items']==[]


def test_group_members_and_resources_are_paged_without_leaking_outsiders(data):
    from app.db import Account,Record
    from app.collaboration import Membership
    app,c,users,(a,b,d),deck,*_=data
    group=c.post('/v1/collaboration/groups',headers=a,json={'name':'Paginación'}).json()
    with app.state.factory() as s:
        for i in range(5):
            user=Account(id=f'paged-user-{i}');s.add(user);s.flush()
            s.add(Membership(target_id=group['id'],user_id=user.id,role='member'))
            material=Record(id=f'paged-deck-{i}',kind='deck',owner=users[0]['userId'],data={'title':f'Mazo {i}'})
            s.add(material);s.flush()
            s.add(Record(id=f'paged-resource-{i}',kind='group_resource',owner=users[0]['userId'],data={'groupId':group['id'],'deckId':material.id,'topic':'Tema'}))
        s.commit()
    path='/v1/collaboration/groups/'+group['id']
    assert c.get(path,headers=b).status_code==404
    first=c.get(path+'?limit=2',headers=a).json()
    assert len(first['members'])==3 and len(first['resources'])==2
    next_page=c.get(path,headers=a,params={'limit':2,'membersCursor':first['membersNextCursor'],'resourcesCursor':first['resourcesNextCursor']}).json()
    assert len(next_page['members'])==2 and len(next_page['resources'])==2
    assert not ({x['id'] for x in first['members']} & {x['id'] for x in next_page['members']})
    assert not ({x['id'] for x in first['resources']} & {x['id'] for x in next_page['resources']})


def test_v1_public_switch_blocks_old_approvals_but_preserves_private_sharing(data, monkeypatch):
    monkeypatch.delenv('PUBLIC_DECK_PUBLICATION_ENABLED', raising=False)
    app,c,users,(owner,reader,outsider),deck,card,body=data
    path='/v1/collaboration/decks/'+deck['id']
    publication=path+'/publication'
    with app.state.factory() as session:
        session.add(Record(id=deck['id']+':publication',kind='deck_publication',owner=users[0]['userId'],
                           data={'deckId':deck['id'],'state':'allowed'}))
        session.commit()
    assert c.get('/health').json()['publicDeckPublicationEnabled'] is False
    assert c.get('/v1/collaboration/catalogue').status_code==404
    assert c.post(publication,headers=owner,json={'confirmation':'PUBLICAR'}).status_code==404
    assert c.get(path,headers=outsider).status_code==404
    assert c.post(path+'/copy',headers=outsider).status_code==404
    assert c.get(path,headers=owner).status_code==200
    private_invitation=invite(c,owner,deck['id'],'reader')
    assert accept(c,reader,private_invitation).status_code==200
    assert c.get(path,headers=reader).status_code==200
    assert c.post(path+'/copy',headers=reader).status_code==201
    monkeypatch.setenv('PUBLIC_DECK_PUBLICATION_ENABLED','true')
    assert c.get(path,headers=outsider).status_code==200
    monkeypatch.setenv('PUBLIC_DECK_PUBLICATION_ENABLED','false')
    assert c.get(path,headers=outsider).status_code==404
    assert c.get(path,headers=reader).status_code==200
    assert c.delete(publication,headers=owner).status_code==200
