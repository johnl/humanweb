
sys = require 'sys'
xmpp = require 'node-xmpp'
argv = process.argv
http = require 'http'

if argv.length != 5
	 console.error "Usage: <jid> <password> <receiverjid>"
	 process.exit 1


client = new xmpp.Client { jid: argv[2], password: argv[3]  }

client.buddies = {}

client.iq = (query, to = undefined, type = 'get') ->
  attrs = { type: type }
  attrs.to = to if to
  client.send(new xmpp.Element('iq', attrs).cnode(query).tree());

client.getRoster = () ->
  client.iq new xmpp.Element('query', { xmlns: 'jabber:iq:roster' })

client.syncSubscription = (q) ->
  if q.jid
    jid = q.jid
    subscription = q.subscription
  else
    console.error 'HOLI SHITBURGERS'
  if subscription == 'from'
    console.log 'Subscribing to ' + jid
    client.send new xmpp.Element('presence', { to: jid, type: 'subscribe' })
  if subscription == 'both'
    console.log 'Already subscribed to ' + jid

receiver = argv[4]

client.on 'online', () ->
  console.log "Connected to xmpp server"
  e = new xmpp.Element('presence', {})
  e.c('show').t('chat').up().c('status').t('Ask me a question!')
  client.send e
  client.getRoster()

client.on 'stanza', (stanza) ->
  if stanza.is('message') and (stanza.attrs.type == 'chat')
    stanza.attrs.to = stanza.attrs.from
    delete stanza.attrs.from
    client.send(stanza)
  if stanza.is('iq')
    # roster response
    if stanza.attrs.type == 'result' and stanza.children[0].attrs.xmlns == 'jabber:iq:roster'
      console.log 'Received jabber:iq:roster'
      roster = stanza.children[0]
      roster.children.forEach (e) ->
        console.log e
        client.syncSubscription e.attrs
    console.log "Sending pong."
    client.send(new xmpp.Element('iq', { to : stanza.attrs.from, id : 'c2s1', type : 'result' }))
  if stanza.is('presence')
    switch stanza.attrs.type
      when 'subscribe'
        console.log "Subscribing user " + stanza.attrs.from
        e = new xmpp.Element('presence', { to : stanza.attrs.from, type : 'subscribed' })
        client.send e
      when 'unavailable'
        console.log "Now unavailable: " + stanza.attrs.from
        client.buddies[stanza.attrs.from] = undefined
      else
        console.log "Probably available: " + stanza.attrs.from
        client.buddies[stanza.attrs.from] = true

client.on 'error', (e) ->
  console.error('Error: ' + e)

server = http.createServer( (req, res) ->
  console.log "Received request"
  res.writeHead 200, {'Content-Type': 'text/plain'}
  res.end 'Hello World\n'
  e = new xmpp.Element 'message', { to: receiver, type: 'chat' }
  e.c('body').t req.url
  client.send e
)

server.listen 5000
